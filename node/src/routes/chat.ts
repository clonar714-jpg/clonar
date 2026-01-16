/**
 * ✅ /api/chat endpoint: New APISearchAgent-based chat endpoint
 * Matches client expectations from React ChatProvider
 */

import express, { Request, Response } from 'express';
import { z } from 'zod';
import { randomUUID } from 'crypto';
import APISearchAgent, { SessionManager } from '../agent/APISearchAgent';
import { sessionStore } from '../agent/sessionStore';
import { buildAgentConfig } from '../utils/agentConfigHelper';
import { SearchSources } from '../agent/types';
import ModelRegistry from '../models/registry';

const router = express.Router();

// Request body schema matching client expectations
const chatRequestSchema = z.object({
  content: z.string().optional(), // Legacy field
  message: z.object({
    messageId: z.string(),
    chatId: z.string(),
    content: z.string(),
  }),
  chatId: z.string(),
  files: z.array(z.string()).optional().default([]),
  sources: z.array(z.string()).optional().default(['web']),
  optimizationMode: z.enum(['speed', 'balanced', 'quality']).optional().default('balanced'),
  history: z.array(z.tuple([z.string(), z.string()])).optional().default([]),
  chatModel: z.object({
    key: z.string(),
    providerId: z.string(),
  }),
  embeddingModel: z.object({
    key: z.string(),
    providerId: z.string(),
  }),
  systemInstructions: z.string().optional().default(''),
});

/**
 * POST /api/chat
 * Main chat endpoint using APISearchAgent
 */
router.post('/', async (req: Request, res: Response) => {
  try {
    // Validate request body
    const validation = chatRequestSchema.safeParse(req.body);
    if (!validation.success) {
      return res.status(400).json({
        message: 'Invalid request body',
        error: validation.error.errors,
      });
    }

    const body = validation.data;
    const query = body.content || body.message.content;
    
    if (!query || query.trim() === '') {
      return res.status(400).json({
        message: 'Please provide a message to process',
      });
    }

    // Convert history format from [['human', '...'], ['assistant', '...']] to ChatTurnMessage[]
    const chatHistory = body.history.map(([role, content]) => ({
      role: role === 'human' ? 'user' : 'assistant',
      content,
    }));

    // Create session
    const session = SessionManager.createSession();
    
    // ✅ CRITICAL: Create AbortController to cancel operations on disconnect
    const abortController = new AbortController();
    
    // ✅ CRITICAL: Set up SSE headers IMMEDIATELY before any async work
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    // ✅ CRITICAL: Flush headers immediately to establish connection
    if (typeof res.flushHeaders === 'function') {
      res.flushHeaders();
    }
    
    // ✅ CRITICAL: Send initial heartbeat to keep connection alive
    res.write(': heartbeat\n\n');
    
    // ✅ CRITICAL: Send start event immediately with eventId for idempotency
    const startEventId = randomUUID();
    res.write(`data: ${JSON.stringify({ type: 'start', message: 'Processing query...', eventId: startEventId, sessionId: session.id })}\n\n`);
    
    // ✅ CRITICAL: Track if we've sent final event to prevent duplicate writes
    let finalEventSent = false;
    
    // ✅ TASK 1: Helper function to safely terminate SSE stream on abort
    const terminateSSE = (reason: 'aborted' | 'closed') => {
      if (finalEventSent || res.closed || res.destroyed) {
        return; // Already terminated or closed
      }
      
      finalEventSent = true;
      clearInterval(heartbeatInterval);
      
      try {
        // Emit final event before closing
        const finalEvent = {
          type: reason === 'aborted' ? 'error' : 'end',
          data: reason === 'aborted' ? 'Connection aborted by client' : undefined,
          eventId: randomUUID(),
          sessionId: session.id,
        };
        res.write(`data: ${JSON.stringify(finalEvent)}\n\n`);
        res.end();
        console.log(`🔌 SSE stream terminated: ${reason}`);
      } catch (error) {
        // Ignore write errors if connection is already closed
        if (!res.closed && !res.destroyed) {
          console.error('Error terminating SSE stream:', error);
        }
      }
    };
    
    // Handle client disconnect - abort all operations
    // ✅ FIX: req.on('close') fires when request body is read, not when connection closes
    // For SSE, we care about res.closed, not req.closed
    let clientDisconnected = false;
    req.on('close', () => {
      // Request stream closed (body read complete) - this is normal for POST requests
      // Don't treat this as connection close - check res.closed instead
      if (res.closed || res.destroyed) {
        if (!clientDisconnected) {
          console.log('🔌 Client disconnected - aborting operations');
          clientDisconnected = true;
          abortController.abort(); // ✅ CRITICAL: Signal all operations to stop
          terminateSSE('closed'); // ✅ TASK 1: Properly terminate SSE stream
        }
      }
      // If response is still open, connection is still alive - don't clear heartbeat
    });
    
    // ✅ CRITICAL: Also listen for actual response close (real disconnect)
    res.on('close', () => {
      if (!clientDisconnected) {
        console.log('🔌 Response stream closed - aborting operations');
        clientDisconnected = true;
        abortController.abort(); // ✅ CRITICAL: Signal all operations to stop
        terminateSSE('closed'); // ✅ TASK 1: Properly terminate SSE stream
      }
    });
    
    // ✅ TASK 1: Listen for abort signal and terminate SSE stream
    abortController.signal.addEventListener('abort', () => {
      if (!clientDisconnected) {
        console.log('🔌 Abort signal received - terminating SSE stream');
        clientDisconnected = true;
        terminateSSE('aborted'); // ✅ TASK 1: Emit final event and close stream
      }
    });

    // ✅ SSE Heartbeat: Send keep-alive every 15 seconds
    const heartbeatInterval = setInterval(() => {
      // ✅ FIX: Only check res.closed - req.closed is true when body is read (normal)
      if (res.closed || res.destroyed) {
        clearInterval(heartbeatInterval);
        return;
      }
      try {
        res.write(': heartbeat\n\n');
      } catch (error) {
        clearInterval(heartbeatInterval);
      }
    }, 15000);

    // Track if we've logged the connection closed message to avoid spam
    let connectionClosedLogged = false;
    
    // Subscribe to session events and stream to client in SSE format
    session.subscribe((event: string, data?: any) => {
      // ✅ TASK 1: Prevent writes after abort or final event sent
      if (finalEventSent || res.closed || res.destroyed || abortController.signal.aborted) {
        // Only log once to avoid spam
        if (!connectionClosedLogged) {
          console.log(`⚠️ Connection closed/aborted, agent will continue but events won't be sent`);
          connectionClosedLogged = true;
        }
        if (event === 'end' || event === 'error') {
          clearInterval(heartbeatInterval);
        }
        return;
      }

      try {
        if (event === 'data') {
          // ✅ SSE FORMAT: Stream block, updateBlock, or researchComplete events
          // Format: data: {json}\n\n
          // ✅ CRITICAL: Add eventId and sessionId for idempotency
          const eventData = {
            ...data,
            eventId: randomUUID(),
            sessionId: session.id,
          };
          
          // ✅ DEBUG: Log reasoning blocks being sent
          if (data?.type === 'block' && data?.block?.type === 'text' && data?.block?.data?.startsWith('💭')) {
            console.log(`📤📤📤 SENDING REASONING BLOCK TO FRONTEND: "${data.block.data.substring(0, 100)}..."`);
          }
          
          const json = JSON.stringify(eventData);
          res.write(`data: ${json}\n\n`);
          // ✅ CRITICAL: Flush immediately to ensure data is sent to client
          if (typeof res.flush === 'function') {
            res.flush();
          }
        } else if (event === 'end') {
          // ✅ TASK 1: Mark final event sent to prevent duplicate writes
          if (!finalEventSent) {
            finalEventSent = true;
            clearInterval(heartbeatInterval);
            if (!res.closed && !res.destroyed) {
              // ✅ Include follow-up suggestions and other data from end event
              const endEventData = {
                type: 'end',
                eventId: randomUUID(),
                sessionId: session.id,
                ...(data && typeof data === 'object' ? data : {}), // Include followUpSuggestions and other data
              };
              res.write(`data: ${JSON.stringify(endEventData)}\n\n`);
              res.end();
            }
          }
        } else if (event === 'error') {
          // ✅ TASK 1: Mark final event sent to prevent duplicate writes
          if (!finalEventSent) {
            finalEventSent = true;
            clearInterval(heartbeatInterval);
            if (!res.closed && !res.destroyed) {
              res.write(`data: ${JSON.stringify({ type: 'error', data: data?.data || 'An error occurred', eventId: randomUUID(), sessionId: session.id })}\n\n`);
              res.end();
            }
          }
        }
      } catch (error) {
        console.error('Error streaming response:', error);
        clearInterval(heartbeatInterval);
        // Don't try to send error if connection is already closed
        if (!res.headersSent && !res.closed && !res.destroyed) {
          try {
            res.status(500).json({ message: 'Streaming error' });
          } catch (e) {
            // Connection already closed, ignore
          }
        }
      }
    });

    // ✅ IMPROVEMENT: Use ModelRegistry to load models (supports multiple providers)
    const modelRegistry = new ModelRegistry();
    
    let llm;
    let embedding = null;
    
    try {
      // Load chat model from registry (supports both provider ID and type)
      llm = await modelRegistry.loadChatModel(
        body.chatModel.providerId,
        body.chatModel.key
      );
      
      // Load embedding model if provided
      if (body.embeddingModel) {
        embedding = await modelRegistry.loadEmbeddingModel(
          body.embeddingModel.providerId,
          body.embeddingModel.key
        );
      }
    } catch (error: any) {
      console.error('❌ Failed to load models from registry:', error);
      console.error('   Provider ID/Type sent:', body.chatModel.providerId);
      console.error('   Active providers:', modelRegistry.activeProviders.map(p => ({ id: p.id, type: p.type, name: p.name })));
      // ✅ CRITICAL: Send error via SSE, don't close with JSON response
      clearInterval(heartbeatInterval);
      if (!res.closed && !res.destroyed) {
        res.write(`data: ${JSON.stringify({ type: 'error', data: `Failed to load models: ${error.message}` })}\n\n`);
        res.end();
      }
      return;
    }

    // Build agent config
    const agentConfig = buildAgentConfig(req, {
      llm,
      embedding,
      sources: (body.sources || ['web']) as SearchSources[],
      mode: body.optimizationMode || 'balanced',
    });

    // Create agent and start search (don't await - let it run async)
    console.log('🚀 Starting agent search...');
    const agent = new APISearchAgent();
    
    // ✅ CRITICAL: Wrap in try-catch to prevent unhandled promise rejection from closing connection
    // ✅ CRITICAL: Pass abortSignal to agent for cancellation support
    agent.searchAsync(session, {
      chatHistory,
      followUp: query,
      chatId: body.chatId,
      messageId: body.message.messageId,
      config: agentConfig,
      abortSignal: abortController.signal, // ✅ CRITICAL: Pass abort signal
    }).catch((error) => {
      // Don't log if aborted (expected behavior)
      if (error.name !== 'AbortError') {
        console.error('❌ Agent error:', error);
        console.error('❌ Agent error stack:', error.stack);
      }
      clearInterval(heartbeatInterval);
      // Emit error through session (will be handled by subscription handler)
      session.emit('error', { data: error.message || 'An error occurred' });
    });

  } catch (err: any) {
    console.error('❌ Error in chat endpoint:', err);
    console.error('❌ Error stack:', err.stack);
    // ✅ CRITICAL: If headers are already sent (SSE started), send error via SSE
    if (res.headersSent) {
      try {
        res.write(`data: ${JSON.stringify({ type: 'error', data: err.message || 'An error occurred while processing chat request' })}\n\n`);
        res.end();
      } catch (e) {
        // Connection already closed, ignore
      }
    } else {
      return res.status(500).json({
        message: 'An error occurred while processing chat request',
      });
    }
  }
});

export default router;


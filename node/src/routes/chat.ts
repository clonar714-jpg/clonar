

import express, { Request, Response } from 'express';
import { z } from 'zod';
import { randomUUID } from 'crypto';
import APISearchAgent, { SessionManager } from '../agent/APISearchAgent';
import { sessionStore } from '../agent/sessionStore';
import { buildAgentConfig } from '../utils/agentConfigHelper';
import { SearchSources } from '../agent/types';
import ModelRegistry from '../models/registry';

const router = express.Router();


const chatRequestSchema = z.object({
  content: z.string().optional(), 
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


router.post('/', async (req: Request, res: Response) => {
  try {
    
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

    
    const chatHistory = body.history.map(([role, content]) => ({
      role: role === 'human' ? 'user' : 'assistant',
      content,
    }));

    
    const session = SessionManager.createSession();
    
    
    const abortController = new AbortController();
    
    
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    
    if (typeof res.flushHeaders === 'function') {
      res.flushHeaders();
    }
    
    
    res.write(': heartbeat\n\n');
    
    
    const startEventId = randomUUID();
    res.write(`data: ${JSON.stringify({ type: 'start', message: 'Processing query...', eventId: startEventId, sessionId: session.id })}\n\n`);
    
    
    let finalEventSent = false;
    
    
    const terminateSSE = (reason: 'aborted' | 'closed') => {
      if (finalEventSent || res.closed || res.destroyed) {
        return; 
      }
      
      finalEventSent = true;
      clearInterval(heartbeatInterval);
      
      try {
        
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
        
        if (!res.closed && !res.destroyed) {
          console.error('Error terminating SSE stream:', error);
        }
      }
    };
    
   
    let clientDisconnected = false;
    req.on('close', () => {
      
      if (res.closed || res.destroyed) {
        if (!clientDisconnected) {
          console.log('🔌 Client disconnected - aborting operations');
          clientDisconnected = true;
          abortController.abort(); 
          terminateSSE('closed'); 
        }
      }
      
    });
    
    
    res.on('close', () => {
      if (!clientDisconnected) {
        console.log('🔌 Response stream closed - aborting operations');
        clientDisconnected = true;
        abortController.abort(); 
        terminateSSE('closed'); 
      }
    });
    
   
    abortController.signal.addEventListener('abort', () => {
      if (!clientDisconnected) {
        console.log('🔌 Abort signal received - terminating SSE stream');
        clientDisconnected = true;
        terminateSSE('aborted'); 
      }
    });

    
    const heartbeatInterval = setInterval(() => {
      
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

    
    let connectionClosedLogged = false;
    
   
    session.subscribe((event: string, data?: any) => {
      
      if (finalEventSent || res.closed || res.destroyed || abortController.signal.aborted) {
        
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
          
          const eventData = {
            ...data,
            eventId: randomUUID(),
            sessionId: session.id,
          };
          
          
          if (data?.type === 'block' && data?.block?.type === 'text' && data?.block?.data?.startsWith('💭')) {
            console.log(`📤📤📤 SENDING REASONING BLOCK TO FRONTEND: "${data.block.data.substring(0, 100)}..."`);
          }
          
          const json = JSON.stringify(eventData);
          res.write(`data: ${json}\n\n`);
          
          if (typeof res.flush === 'function') {
            res.flush();
          }
        } else if (event === 'end') {
          
          if (!finalEventSent) {
            finalEventSent = true;
            clearInterval(heartbeatInterval);
            if (!res.closed && !res.destroyed) {
              
              const endEventData = {
                type: 'end',
                eventId: randomUUID(),
                sessionId: session.id,
                ...(data && typeof data === 'object' ? data : {}), 
              };
              res.write(`data: ${JSON.stringify(endEventData)}\n\n`);
              res.end();
            }
          }
        } else if (event === 'error') {
          
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
        
        if (!res.headersSent && !res.closed && !res.destroyed) {
          try {
            res.status(500).json({ message: 'Streaming error' });
          } catch (e) {
            
          }
        }
      }
    });

    
    const modelRegistry = new ModelRegistry();
    
    let llm;
    let embedding = null;
    
    try {
      
      llm = await modelRegistry.loadChatModel(
        body.chatModel.providerId,
        body.chatModel.key
      );
      
      
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
     
      clearInterval(heartbeatInterval);
      if (!res.closed && !res.destroyed) {
        res.write(`data: ${JSON.stringify({ type: 'error', data: `Failed to load models: ${error.message}` })}\n\n`);
        res.end();
      }
      return;
    }

    
    const agentConfig = buildAgentConfig(req, {
      llm,
      embedding,
      sources: (body.sources || ['web']) as SearchSources[],
      mode: body.optimizationMode || 'balanced',
    });

    
    console.log('🚀 Starting agent search...');
    const agent = new APISearchAgent();
    
    
    agent.searchAsync(session, {
      chatHistory,
      followUp: query,
      chatId: body.chatId,
      messageId: body.message.messageId,
      config: agentConfig,
      abortSignal: abortController.signal, 
    }).catch((error) => {
      
      if (error.name !== 'AbortError') {
        console.error('❌ Agent error:', error);
        console.error('❌ Agent error stack:', error.stack);
      }
      clearInterval(heartbeatInterval);
      
      session.emit('error', { data: error.message || 'An error occurred' });
    });

  } catch (err: any) {
    console.error('❌ Error in chat endpoint:', err);
    console.error('❌ Error stack:', err.stack);
    
    if (res.headersSent) {
      try {
        res.write(`data: ${JSON.stringify({ type: 'error', data: err.message || 'An error occurred while processing chat request' })}\n\n`);
        res.end();
      } catch (e) {
        
      }
    } else {
      return res.status(500).json({
        message: 'An error occurred while processing chat request',
      });
    }
  }
});

export default router;


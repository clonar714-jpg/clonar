/**
 * ✅ /api/reconnect/:backendId endpoint
 * Reconnects to an existing session and streams remaining blocks
 */

import express, { Request, Response } from 'express';
import { sessionStore } from '../agent/sessionStore';

const router = express.Router();

/**
 * POST /api/reconnect/:backendId
 * Reconnect to an existing session
 */
router.post('/:backendId', async (req: Request, res: Response) => {
  try {
    const { backendId } = req.params;

    if (!backendId) {
      return res.status(400).json({
        message: 'backendId is required',
      });
    }

    // Get session from store
    const session = sessionStore.get(backendId);

    if (!session) {
      return res.status(404).json({
        message: 'Session not found',
      });
    }

    // Set up streaming response
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('Cache-Control', 'no-cache, no-transform');

    // Handle client disconnect
    req.on('close', () => {
      // Don't remove listeners - session might still be active
    });

    // ✅ IMPROVEMENT 1: Subscribe to session - event replay will automatically send all past events
    // This includes: blocks, updateBlocks, researchComplete, end, error - in correct order
    const unsubscribe = session.subscribe((event: string, data?: any) => {
      if (req.closed || res.closed) {
        unsubscribe(); // Clean up subscription on disconnect
        return;
      }

      try {
        if (event === 'data') {
          // ✅ IMPROVEMENT 1: Event replay ensures all events are sent in correct order
          // Format as SSE: data: {json}\n\n
          const json = JSON.stringify(data);
          res.write(`data: ${json}\n\n`);
          // Flush immediately
          if (typeof res.flush === 'function') {
            res.flush();
          }
        } else if (event === 'end') {
          // ✅ IMPROVEMENT 1: End event from replay or new
          const json = JSON.stringify({ type: 'end', eventId: data?.eventId, sessionId: data?.sessionId || session.id });
          res.write(`data: ${json}\n\n`);
          res.end();
          unsubscribe();
        } else if (event === 'error') {
          // ✅ IMPROVEMENT 1: Error event from replay or new
          const json = JSON.stringify({ type: 'error', data: data?.data || 'An error occurred', eventId: data?.eventId, sessionId: data?.sessionId || session.id });
          res.write(`data: ${json}\n\n`);
          res.end();
          unsubscribe();
        }
      } catch (error) {
        console.error('Error streaming reconnect response:', error);
        unsubscribe(); // Clean up on error
        if (!res.headersSent) {
          res.status(500).json({ message: 'Streaming error' });
        }
      }
    });

  } catch (err: any) {
    console.error('Error in reconnect endpoint:', err);
    if (!res.headersSent) {
      return res.status(500).json({
        message: 'An error occurred while reconnecting',
      });
    }
  }
});

export default router;


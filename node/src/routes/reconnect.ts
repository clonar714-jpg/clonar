

import express, { Request, Response } from 'express';
import { sessionStore } from '../agent/sessionStore';

const router = express.Router();


router.post('/:backendId', async (req: Request, res: Response) => {
  try {
    const { backendId } = req.params;

    if (!backendId) {
      return res.status(400).json({
        message: 'backendId is required',
      });
    }

    
    const session = sessionStore.get(backendId);

    if (!session) {
      return res.status(404).json({
        message: 'Session not found',
      });
    }

   
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('Cache-Control', 'no-cache, no-transform');

    
    req.on('close', () => {
      
    });

    
    const unsubscribe = session.subscribe((event: string, data?: any) => {
      if (req.closed || res.closed) {
        unsubscribe(); 
        return;
      }

      try {
        if (event === 'data') {
          
          const json = JSON.stringify(data);
          res.write(`data: ${json}\n\n`);
          
          if (typeof res.flush === 'function') {
            res.flush();
          }
        } else if (event === 'end') {
          
          const json = JSON.stringify({ type: 'end', eventId: data?.eventId, sessionId: data?.sessionId || session.id });
          res.write(`data: ${json}\n\n`);
          res.end();
          unsubscribe();
        } else if (event === 'error') {
          
          const json = JSON.stringify({ type: 'error', data: data?.data || 'An error occurred', eventId: data?.eventId, sessionId: data?.sessionId || session.id });
          res.write(`data: ${json}\n\n`);
          res.end();
          unsubscribe();
        }
      } catch (error) {
        console.error('Error streaming reconnect response:', error);
        unsubscribe(); 
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


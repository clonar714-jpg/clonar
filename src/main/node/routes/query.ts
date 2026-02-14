
import express, { Request, Response, NextFunction } from 'express';
import { runPipeline } from '@/services/orchestrator';
import { runPipelineStream } from '@/services/orchestrator-stream';
import { getPipelineDeps } from '@/services/pipeline-deps';
import { getSession } from '@/services/session/sessionMemory';
import { getUserMemory } from '@/services/session/userMemory';
import { getAndClearLastFeedback } from '@/services/feedback-store';
import { logger } from '@/utils/logger';
import type { QueryContext, QueryMode } from '@/types/core';

const router = express.Router();
const deps = getPipelineDeps();

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function normalizeQueryMode(rawMode: unknown): QueryMode {
  if (rawMode === 'deep' || rawMode === 'pro') return 'deep';
 
  return 'quick';
}

function buildPipelineContext(params: {
  message: unknown;
  history: unknown;
  userId?: unknown;
  mode: unknown;
  sessionId?: unknown;
}): QueryContext {
  if (!isNonEmptyString(params.message)) {
    throw new Error('message is required and must be a non-empty string');
  }

  const message = params.message.trim();
  const mode = normalizeQueryMode(params.mode);

  let history: string[] = [];
  if (Array.isArray(params.history)) {
    history = (params.history as string[])
      .filter((h) => isNonEmptyString(h))
      .map((h) => h.trim())
      .slice(-5); // keep last 5 only
  }

  const userId =
    typeof params.userId === 'string' && params.userId.length > 0
      ? params.userId
      : undefined;

  const sessionId =
    typeof params.sessionId === 'string' && params.sessionId.length > 0
      ? params.sessionId
      : undefined;

  return { message, history, userId, mode, sessionId };
}

function sendJsonError(res: Response, status: number, code: string, details?: unknown) {
  return res.status(status).json({
    error: code,
    details:
      typeof details === 'object' ? JSON.stringify(details) : details ?? undefined,
  });
}

function writeSseEvent(res: Response, event: string, data: unknown) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

router.post('/', async (req: Request, res: Response, _next: NextFunction) => {
  try {
    const { message, history, userId, mode, sessionId: bodySessionId } = req.body ?? {};

    let ctx: QueryContext;
    try {
      ctx = buildPipelineContext({ message, history, userId, mode, sessionId: bodySessionId });
    } catch (validationErr: unknown) {
      const errMessage = validationErr instanceof Error ? validationErr.message : String(validationErr);
      logger.warn('POST /api/query validation failed', { error: errMessage });
      return sendJsonError(res, 400, 'bad_request', errMessage);
    }

    
    const sessionKey = ctx.sessionId ?? ctx.userId;
    if (sessionKey) {
      try {
        const sessionState = await getSession(sessionKey);
        if (sessionState) {
          if (sessionState.conversationThread?.length) ctx.conversationThread = sessionState.conversationThread;
          if (sessionState.lastHotelFilters) ctx.lastHotelFilters = sessionState.lastHotelFilters;
          if (sessionState.lastFlightFilters) ctx.lastFlightFilters = sessionState.lastFlightFilters;
          if (sessionState.lastMovieFilters) ctx.lastMovieFilters = sessionState.lastMovieFilters;
          if (sessionState.lastProductFilters) ctx.lastProductFilters = sessionState.lastProductFilters;
          if (sessionState.lastSuccessfulVertical) ctx.lastSuccessfulVertical = sessionState.lastSuccessfulVertical;
          if (sessionState.lastResultStrength) ctx.lastResultStrength = sessionState.lastResultStrength;
        }
        ctx.sessionId = sessionKey;
      } catch (err) {
        logger.warn('getSession failed', { sessionKey, err: err instanceof Error ? err.message : String(err) });
      }
    }
    
    if (ctx.userId) {
      try {
        const memory = await getUserMemory(ctx.userId);
        if (memory) ctx.userMemory = memory;
      } catch (err) {
        logger.warn('getUserMemory failed', { userId: ctx.userId });
      }
    }

    logger.info('flow:request_context', {
      step: 'request_context',
      messagePreview: ctx.message.slice(0, 100),
      mode: ctx.mode,
      sessionId: ctx.sessionId ?? null,
      hasConversationThread: (ctx.conversationThread?.length ?? 0) > 0,
      threadTurns: ctx.conversationThread?.length ?? 0,
      hasPreviousFeedback: !!ctx.previousFeedback,
      previousFeedbackThumb: ctx.previousFeedback?.thumb ?? null,
      hasUserMemory: !!ctx.userMemory && Object.keys(ctx.userMemory).length > 0,
      lastHotelFilters: !!ctx.lastHotelFilters,
      lastFlightFilters: !!ctx.lastFlightFilters,
      lastProductFilters: !!ctx.lastProductFilters,
      lastMovieFilters: !!ctx.lastMovieFilters,
    });
    const result = await runPipeline(ctx, deps);
    res.json(result);
  } catch (err: unknown) {
    const errMessage = err instanceof Error ? err.message : String(err);
    logger.error('POST /api/query failed', { error: errMessage });
    const details = err && typeof err === 'object' && 'response' in err
      ? (err as { response?: { data?: unknown } }).response?.data
      : errMessage;
    return sendJsonError(res, 500, 'internal_error', details ?? errMessage);
  }
});


function parseConversationThread(raw: unknown): Array<{ query: string; answer: string }> | undefined {
  if (typeof raw !== 'string' || !raw.trim()) return undefined;
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return undefined;
    const out: Array<{ query: string; answer: string }> = [];
    for (const item of parsed) {
      if (item && typeof item.query === 'string' && typeof item.answer === 'string') {
        out.push({ query: item.query.trim(), answer: item.answer.trim() });
      }
    }
    return out.length > 0 ? out.slice(-5) : undefined;
  } catch {
    return undefined;
  }
}

router.get('/stream', async (req: Request, res: Response) => {
  const startedAt = Date.now();
  const {
    message: rawMessage,
    history: rawHistory,
    mode: rawMode,
    userId,
    sessionId: querySessionId,
    conversationThread: rawConversationThread,
  } = req.query;

  let parsedHistory: string[] = [];
  if (typeof rawHistory === 'string' && rawHistory.length > 0) {
    try {
      const parsed = JSON.parse(rawHistory);
      if (Array.isArray(parsed)) {
        parsedHistory = parsed as string[];
      }
    } catch (err) {
      logger.warn('Failed to parse history JSON', { err });
      res.status(400).json({ error: 'invalid history JSON' });
      return;
    }
  }

  let ctx: QueryContext;
  try {
    ctx = buildPipelineContext({
      message: rawMessage,
      history: parsedHistory,
      userId,
      mode: rawMode,
      sessionId: typeof querySessionId === 'string' ? querySessionId : undefined,
    });
  } catch (validationErr: unknown) {
    const errMessage =
      validationErr instanceof Error ? validationErr.message : String(validationErr);
    logger.warn('GET /stream validation failed', { error: errMessage });
    return sendJsonError(res, 400, 'bad_request', errMessage);
  }

  const sessionKey = ctx.sessionId ?? ctx.userId;
  if (sessionKey) {
    try {
      const sessionState = await getSession(sessionKey);
      if (sessionState) {
        if (sessionState.conversationThread?.length) ctx.conversationThread = sessionState.conversationThread;
        if (sessionState.lastHotelFilters) ctx.lastHotelFilters = sessionState.lastHotelFilters;
        if (sessionState.lastFlightFilters) ctx.lastFlightFilters = sessionState.lastFlightFilters;
        if (sessionState.lastMovieFilters) ctx.lastMovieFilters = sessionState.lastMovieFilters;
        if (sessionState.lastProductFilters) ctx.lastProductFilters = sessionState.lastProductFilters;
        if (sessionState.lastSuccessfulVertical) ctx.lastSuccessfulVertical = sessionState.lastSuccessfulVertical;
        if (sessionState.lastResultStrength) ctx.lastResultStrength = sessionState.lastResultStrength;
      }
      ctx.sessionId = sessionKey;
      const lastFeedback = getAndClearLastFeedback(sessionKey);
      if (lastFeedback?.thumb === 'down') {
        ctx.previousFeedback = {
          thumb: 'down',
          reason: lastFeedback.reason,
          comment: lastFeedback.comment,
        };
      }
    } catch (err) {
      logger.warn('getSession failed (stream)', { sessionKey });
    }
  }
  const clientThread = parseConversationThread(rawConversationThread);
  if (clientThread?.length) {
    ctx.conversationThread = clientThread;
  }
  if (ctx.userId) {
    try {
      const memory = await getUserMemory(ctx.userId);
      if (memory) ctx.userMemory = memory;
    } catch (err) {
      logger.warn('getUserMemory failed (stream)', { userId: ctx.userId });
    }
  }

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  if (typeof (res as { flushHeaders?: () => void }).flushHeaders === 'function') {
    (res as { flushHeaders: () => void }).flushHeaders();
  }

  let closed = false;

  const markClosed = () => {
    if (closed) return;
    closed = true;
    logger.info('SSE client disconnected', {
      message: ctx.message.slice(0, 200),
      mode: ctx.mode,
      durationMs: Date.now() - startedAt,
    });
  };

  req.on('close', markClosed);
  res.on('close', markClosed);
  res.on('finish', markClosed);

  const safeSendEvent = (event: string, data: unknown) => {
    if (closed) return;
    writeSseEvent(res, event, data);
  };

  logger.info('flow:request_context', {
    step: 'request_context',
    stream: true,
    messagePreview: ctx.message.slice(0, 100),
    mode: ctx.mode,
    sessionId: ctx.sessionId ?? null,
    hasConversationThread: (ctx.conversationThread?.length ?? 0) > 0,
    threadTurns: ctx.conversationThread?.length ?? 0,
    hasPreviousFeedback: !!ctx.previousFeedback,
    previousFeedbackThumb: ctx.previousFeedback?.thumb ?? null,
    hasUserMemory: !!ctx.userMemory && Object.keys(ctx.userMemory).length > 0,
    lastHotelFilters: !!ctx.lastHotelFilters,
    lastFlightFilters: !!ctx.lastFlightFilters,
    lastProductFilters: !!ctx.lastProductFilters,
    lastMovieFilters: !!ctx.lastMovieFilters,
  });

  try {
    await runPipelineStream(ctx, deps, {
      onToken: (chunk) => safeSendEvent('token', chunk),
      onCitations: (citations) => safeSendEvent('citations', { citations }),
      onDone: (finalPayload) => {
        if (closed) return;
        safeSendEvent('done', finalPayload);
        logger.info('SSE pipeline completed', {
          message: ctx.message.slice(0, 200),
          mode: ctx.mode,
          durationMs: Date.now() - startedAt,
        });
        closed = true;
        res.end();
      },
    });
  } catch (err: unknown) {
    const errMessage = err instanceof Error ? err.message : String(err);
    logger.error('SSE pipeline error', {
      message: ctx.message.slice(0, 200),
      mode: ctx.mode,
      error: errMessage,
    });
    if (!closed) {
      safeSendEvent('error', { error: 'internal_error', details: errMessage });
      closed = true;
      res.end();
    }
  }
});

export default router;

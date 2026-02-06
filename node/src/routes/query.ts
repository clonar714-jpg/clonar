// src/routes/query.ts — wire retrievers (hybrid = BM25 + dense + SQL) + SSE hardening
// Order: 1) load session 2) attach conversation thread (Perplexity-style) 3) rewrite 4) query understanding.
import express, { Request, Response, NextFunction } from 'express';
import { runPipeline } from '@/services/orchestrator';
import { runPipelineStream } from '@/services/orchestrator-stream';
import { getPipelineDeps } from '@/services/pipeline-deps';
import { getSession } from '@/memory/sessionMemory';
import { getUserMemory } from '@/memory/userMemory';
import { logger } from '@/services/logger';
import type { QueryContext, QueryMode } from '@/types/core';

const router = express.Router();
const deps = getPipelineDeps();

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function normalizeQueryMode(rawMode: unknown): QueryMode {
  if (rawMode === 'deep' || rawMode === 'pro') return 'deep';
  // treat 'fast' or missing as quick
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

    // 1) Load session: conversation thread + last-used filters (Perplexity-style).
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
        }
        ctx.sessionId = sessionKey;
      } catch (err) {
        logger.warn('getSession failed', { sessionKey, err: err instanceof Error ? err.message : String(err) });
      }
    }
    // 2) Perplexity-style Memory: load user preferences when userId present.
    if (ctx.userId) {
      try {
        const memory = await getUserMemory(ctx.userId);
        if (memory) ctx.userMemory = memory;
      } catch (err) {
        logger.warn('getUserMemory failed', { userId: ctx.userId });
      }
    }

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

router.get('/stream', async (req: Request, res: Response) => {
  const startedAt = Date.now();
  const { message: rawMessage, history: rawHistory, mode: rawMode, userId, sessionId: querySessionId } = req.query;

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
      }
      ctx.sessionId = sessionKey;
    } catch (err) {
      logger.warn('getSession failed (stream)', { sessionKey });
    }
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

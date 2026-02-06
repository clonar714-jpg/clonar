/// <reference path="./types/express/index.d.ts" />

import dotenv from 'dotenv';
import path from 'path';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import compression from 'compression';

import { errorHandler } from '@/middleware/errorHandler';
import { notFoundHandler } from '@/middleware/notFoundHandler';
import queryRoutes from '@/routes/query';
import { initRedis } from '@/services/cache';
import { logger } from '@/services/logger';
import { attachCorrelationId } from '@/middleware/correlation';
import { setMetricsCallback } from '@/services/query-processing-metrics';
import { record as recordMetricsAggregator } from '@/services/metrics-aggregator';
import { queryRateLimiter } from '@/middleware/rate-limit-query';
import {
  setupUnhandledRejectionHandler,
  setupUncaughtExceptionHandler,
  setupGracefulShutdown,
  requestTimeout,
  setServerInstance,
} from '@/stability/errorHandlers';

const app = express();
const PORT = parseInt(process.env.PORT || '4000', 10);

app.use(attachCorrelationId);
app.use((req: express.Request, _res, next) => {
  logger.info('http:request', {
    method: req.method,
    path: req.path,
    correlationId: (req as express.Request & { correlationId?: string }).correlationId,
  });
  next();
});

app.use(helmet());
app.use(
  cors({
    origin: process.env.NODE_ENV === 'development' ? '*' : (process.env.CORS_ORIGIN?.split(',') || ['http://localhost:3000']),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept'],
  })
);
app.use(requestTimeout(15000));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(compression());

if (process.env.NODE_ENV === 'development') {
  app.use(morgan('dev'));
} else {
  app.use(morgan('combined'));
}

app.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV,
  });
});

app.get('/api/test', (_req, res) => {
  res.status(200).json({
    success: true,
    message: 'Backend is reachable!',
    timestamp: new Date().toISOString(),
  });
});

app.use('/api/query', queryRateLimiter, queryRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

setupUnhandledRejectionHandler();
setupUncaughtExceptionHandler();
setupGracefulShutdown();

const startServer = async () => {
  try {
    await initRedis().catch((err) => {
      logger.warn('initRedis failed, continuing without Redis', { err: err instanceof Error ? err.message : String(err) });
    });

    setMetricsCallback(recordMetricsAggregator);

    const server = app.listen(PORT, '0.0.0.0', () => {
      logger.info('Server running', {
        port: PORT,
        env: process.env.NODE_ENV,
        health: `http://localhost:${PORT}/health`,
        query: `http://localhost:${PORT}/api/query`,
      });
      setServerInstance(server);
    });

    server.on('error', (error: NodeJS.ErrnoException) => {
      if (error.code === 'EADDRINUSE') {
        logger.error(`Port ${PORT} is already in use`);
      } else {
        logger.error('Server error', { error: error.message });
      }
      process.exit(1);
    });
  } catch (error) {
    logger.error('Failed to start server', { error: error instanceof Error ? error.message : String(error) });
    process.exit(1);
  }
};

startServer();

export default app;

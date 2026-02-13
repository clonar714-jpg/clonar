import dotenv from 'dotenv';
import path from 'path';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';

import queryRoutes from '@/routes/query';
import { initRedis } from '@/services/cache';
import { logger } from '@/services/logger';
import { setMetricsCallback } from '@/services/query-processing-metrics';
import { record as recordMetricsAggregator } from '@/services/metrics-aggregator';

const app = express();
const PORT = parseInt(process.env.PORT || '4000', 10);

app.use(helmet());
app.use(cors({ origin: process.env.NODE_ENV === 'development' ? '*' : ['http://localhost:3000'], credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV,
  });
});

app.use('/api/query', queryRoutes);

app.use((_req, res) => {
  res.status(404).json({ error: 'not_found', message: 'Not Found' });
});

app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
  res.status(500).json({ error: 'internal_error', message: 'Internal Server Error' });
});

const startServer = async () => {
  try {
    await initRedis();
    setMetricsCallback(recordMetricsAggregator);

    app.listen(PORT, '0.0.0.0', () => {
      logger.info('Server running', { port: PORT, env: process.env.NODE_ENV });
      console.log(`Server: http://localhost:${PORT}`);
      console.log(`Health: http://localhost:${PORT}/health`);
      console.log(`Query:  http://localhost:${PORT}/api/query`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
};

startServer();

export default app;

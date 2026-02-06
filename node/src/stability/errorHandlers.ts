/**
 * Minimal stubs so the server can start when running query-pipeline only.
 * Replace with real implementations for production (unhandled rejection, graceful shutdown, timeouts).
 */
import type { Request, Response, NextFunction } from 'express';
import type { Server } from 'http';

let serverInstance: Server | null = null;

export function setupUnhandledRejectionHandler(): void {
  // no-op
}

export function setupUncaughtExceptionHandler(): void {
  // no-op
}

export function setupGracefulShutdown(): void {
  // no-op
}

export function requestTimeout(_ms: number) {
  return (_req: Request, _res: Response, next: NextFunction) => next();
}

export function setServerInstance(server: Server): void {
  serverInstance = server;
}

export function getServerInstance(): Server | null {
  return serverInstance;
}

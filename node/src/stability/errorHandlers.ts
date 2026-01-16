// ✅ PHASE 10: Global Error Handlers & Stability Hardeners

import { Server } from 'http';

let serverInstance: Server | null = null;

/**
 * Set server instance for graceful shutdown
 */
export function setServerInstance(server: Server): void {
  serverInstance = server;
}

/**
 * ✅ PHASE 10: Enhanced unhandled rejection handler
 */
export function setupUnhandledRejectionHandler(): void {
  process.on('unhandledRejection', (reason: any, promise: Promise<any>) => {
    console.error('❌ Unhandled Promise Rejection:', reason);
    console.error('Promise:', promise);
    
    // Log stack trace if available
    if (reason instanceof Error) {
      console.error('Stack:', reason.stack);
    }
    
    // In production, don't exit immediately - log and continue
    if (process.env.NODE_ENV === 'production') {
      console.error('⚠️ Continuing in production mode despite unhandled rejection');
      // Could send to error tracking service here
    } else {
      // In development, exit for faster debugging
      console.error('💥 Exiting in development mode');
      process.exit(1);
    }
  });
}

/**
 * ✅ PHASE 10: Enhanced uncaught exception handler
 */
export function setupUncaughtExceptionHandler(): void {
  process.on('uncaughtException', (error: Error) => {
    console.error('❌ Uncaught Exception:', error);
    console.error('Stack:', error.stack);
    
    // Attempt graceful shutdown
    gracefulShutdown('uncaughtException');
  });
}

/**
 * ✅ PHASE 10: Graceful shutdown handler
 */
export function setupGracefulShutdown(): void {
  const signals: NodeJS.Signals[] = ['SIGTERM', 'SIGINT'];
  
  signals.forEach(signal => {
    process.on(signal, () => {
      console.log(`\n🛑 Received ${signal}, starting graceful shutdown...`);
      gracefulShutdown(signal);
    });
  });
}

/**
 * Graceful shutdown implementation
 */
async function gracefulShutdown(reason: string): Promise<void> {
  console.log(`🔄 Graceful shutdown initiated: ${reason}`);
  
  // Close server (stop accepting new requests)
  if (serverInstance) {
    serverInstance.close(() => {
      console.log('✅ HTTP server closed');
    });
  }
  
  // Give ongoing requests time to complete (15 seconds)
  const shutdownTimeout = setTimeout(() => {
    console.error('⚠️ Forced shutdown after timeout');
    process.exit(1);
  }, 15000);
  
  // Close database connections, cleanup, etc.
  try {
    // Add any cleanup logic here (database connections, file handles, etc.)
    console.log('🧹 Cleanup completed');
    clearTimeout(shutdownTimeout);
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    clearTimeout(shutdownTimeout);
    process.exit(1);
  }
}

/**
 * ✅ PHASE 10: Request timeout middleware
 * ✅ FIX: Increased timeout for agent routes (places queries can take 20-30s)
 */
export function requestTimeout(timeoutMs: number = 15000) {
  return (req: any, res: any, next: any) => {
    // ✅ FIX: Agent routes need longer timeout (places queries take 20-30s)
    const isAgentRoute = req.path === '/api/chat' || req.originalUrl?.includes('/api/chat');
    const effectiveTimeout = isAgentRoute ? 60000 : timeoutMs; // 60s for agent, 15s for others
    
    const timeout = setTimeout(() => {
      if (!res.headersSent) {
        res.status(408).json({
          error: 'Request timeout',
          message: `Request exceeded ${effectiveTimeout}ms timeout`,
        });
      }
    }, effectiveTimeout);
    
    // Clear timeout when response is sent
    res.on('finish', () => {
      clearTimeout(timeout);
    });
    
    res.on('close', () => {
      clearTimeout(timeout);
    });
    
    next();
  };
}


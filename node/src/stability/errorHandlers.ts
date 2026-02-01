

import { Server } from 'http';

let serverInstance: Server | null = null;


export function setServerInstance(server: Server): void {
  serverInstance = server;
}


export function setupUnhandledRejectionHandler(): void {
  process.on('unhandledRejection', (reason: any, promise: Promise<any>) => {
    console.error('❌ Unhandled Promise Rejection:', reason);
    console.error('Promise:', promise);
    
    
    if (reason instanceof Error) {
      console.error('Stack:', reason.stack);
    }
    
   
    if (process.env.NODE_ENV === 'production') {
      console.error('⚠️ Continuing in production mode despite unhandled rejection');
      
    } else {
      
      console.error('💥 Exiting in development mode');
      process.exit(1);
    }
  });
}


export function setupUncaughtExceptionHandler(): void {
  process.on('uncaughtException', (error: Error) => {
    console.error('❌ Uncaught Exception:', error);
    console.error('Stack:', error.stack);
    
   
    gracefulShutdown('uncaughtException');
  });
}


export function setupGracefulShutdown(): void {
  const signals: NodeJS.Signals[] = ['SIGTERM', 'SIGINT'];
  
  signals.forEach(signal => {
    process.on(signal, () => {
      console.log(`\n🛑 Received ${signal}, starting graceful shutdown...`);
      gracefulShutdown(signal);
    });
  });
}


async function gracefulShutdown(reason: string): Promise<void> {
  console.log(`🔄 Graceful shutdown initiated: ${reason}`);
  
  
  if (serverInstance) {
    serverInstance.close(() => {
      console.log('✅ HTTP server closed');
    });
  }
  
  
  const shutdownTimeout = setTimeout(() => {
    console.error('⚠️ Forced shutdown after timeout');
    process.exit(1);
  }, 15000);
  
  
  try {
    
    console.log('🧹 Cleanup completed');
    clearTimeout(shutdownTimeout);
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    clearTimeout(shutdownTimeout);
    process.exit(1);
  }
}

export function requestTimeout(timeoutMs: number = 15000) {
  return (req: any, res: any, next: any) => {
    
    const isAgentRoute = req.path === '/api/query' || req.originalUrl?.includes('/api/query');
    const effectiveTimeout = isAgentRoute ? 60000 : timeoutMs; // 60s for agent, 15s for others
    
    const timeout = setTimeout(() => {
      if (!res.headersSent) {
        res.status(408).json({
          error: 'Request timeout',
          message: `Request exceeded ${effectiveTimeout}ms timeout`,
        });
      }
    }, effectiveTimeout);
    
    
    res.on('finish', () => {
      clearTimeout(timeout);
    });
    
    res.on('close', () => {
      clearTimeout(timeout);
    });
    
    next();
  };
}


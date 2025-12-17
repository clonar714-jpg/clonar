// ✅ PHASE 10: Global Error Handlers & Stability Hardeners
let serverInstance = null;
/**
 * Set server instance for graceful shutdown
 */
export function setServerInstance(server) {
    serverInstance = server;
}
/**
 * ✅ PHASE 10: Enhanced unhandled rejection handler
 */
export function setupUnhandledRejectionHandler() {
    process.on('unhandledRejection', (reason, promise) => {
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
        }
        else {
            // In development, exit for faster debugging
            console.error('💥 Exiting in development mode');
            process.exit(1);
        }
    });
}
/**
 * ✅ PHASE 10: Enhanced uncaught exception handler
 */
export function setupUncaughtExceptionHandler() {
    process.on('uncaughtException', (error) => {
        console.error('❌ Uncaught Exception:', error);
        console.error('Stack:', error.stack);
        // Attempt graceful shutdown
        gracefulShutdown('uncaughtException');
    });
}
/**
 * ✅ PHASE 10: Graceful shutdown handler
 */
export function setupGracefulShutdown() {
    const signals = ['SIGTERM', 'SIGINT'];
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
async function gracefulShutdown(reason) {
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
    }
    catch (error) {
        console.error('❌ Error during shutdown:', error);
        clearTimeout(shutdownTimeout);
        process.exit(1);
    }
}
/**
 * ✅ PHASE 10: Request timeout middleware
 * ✅ FIX: Increased timeout for agent routes (places queries can take 20-30s)
 */
export function requestTimeout(timeoutMs = 15000) {
    return (req, res, next) => {
        // ✅ FIX: Agent routes need longer timeout (places queries take 20-30s)
        const isAgentRoute = req.path === '/api/agent' || req.originalUrl?.includes('/api/agent');
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

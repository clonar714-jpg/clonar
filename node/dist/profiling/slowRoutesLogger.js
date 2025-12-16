// ✅ PHASE 11: Slow Routes Logger - Logs Operations >200ms
class SlowRoutesLogger {
    constructor() {
        this.slowOperations = [];
        this.threshold = 200; // 200ms threshold
    }
    /**
     * Log operation timing
     */
    logOperation(operation, duration, metadata) {
        if (duration > this.threshold) {
            this.slowOperations.push({
                operation,
                duration,
                timestamp: Date.now(),
                metadata,
            });
            console.warn(`⚠️ Slow operation detected: ${operation} took ${duration.toFixed(2)}ms`, metadata || '');
        }
    }
    /**
     * Get slow operations summary
     */
    getSlowOperations() {
        return this.slowOperations;
    }
    /**
     * Get top N slowest operations
     */
    getTopSlowOperations(n = 10) {
        return [...this.slowOperations]
            .sort((a, b) => b.duration - a.duration)
            .slice(0, n);
    }
    /**
     * Clear logged operations
     */
    clear() {
        this.slowOperations = [];
    }
    /**
     * Get statistics
     */
    getStats() {
        if (this.slowOperations.length === 0) {
            return {
                totalSlowOps: 0,
                avgDuration: 0,
                maxDuration: 0,
                minDuration: 0,
            };
        }
        const durations = this.slowOperations.map(op => op.duration);
        return {
            totalSlowOps: this.slowOperations.length,
            avgDuration: durations.reduce((a, b) => a + b, 0) / durations.length,
            maxDuration: Math.max(...durations),
            minDuration: Math.min(...durations),
        };
    }
}
// ✅ PHASE 11: Global slow routes logger
export const slowRoutesLogger = new SlowRoutesLogger();
/**
 * Decorator to measure function execution time
 */
export function measureTime(operationName) {
    return function (target, propertyName, descriptor) {
        const method = descriptor.value;
        descriptor.value = async function (...args) {
            const start = Date.now();
            try {
                const result = await method.apply(this, args);
                const duration = Date.now() - start;
                slowRoutesLogger.logOperation(`${target.constructor.name}.${propertyName}`, duration);
                return result;
            }
            catch (error) {
                const duration = Date.now() - start;
                slowRoutesLogger.logOperation(`${target.constructor.name}.${propertyName} (error)`, duration, { error: error.message });
                throw error;
            }
        };
        return descriptor;
    };
}
/**
 * Helper function to measure async operations
 */
export async function measureAsync(operationName, fn, metadata) {
    const start = Date.now();
    try {
        const result = await fn();
        const duration = Date.now() - start;
        slowRoutesLogger.logOperation(operationName, duration, metadata);
        return result;
    }
    catch (error) {
        const duration = Date.now() - start;
        slowRoutesLogger.logOperation(`${operationName} (error)`, duration, {
            ...metadata,
            error: error.message,
        });
        throw error;
    }
}

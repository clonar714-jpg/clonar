// ✅ PHASE 11: Slow Routes Logger - Logs Operations >200ms

interface OperationTiming {
  operation: string;
  duration: number;
  timestamp: number;
  metadata?: Record<string, any>;
}

class SlowRoutesLogger {
  private slowOperations: OperationTiming[] = [];
  private threshold: number = 200; // 200ms threshold

  /**
   * Log operation timing
   */
  logOperation(operation: string, duration: number, metadata?: Record<string, any>): void {
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
  getSlowOperations(): OperationTiming[] {
    return this.slowOperations;
  }

  /**
   * Get top N slowest operations
   */
  getTopSlowOperations(n: number = 10): OperationTiming[] {
    return [...this.slowOperations]
      .sort((a, b) => b.duration - a.duration)
      .slice(0, n);
  }

  /**
   * Clear logged operations
   */
  clear(): void {
    this.slowOperations = [];
  }

  /**
   * Get statistics
   */
  getStats(): {
    totalSlowOps: number;
    avgDuration: number;
    maxDuration: number;
    minDuration: number;
  } {
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
export function measureTime(operationName: string) {
  return function (target: any, propertyName: string, descriptor: PropertyDescriptor) {
    const method = descriptor.value;

    descriptor.value = async function (...args: any[]) {
      const start = Date.now();
      try {
        const result = await method.apply(this, args);
        const duration = Date.now() - start;
        slowRoutesLogger.logOperation(`${target.constructor.name}.${propertyName}`, duration);
        return result;
      } catch (error) {
        const duration = Date.now() - start;
        slowRoutesLogger.logOperation(`${target.constructor.name}.${propertyName} (error)`, duration, { error: (error as Error).message });
        throw error;
      }
    };

    return descriptor;
  };
}

/**
 * Helper function to measure async operations
 */
export async function measureAsync<T>(
  operationName: string,
  fn: () => Promise<T>,
  metadata?: Record<string, any>
): Promise<T> {
  const start = Date.now();
  try {
    const result = await fn();
    const duration = Date.now() - start;
    slowRoutesLogger.logOperation(operationName, duration, metadata);
    return result;
  } catch (error) {
    const duration = Date.now() - start;
    slowRoutesLogger.logOperation(`${operationName} (error)`, duration, {
      ...metadata,
      error: (error as Error).message,
    });
    throw error;
  }
}


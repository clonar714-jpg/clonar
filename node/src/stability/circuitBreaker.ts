// ✅ PHASE 10: Circuit Breaker for Route-Level Protection

enum CircuitState {
  CLOSED = 'CLOSED',    // Normal operation
  OPEN = 'OPEN',        // Failing, reject requests
  HALF_OPEN = 'HALF_OPEN', // Testing if service recovered
}

interface CircuitBreakerConfig {
  failureThreshold: number;      // Open circuit after N failures
  successThreshold: number;      // Close circuit after N successes (half-open)
  timeout: number;               // Time to wait before trying again (ms)
  resetTimeout: number;          // Time before attempting half-open (ms)
}

class CircuitBreaker {
  private state: CircuitState = CircuitState.CLOSED;
  private failureCount: number = 0;
  private successCount: number = 0;
  private lastFailureTime: number = 0;
  private config: CircuitBreakerConfig;

  constructor(config: CircuitBreakerConfig = {
    failureThreshold: 5,
    successThreshold: 2,
    timeout: 10000,
    resetTimeout: 30000,
  }) {
    this.config = config;
  }

  /**
   * Execute function with circuit breaker protection
   */
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    // Check circuit state
    if (this.state === CircuitState.OPEN) {
      const timeSinceFailure = Date.now() - this.lastFailureTime;
      if (timeSinceFailure > this.config.resetTimeout) {
        // Try half-open
        this.state = CircuitState.HALF_OPEN;
        this.successCount = 0;
        console.log('🔄 Circuit breaker: Moving to HALF_OPEN state');
      } else {
        throw new Error('Circuit breaker is OPEN - service unavailable');
      }
    }

    try {
      // Execute function with timeout
      const result = await Promise.race([
        fn(),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Operation timeout')), this.config.timeout)
        ),
      ]);

      // Success
      this.onSuccess();
      return result;
    } catch (error) {
      // Failure
      this.onFailure();
      throw error;
    }
  }

  private onSuccess(): void {
    this.failureCount = 0;

    if (this.state === CircuitState.HALF_OPEN) {
      this.successCount++;
      if (this.successCount >= this.config.successThreshold) {
        this.state = CircuitState.CLOSED;
        console.log('✅ Circuit breaker: Moving to CLOSED state (recovered)');
      }
    }
  }

  private onFailure(): void {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.failureCount >= this.config.failureThreshold) {
      this.state = CircuitState.OPEN;
      console.error(`❌ Circuit breaker: Moving to OPEN state (${this.failureCount} failures)`);
    }
  }

  getState(): CircuitState {
    return this.state;
  }

  reset(): void {
    this.state = CircuitState.CLOSED;
    this.failureCount = 0;
    this.successCount = 0;
    this.lastFailureTime = 0;
  }
}

// ✅ PHASE 10: Global circuit breakers for different routes
export const agentCircuitBreaker = new CircuitBreaker({
  failureThreshold: 5,
  successThreshold: 2,
  timeout: 15000,
  resetTimeout: 60000, // 1 minute before retry
});

export const llmCircuitBreaker = new CircuitBreaker({
  failureThreshold: 3,
  successThreshold: 1,
  timeout: 30000,
  resetTimeout: 120000, // 2 minutes before retry
});


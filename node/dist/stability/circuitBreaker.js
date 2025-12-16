// ✅ PHASE 10: Circuit Breaker for Route-Level Protection
var CircuitState;
(function (CircuitState) {
    CircuitState["CLOSED"] = "CLOSED";
    CircuitState["OPEN"] = "OPEN";
    CircuitState["HALF_OPEN"] = "HALF_OPEN";
})(CircuitState || (CircuitState = {}));
class CircuitBreaker {
    constructor(config = {
        failureThreshold: 5,
        successThreshold: 2,
        timeout: 10000,
        resetTimeout: 30000,
    }) {
        this.state = CircuitState.CLOSED;
        this.failureCount = 0;
        this.successCount = 0;
        this.lastFailureTime = 0;
        this.config = config;
    }
    /**
     * Execute function with circuit breaker protection
     */
    async execute(fn) {
        // Check circuit state
        if (this.state === CircuitState.OPEN) {
            const timeSinceFailure = Date.now() - this.lastFailureTime;
            if (timeSinceFailure > this.config.resetTimeout) {
                // Try half-open
                this.state = CircuitState.HALF_OPEN;
                this.successCount = 0;
                console.log('🔄 Circuit breaker: Moving to HALF_OPEN state');
            }
            else {
                throw new Error('Circuit breaker is OPEN - service unavailable');
            }
        }
        try {
            // Execute function with timeout
            const result = await Promise.race([
                fn(),
                new Promise((_, reject) => setTimeout(() => reject(new Error('Operation timeout')), this.config.timeout)),
            ]);
            // Success
            this.onSuccess();
            return result;
        }
        catch (error) {
            // Failure
            this.onFailure();
            throw error;
        }
    }
    onSuccess() {
        this.failureCount = 0;
        if (this.state === CircuitState.HALF_OPEN) {
            this.successCount++;
            if (this.successCount >= this.config.successThreshold) {
                this.state = CircuitState.CLOSED;
                console.log('✅ Circuit breaker: Moving to CLOSED state (recovered)');
            }
        }
    }
    onFailure() {
        this.failureCount++;
        this.lastFailureTime = Date.now();
        if (this.failureCount >= this.config.failureThreshold) {
            this.state = CircuitState.OPEN;
            console.error(`❌ Circuit breaker: Moving to OPEN state (${this.failureCount} failures)`);
        }
    }
    getState() {
        return this.state;
    }
    reset() {
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

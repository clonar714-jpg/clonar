// ✅ PHASE 11: Retry Backoff with Jitter
/**
 * Retry function with exponential backoff and jitter
 */
export async function retryWithBackoff(fn, options = {}) {
    const { maxRetries = 3, initialDelay = 100, maxDelay = 5000, jitter = true, exponentialBase = 2, } = options;
    let lastError = null;
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            return await fn();
        }
        catch (error) {
            lastError = error;
            if (attempt === maxRetries) {
                throw lastError;
            }
            // Calculate delay with exponential backoff
            const exponentialDelay = initialDelay * Math.pow(exponentialBase, attempt);
            // Add jitter (random 0-25% of delay)
            const jitterAmount = jitter ? Math.random() * 0.25 * exponentialDelay : 0;
            const delay = Math.min(exponentialDelay + jitterAmount, maxDelay);
            console.log(`⚠️ Retry attempt ${attempt + 1}/${maxRetries} after ${delay.toFixed(0)}ms`);
            await new Promise(resolve => setTimeout(resolve, delay));
        }
    }
    throw lastError || new Error('Retry failed');
}

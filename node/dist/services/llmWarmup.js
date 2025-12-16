// ✅ PHASE 11: LLM Cold-Start Warm-up
import OpenAI from 'openai';
let warmupComplete = false;
let warmupPromise = null;
/**
 * Warm up LLM client to reduce cold-start latency
 */
export async function warmupLLMClient() {
    if (warmupComplete) {
        return;
    }
    if (warmupPromise) {
        return warmupPromise;
    }
    warmupPromise = (async () => {
        try {
            const apiKey = process.env.OPENAI_API_KEY;
            if (!apiKey) {
                console.warn('⚠️ OPENAI_API_KEY not set, skipping LLM warmup');
                return;
            }
            const client = new OpenAI({ apiKey });
            console.log('🔥 Warming up LLM client...');
            const start = Date.now();
            // Make a small test request to warm up the connection
            await client.chat.completions.create({
                model: 'gpt-4o-mini',
                messages: [{ role: 'user', content: 'test' }],
                max_tokens: 5,
            });
            const duration = Date.now() - start;
            console.log(`✅ LLM warmup complete in ${duration}ms`);
            warmupComplete = true;
        }
        catch (error) {
            console.error('❌ LLM warmup failed:', error);
            // Don't block on warmup failure
        }
    })();
    return warmupPromise;
}
/**
 * Get warmup status
 */
export function isWarmupComplete() {
    return warmupComplete;
}

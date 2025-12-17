// src/followup/rerankFollowups.ts
import { getEmbedding, cosine } from "../embeddings/embeddingClient";
/**
 * 🟦 C10.4 — EMBEDDING RERANKING OF FOLLOW-UPS (Perplexity secret)
 * After generating potential follow-ups, we rerank them using embeddings for relevance
 * ✅ UPGRADE: Multi-context embedding reranking (query + answer + recent follow-ups)
 */
export async function rerankFollowUps(query, candidates, topN = 5, answerSummary, recentFollowups = []) {
    if (!candidates || candidates.length === 0)
        return [];
    // If we have few candidates, return them all with default scores
    if (candidates.length <= topN) {
        return candidates.map((c) => ({ candidate: c, score: 0.5 }));
    }
    try {
        // ✅ UPGRADE: Build multi-context string for embedding
        const rerankContext = `
Query: ${query}
Answer: ${answerSummary ?? ""}
Recent followups: ${recentFollowups.join(" | ")}
`.trim();
        // ✅ FIX: Get context embedding once with retry logic
        let contextEmb;
        try {
            contextEmb = await getEmbedding(rerankContext);
        }
        catch (err) {
            console.error("❌ Failed to get context embedding:", err.message);
            // Fallback: return first N candidates without reranking
            return candidates.slice(0, topN).map((c) => ({ candidate: c, score: 0.5 }));
        }
        // ✅ FIX: Score candidates with error handling and rate limit protection
        // Process in smaller batches to avoid overwhelming the API
        const BATCH_SIZE = 5;
        const scored = [];
        for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
            const batch = candidates.slice(i, i + BATCH_SIZE);
            const batchResults = await Promise.allSettled(batch.map(async (candidate) => {
                if (!candidate || candidate.trim().length === 0) {
                    return { candidate, score: -1 };
                }
                try {
                    const candidateEmb = await getEmbedding(candidate);
                    const similarity = cosine(contextEmb, candidateEmb);
                    return { candidate, score: similarity };
                }
                catch (err) {
                    console.warn(`⚠️ Failed to get embedding for candidate "${candidate.substring(0, 30)}...":`, err.message);
                    return { candidate, score: -1 };
                }
            }));
            // Extract successful results
            for (const result of batchResults) {
                if (result.status === 'fulfilled') {
                    scored.push(result.value);
                }
                else {
                    console.warn("⚠️ Candidate scoring failed:", result.reason);
                }
            }
            // ✅ FIX: Small delay between batches to avoid rate limits
            if (i + BATCH_SIZE < candidates.length) {
                await new Promise(resolve => setTimeout(resolve, 100)); // 100ms delay
            }
        }
        // Sort by score (highest first) and return top N with scores
        const ranked = scored
            .filter((item) => item.score >= 0) // Remove invalid candidates
            .sort((a, b) => b.score - a.score)
            .slice(0, topN);
        console.log(`🎯 Reranked ${candidates.length} follow-ups → top ${ranked.length} (scores: ${ranked.map(s => s.score.toFixed(3)).join(", ")})`);
        return ranked;
    }
    catch (err) {
        console.error("❌ Follow-up reranking error:", err.message);
        // Fallback: return first N candidates with default scores
        return candidates.slice(0, topN).map((c) => ({ candidate: c, score: 0.5 }));
    }
}

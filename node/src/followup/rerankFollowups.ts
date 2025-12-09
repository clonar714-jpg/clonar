// src/followup/rerankFollowups.ts
import { getEmbedding, cosine } from "../embeddings/embeddingClient";

/**
 * 🟦 C10.4 — EMBEDDING RERANKING OF FOLLOW-UPS (Perplexity secret)
 * After generating potential follow-ups, we rerank them using embeddings for relevance
 */
export async function rerankFollowUps(
  query: string,
  candidates: string[],
  topN: number = 5
): Promise<string[]> {
  if (!candidates || candidates.length === 0) return [];

  // If we have few candidates, return them all
  if (candidates.length <= topN) {
    return candidates;
  }

  try {
    // ✅ FIX: Get query embedding once with retry logic
    let qEmb;
    try {
      qEmb = await getEmbedding(query);
    } catch (err: any) {
      console.error("❌ Failed to get query embedding:", err.message);
      // Fallback: return first N candidates without reranking
      return candidates.slice(0, topN);
    }

    // ✅ FIX: Score candidates with error handling and rate limit protection
    // Process in smaller batches to avoid overwhelming the API
    const BATCH_SIZE = 5;
    const scored: Array<{ candidate: string; score: number }> = [];
    
    for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
      const batch = candidates.slice(i, i + BATCH_SIZE);
      
      const batchResults = await Promise.allSettled(
        batch.map(async (candidate) => {
          if (!candidate || candidate.trim().length === 0) {
            return { candidate, score: -1 };
          }

          try {
            const candidateEmb = await getEmbedding(candidate);
            const similarity = cosine(qEmb, candidateEmb);
            return { candidate, score: similarity };
          } catch (err: any) {
            console.warn(`⚠️ Failed to get embedding for candidate "${candidate.substring(0, 30)}...":`, err.message);
            return { candidate, score: -1 };
          }
        })
      );
      
      // Extract successful results
      for (const result of batchResults) {
        if (result.status === 'fulfilled') {
          scored.push(result.value);
        } else {
          console.warn("⚠️ Candidate scoring failed:", result.reason);
        }
      }
      
      // ✅ FIX: Small delay between batches to avoid rate limits
      if (i + BATCH_SIZE < candidates.length) {
        await new Promise(resolve => setTimeout(resolve, 100)); // 100ms delay
      }
    }

    // Sort by score (highest first) and return top N
    const ranked = scored
      .filter((item) => item.score >= 0) // Remove invalid candidates
      .sort((a, b) => b.score - a.score)
      .slice(0, topN)
      .map((x) => x.candidate);

    console.log(`🎯 Reranked ${candidates.length} follow-ups → top ${ranked.length} (scores: ${scored.slice(0, topN).map(s => s.score.toFixed(3)).join(", ")})`);

    return ranked;
  } catch (err: any) {
    console.error("❌ Follow-up reranking error:", err.message);
    // Fallback: return first N candidates
    return candidates.slice(0, topN);
  }
}


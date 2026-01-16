/**
 * ✅ Follow-up Scorer: Multi-factor scoring system
 */

export interface ScoringFactors {
  embeddingScore: number;
  behaviorScore: number;
  stageMatch: number;
  noveltyScore: number;
  gapMatch: number;
}

/**
 * Score a follow-up suggestion using multiple factors
 */
export function scoreFollowup(factors: ScoringFactors): number {
  const {
    embeddingScore,
    behaviorScore,
    stageMatch,
    noveltyScore,
    gapMatch,
  } = factors;

  // Weighted combination (Perplexity-style)
  const weights = {
    embedding: 0.35,    // Semantic relevance
    behavior: 0.20,     // User behavior pattern
    stage: 0.15,        // Intent stage alignment
    novelty: 0.15,      // Novelty (avoid repetition)
    gap: 0.15,          // Fills answer gaps
  };

  return (
    embeddingScore * weights.embedding +
    behaviorScore * weights.behavior +
    stageMatch * weights.stage +
    noveltyScore * weights.novelty +
    gapMatch * weights.gap
  );
}


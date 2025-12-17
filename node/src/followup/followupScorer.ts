// ==================================================================
// FOLLOW-UP SCORER (Multi-factor scoring system)
// ==================================================================

export interface FollowupScoreParams {
  embeddingScore: number;
  behaviorScore: number;
  stageMatch: number;
  noveltyScore: number;
  gapMatch: number;
}

/**
 * Combines multiple scoring factors to rank follow-up suggestions
 * Uses weighted combination for Perplexity-like intelligence
 */
export function scoreFollowup({
  embeddingScore,
  behaviorScore,
  stageMatch,
  noveltyScore,
  gapMatch,
}: FollowupScoreParams): number {
  return (
    embeddingScore * 0.45 + // Primary: semantic relevance
    behaviorScore * 0.20 + // User behavior patterns
    stageMatch * 0.15 + // Intent stage alignment
    gapMatch * 0.10 + // Fills answer gaps
    noveltyScore * 0.10 // Novelty/exploration value
  );
}


// ==================================================================
// INTENT STAGE INFERENCE (Perplexity-like progression awareness)
// ==================================================================

export type IntentStage =
  | "explore"
  | "compare"
  | "narrow"
  | "decide"
  | "act";

/**
 * Infers the current stage of user intent based on query patterns and follow-up history
 */
export function inferIntentStage(
  query: string,
  followupHistory: string[]
): IntentStage {
  const lowerQuery = query.toLowerCase();

  // Action stage: user is ready to buy/book/reserve
  if (/buy|book|reserve|order|purchase|checkout/i.test(lowerQuery)) {
    return "act";
  }

  // Compare stage: user wants to compare options
  if (/vs|versus|compare|comparison|difference|which is better|which one/i.test(lowerQuery)) {
    return "compare";
  }

  // Narrow stage: user is filtering/narrowing down
  if (/under|cheap|budget|filter|only|just|exactly|specifically/i.test(lowerQuery)) {
    return "narrow";
  }

  // Decide stage: user has explored enough, likely deciding
  if (followupHistory.length >= 2) {
    return "decide";
  }

  // Default: explore stage (initial discovery)
  return "explore";
}


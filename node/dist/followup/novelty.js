// ==================================================================
// NOVELTY SCORING (Controlled novelty injection)
// ==================================================================
/**
 * Scores follow-up suggestions based on novelty
 * Higher scores for unique, unexpected, or counter-intuitive suggestions
 */
export function noveltyScore(followup, recentFollowups) {
    if (!followup || followup.trim().length === 0) {
        return 0;
    }
    const lowerFollowup = followup.toLowerCase();
    // Check if this follow-up is too similar to recent ones
    if (recentFollowups.some((r) => r.toLowerCase().includes(lowerFollowup) || lowerFollowup.includes(r.toLowerCase()))) {
        return 0;
    }
    // High novelty: counter-intuitive or unexpected questions
    if (/regret|avoid|complain|overrated|hidden|secret|underrated|worst|bad|negative/i.test(lowerFollowup)) {
        return 1.0;
    }
    // Medium novelty: exploratory or alternative perspectives
    if (/alternative|different|other|else|instead|what about|how about/i.test(lowerFollowup)) {
        return 0.5;
    }
    // Default novelty: standard follow-ups
    return 0.3;
}

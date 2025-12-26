// ======================================================================
// UI MODE - Goal-based UI rendering mode
// ======================================================================
// This enum and resolver ensure UI is derived from userGoal, not intent

enum UiMode {
  decide,
  browse,
  learn,
  compare,
  locate,
  clarify,
}

/// Resolves UI mode from userGoal ONLY
/// 
/// 🚫 HARD RULES:
/// ❌ Do NOT use intent to determine UI mode
/// ❌ Do NOT use cards.length to determine UI mode
/// 
/// CRITICAL RULE: UI mode MUST be derived from userGoal, not intent or card presence.
/// Cards can exist in decide mode - that does NOT make it shopping.
UiMode resolveUiMode(String userGoal) {
  switch (userGoal) {
    case 'browse':
      return UiMode.browse;
    case 'decide':
      return UiMode.decide;
    case 'compare':
      return UiMode.compare;
    case 'learn':
      return UiMode.learn;
    case 'locate':
      return UiMode.locate;
    case 'clarification':
      return UiMode.clarify;
    default:
      return UiMode.decide; // safe fallback
  }
}


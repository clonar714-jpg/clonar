// ======================================================================
// ANSWER CONTEXT - UI model for answer-first architecture
// ======================================================================
// This model represents the context of an answer to help the UI
// render appropriately (clarification, evidence, confidence, etc.)

class AnswerContext {
  final String userGoal; // "learn" | "decide" | "compare" | "browse" | "locate" | "clarification"
  final String confidenceBand; // "high" | "medium" | "low"
  final String ambiguity; // "none" | "soft" | "hard"
  final bool hasCards;
  final bool isClarificationOnly;

  const AnswerContext({
    this.userGoal = "browse",
    this.confidenceBand = "medium",
    this.ambiguity = "none",
    this.hasCards = false,
    this.isClarificationOnly = false,
  });

  // Helper to get intent header text
  String get intentHeader {
    switch (userGoal) {
      case "learn":
        return "Explanation";
      case "decide":
        return "Recommendation";
      case "compare":
        return "Comparison";
      case "browse":
        return "Options";
      case "locate":
        return "Nearby results";
      case "clarification":
        return "Quick question";
      default:
        return "Overview";
    }
  }

  // Helper to check if cards should be shown as evidence
  bool get shouldShowEvidenceSection => hasCards && !isClarificationOnly;

  // Helper to check if follow-ups should be shown
  bool get shouldShowFollowUps => !isClarificationOnly;

  // Factory method to create from QuerySession
  factory AnswerContext.fromSession(dynamic session, Map<String, dynamic>? responseData) {
    // Extract from response metadata if available
    final metadata = responseData?['_metadata'] as Map<String, dynamic>?;
    final query = session.query?.toString() ?? '';
    final userGoal = metadata?['userGoal']?.toString() ?? 
                     _inferUserGoal(query) ?? 
                     "browse";
    
    final confidence = metadata?['confidence'] as Map<String, dynamic>?;
    final overallConfidence = (confidence?['overall'] as num?)?.toDouble() ?? 0.5;
    
    String confidenceBand = "medium";
    if (overallConfidence >= 0.75) {
      confidenceBand = "high";
    } else if (overallConfidence < 0.45) {
      confidenceBand = "low";
    }
    
    // Extract ambiguity from metadata
    final ambiguity = metadata?['ambiguity']?.toString() ?? 
                     metadata?['answerPlan']?['ambiguity']?.toString() ??
                     "none";
    
    final hasCards = (session.cards != null && (session.cards as List).isNotEmpty) || 
                     (session.results != null && (session.results as List).isNotEmpty);
    
    // Check if this is a clarification-only response
    // Clarification responses typically have no cards and a question-like summary
    // OR ambiguity === "hard"
    final summary = session.summary?.toString() ?? '';
    final isClarificationOnly = (ambiguity == "hard") ||
                                (!hasCards && 
                                 summary.isNotEmpty &&
                                 (summary.contains('?') || 
                                  summary.toLowerCase().contains('could you') ||
                                  summary.toLowerCase().contains('what') ||
                                  summary.toLowerCase().contains('which')));
    
    return AnswerContext(
      userGoal: userGoal,
      confidenceBand: confidenceBand,
      ambiguity: ambiguity,
      hasCards: hasCards,
      isClarificationOnly: isClarificationOnly,
    );
  }

  // Infer user goal from query text (fallback if not in metadata)
  static String? _inferUserGoal(String query) {
    final lower = query.toLowerCase();
    
    final learnPattern = RegExp(r'\b(what is|what are|how does|how do|explain|why|tell me about|describe)\b');
    if (learnPattern.hasMatch(lower)) {
      return "learn";
    }
    
    // ✅ FIX: Check "compare" BEFORE "decide" to catch "difference between" correctly
    final comparePattern = RegExp(r'\b(vs|versus|compare|comparison|difference between|which is better)\b');
    if (comparePattern.hasMatch(lower)) {
      return "compare";
    }
    
    // ✅ FIX: Removed "difference between" from decide pattern (it's in compare now)
    final decidePattern = RegExp(r'\b(best|top|worth it|should i|is.*worth|is.*good|recommend|suggest|better than)\b');
    if (decidePattern.hasMatch(lower)) {
      return "decide";
    }
    
    final locatePattern = RegExp(r'\b(where|near|in [a-z]+|at [a-z]+|around)\b');
    if (locatePattern.hasMatch(lower)) {
      return "locate";
    }
    
    return null; // Default to "browse"
  }
}


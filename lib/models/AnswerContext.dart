

class AnswerContext {
  final String userGoal; 
  final String confidenceBand; 
  final String ambiguity; 
  final bool hasCards;
  final bool isClarificationOnly;

  const AnswerContext({
    this.userGoal = "browse",
    this.confidenceBand = "medium",
    this.ambiguity = "none",
    this.hasCards = false,
    this.isClarificationOnly = false,
  });

  
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

  
  bool get shouldShowEvidenceSection => hasCards && !isClarificationOnly;

  
  bool get shouldShowFollowUps => !isClarificationOnly;

  
  factory AnswerContext.fromSession(dynamic session, Map<String, dynamic>? responseData) {
    
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
    
    
    final ambiguity = metadata?['ambiguity']?.toString() ?? 
                     metadata?['answerPlan']?['ambiguity']?.toString() ??
                     "none";
    
    final hasCards = (session.cards != null && (session.cards as List).isNotEmpty) || 
                     (session.results != null && (session.results as List).isNotEmpty);
    
    
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

  
  static String? _inferUserGoal(String query) {
    final lower = query.toLowerCase();
    
    final learnPattern = RegExp(r'\b(what is|what are|how does|how do|explain|why|tell me about|describe)\b');
    if (learnPattern.hasMatch(lower)) {
      return "learn";
    }
    
    
    final comparePattern = RegExp(r'\b(vs|versus|compare|comparison|difference between|which is better)\b');
    if (comparePattern.hasMatch(lower)) {
      return "compare";
    }
    
    
    final decidePattern = RegExp(r'\b(best|top|worth it|should i|is.*worth|is.*good|recommend|suggest|better than)\b');
    if (decidePattern.hasMatch(lower)) {
      return "decide";
    }
    
    final locatePattern = RegExp(r'\b(where|near|in [a-z]+|at [a-z]+|around)\b');
    if (locatePattern.hasMatch(lower)) {
      return "locate";
    }
    
    return null; 
  }
}


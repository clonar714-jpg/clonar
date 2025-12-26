import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/query_session_model.dart';
import '../models/Product.dart';
import '../models/AnswerContext.dart';
import '../models/UiMode.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../providers/follow_up_engine_provider.dart';
import '../widgets/StreamingTextWidget.dart';
import '../widgets/HotelMapView.dart';
import '../screens/FullScreenMapScreen.dart';
import '../screens/HotelResultsScreen.dart';
import '../screens/ShoppingGridScreen.dart';
import '../screens/MovieDetailScreen.dart';
import '../services/AgentService.dart';
import 'result_shells/ResultShellRouter.dart';
import 'PerplexityAnswerWidget.dart';

class SessionRenderModel {
  final QuerySession session;
  final int index;
  final BuildContext context;
  final Function(String, QuerySession) onFollowUpTap;
  final Function(Map<String, dynamic>) onHotelTap;
  final Function(Product) onProductTap;
  final Function(String) onViewAllHotels;
  final Function(String) onViewAllProducts;
  final String? query;
  
  SessionRenderModel({
    required this.session,
    required this.index,
    required this.context,
    required this.onFollowUpTap,
    required this.onHotelTap,
    required this.onProductTap,
    required this.onViewAllHotels,
    required this.onViewAllProducts,
    this.query,
  });
}

class SessionRenderer extends StatelessWidget {
  final SessionRenderModel model;
  
  const SessionRenderer({super.key, required this.model});
  
  @override
  Widget build(BuildContext context) {
    return _SessionContentRenderer(model: model);
  }
}

class _SessionContentRenderer extends ConsumerWidget {
  final SessionRenderModel model;
  
  const _SessionContentRenderer({required this.model});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = model.session;
    
    return Padding(
      key: ValueKey('session-${model.index}'),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ FIX 3: Add horizontal padding to query text (16px like description/images)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              session.query,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          
          // ✅ CRITICAL: Direct call - NO Builder wrapper
          // If you see "✅ NOT LOADING" in logs, app is running OLD CODE - do: flutter clean && flutter run --profile
          _buildContentDirectly(session),
        ],
      ),
    );
  }
  
  // ✅ CRITICAL: Direct content builder - NO Builder wrapper, NO routing
  Widget _buildContentDirectly(QuerySession session) {
    // ✅ CRITICAL: Log IMMEDIATELY when method is called
    print('🔥🔥🔥 _buildContentDirectly() CALLED for query: "${session.query}"');
    print('🔥🔥🔥   - Session summary: ${session.summary != null && session.summary!.isNotEmpty}');
    print('🔥🔥🔥   - Session sections: ${session.sections?.length ?? 0}');
    
    // ✅ SIMPLIFIED: Only check for summary and sections (no more hotel/learn logic)
    final hasSummary = session.summary != null && session.summary!.isNotEmpty;
    final hasSections = session.sections != null && session.sections!.isNotEmpty;
    
    final hasNoData = !hasSummary && !hasSections;
    
    // ✅ ROOT CAUSE FIX: Loading depends ONLY on data presence, not flags
    final isLoading = hasNoData;
    
    // ✅ FIX: Log loading state for debugging
    if (isLoading) {
      print("⏳ LOADING STATE - Query: '${session.query}'");
      print("  - hasSummary: $hasSummary");
      print("  - hasSections: $hasSections (${session.sections?.length ?? 0})");
      print("  - hasNoData: $hasNoData");
      print("  - isLoading: $isLoading (based on data only, not flags)");
      
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Searching...',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    
    // ✅ CRITICAL: This MUST execute - log immediately to verify
    print('🔥🔥🔥 SessionRenderer: About to build PerplexityAnswerWidget for "${session.query}"');
    print('🔥🔥🔥   - isLoading: $isLoading (MUST be false)');
    print('🔥🔥🔥   - hasSummary: $hasSummary');
    print('🔥🔥🔥   - hasSections: $hasSections (${session.sections?.length ?? 0})');
    print('🔥🔥🔥   - Session sections: ${session.sections}');
    print('🔥🔥🔥   - Session sources: ${session.sources.length}');
    
    // ✅ SIMPLIFIED: Directly use PerplexityAnswerWidget for ALL queries
    // No more goal-aware routing - LLM-driven means one widget for everything
    // ✅ CRITICAL: This is the ONLY code path that should execute
    final widget = Column(
      key: ValueKey('answer-${session.query}-${session.sections?.length ?? 0}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ SIMPLIFIED: Use PerplexityAnswerWidget directly (shows "Answer" header, not "Explanation")
        // Just answer content - sections have their own titles
        PerplexityAnswerWidget(
          key: ValueKey('perplexity-${session.query}'),
          session: session,
        ),
        
        const SizedBox(height: 40),
      ],
    );
    
    print('🔥🔥🔥 SessionRenderer: Built PerplexityAnswerWidget widget, returning now');
    return widget;
  }
  
  // ✅ GOAL-AWARE: Build content using goal-specific shells (delegates to existing methods for now)
  Widget _buildGoalAwareContent(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    // ✅ CRITICAL: Log which path we're taking
    print('🎯 _buildGoalAwareContent: userGoal=${answerContext.userGoal}, isClarification=${answerContext.isClarificationOnly}');
    
    if (answerContext.isClarificationOnly) {
      print('  - → Using _buildClarificationCard');
      return _buildClarificationCard(session, answerContext);
    }
    
    switch (answerContext.userGoal) {
      case 'learn':
        // ✅ SIMPLIFIED: Use ResultShellRouter (routes to LearnResultShell which uses PerplexityAnswerWidget)
        print('  - → Routing to ResultShellRouter for learn goal');
        return ResultShellRouter(
          session: session,
          answerContext: answerContext,
          model: model,
        );
      case 'compare':
        // ✅ SIMPLIFIED: Use ResultShellRouter (routes to LearnResultShell which uses PerplexityAnswerWidget)
        return ResultShellRouter(
          session: session,
          answerContext: answerContext,
          model: model,
        );
      case 'decide':
        // ✅ FIX: Use ResultShellRouter for decide queries (properly handles evidence section)
        return ResultShellRouter(
          session: session,
          answerContext: answerContext,
          model: model,
        );
      case 'browse':
        // ✅ SIMPLIFIED: Use ResultShellRouter (routes to LearnResultShell which uses PerplexityAnswerWidget)
        return ResultShellRouter(
          session: session,
          answerContext: answerContext,
          model: model,
        );
      case 'locate':
        // ✅ SIMPLIFIED: Use ResultShellRouter (routes to LearnResultShell which uses PerplexityAnswerWidget)
        return ResultShellRouter(
          session: session,
          answerContext: answerContext,
          model: model,
        );
      default:
        // ✅ SIMPLIFIED: Use ResultShellRouter (routes to LearnResultShell which uses PerplexityAnswerWidget)
        return ResultShellRouter(
          session: session,
          answerContext: answerContext,
          model: model,
        );
    }
  }
  
  // ✅ LEARN: Answer only, no cards, no domain chips
  Widget _buildLearnContent(QuerySession session, AnswerContext context, WidgetRef ref) {
    // ✅ SIMPLIFIED: Use PerplexityAnswerWidget for all learn queries
    return ResultShellRouter(
      session: session,
      answerContext: context,
      model: model,
    );
  }
  
  // ✅ LEARN: Build answer section with reading-friendly typography
  Widget _buildLearnAnswerSection(String summary, AnswerContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Answer", // ✅ Changed from context.intentHeader to "Answer"
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          StreamingTextWidget(
            targetText: summary,
            enableAnimation: false,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
              height: 1.75, // More line spacing for reading
              letterSpacing: 0.1, // Slightly more letter spacing
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ LEARN: Build key takeaways block
  Widget _buildKeyTakeaways(String summary) {
    // Extract key points using sentence chunking
    final takeaways = _extractKeyTakeaways(summary);
    
    if (takeaways.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Key takeaways",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            // ✅ UI Enforcement Rule: Hide if empty (better than duplicated ones)
            if (takeaways.isNotEmpty)
              ...takeaways.map((takeaway) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "• ",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          takeaway,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
  
  // ✅ LEARN: Extract key takeaways from summary (concept-based abstraction)
  // ✅ FIX: Changed from sentence-based to concept-based to prevent duplication
  List<String> _extractKeyTakeaways(String summary) {
    // Step 1: Extract core concepts (noun phrases, technical terms)
    final concepts = _extractCoreConcepts(summary);
    
    // Step 2: Convert to abstract labels (remove verbs, examples, connectors)
    final takeaways = concepts.map((c) => _toAbstractLabel(c)).toList();
    
    // Step 3: Hard de-duplication - remove any takeaway that appears in summary
    final summaryLower = summary.toLowerCase();
    final uniqueTakeaways = takeaways
        .where((t) => !summaryLower.contains(t.toLowerCase()))
        .where((t) => t.length > 5 && t.length < 50) // Reasonable length for labels
        .toList();
    
    // Step 4: Quality check - if less than 2 unique takeaways, return empty
    if (uniqueTakeaways.length < 2) {
      return [];
    }
    
    // Step 5: Return max 3 items
    return uniqueTakeaways.take(3).toList();
  }
  
  // Extract core concepts: noun phrases, technical terms, key entities
  List<String> _extractCoreConcepts(String text) {
    final concepts = <String>[];
    final lowerText = text.toLowerCase();
    
    // Pattern 1: Technical terms (capitalized words, acronyms)
    final techPattern = RegExp(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b');
    final techMatches = techPattern.allMatches(text);
    for (final match in techMatches) {
      final term = match.group(0)?.trim();
      if (term != null && term.length > 3) {
        concepts.add(term);
      }
    }
    
    // Pattern 2: Noun phrases (adjective + noun patterns)
    final nounPhrasePattern = RegExp(r'\b(?:embedding|vector|semantic|retrieval|augmented|generation|similarity|metric|document|system|model|algorithm|technique|method|approach|framework|architecture|component|feature|capability|limitation|advantage|benefit|tradeoff|alternative|application|use case|scalability|performance|efficiency)\b', caseSensitive: false);
    final nounMatches = nounPhrasePattern.allMatches(lowerText);
    for (final match in nounMatches) {
      final term = match.group(0)?.trim();
      if (term != null) {
        // Try to get the full noun phrase (adjective + noun)
        final start = match.start;
        final end = match.end;
        if (start > 0 && end < text.length) {
          final context = text.substring(
            start > 10 ? start - 10 : 0,
            end < text.length - 10 ? end + 10 : text.length
          );
          // Extract 2-4 word phrases around the term
          final escapedTerm = term.replaceAll(RegExp(r'[.*+?^${}()|[\]\\]'), r'\$&');
          final phrasePattern = RegExp('\\b(?:\\w+\\s+){1,3}$escapedTerm(?:\\s+\\w+){0,2}\\b', caseSensitive: false);
          final phraseMatch = phrasePattern.firstMatch(context);
          if (phraseMatch != null) {
            concepts.add(phraseMatch.group(0)!.trim());
          } else {
            concepts.add(term);
          }
        } else {
          concepts.add(term);
        }
      }
    }
    
    // Pattern 3: Key action-result pairs (extract the result/concept, not the action)
    // e.g., "converts text into embeddings" -> "embedding-based conversion"
    final actionPattern = RegExp(r'\b(?:converts?|transforms?|uses?|applies?|implements?|enables?|provides?|offers?|supports?)\s+[\w\s]+(?:into|to|for|as|with)\s+([\w\s]+)', caseSensitive: false);
    final actionMatches = actionPattern.allMatches(text);
    for (final match in actionMatches) {
      final result = match.group(1)?.trim();
      if (result != null && result.length > 3 && result.length < 30) {
        concepts.add(result);
      }
    }
    
    // Remove duplicates and return
    return concepts.toSet().toList();
  }
  
  // Convert concept to abstract label (remove verbs, examples, connectors)
  String _toAbstractLabel(String concept) {
    // Remove common verbs and connectors
    final cleaned = concept
        .replaceAll(RegExp(r'\b(?:is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|can|could|should|may|might|must)\b', caseSensitive: true), '')
        .replaceAll(RegExp(r'\b(?:the|a|an|this|that|these|those|it|they|we|you)\b', caseSensitive: true), '')
        .replaceAll(RegExp(r'\b(?:and|or|but|so|because|since|although|however|therefore|thus|hence)\b', caseSensitive: true), '')
        .replaceAll(RegExp(r'\b(?:using|with|by|for|from|to|in|on|at|of)\b', caseSensitive: true), '')
        .replaceAll(RegExp(r'[.!?,;:()\[\]{}]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Capitalize first letter
    if (cleaned.isEmpty) return concept;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
  
  // ✅ DEPRECATED: This old method should NOT be used anymore
  // All queries should use PerplexityAnswerWidget directly (LLM-driven)
  Widget _buildCompareContent(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    print('⚠️ WARNING: _buildCompareContent called - should use PerplexityAnswerWidget instead');
    // ✅ FIXED: Use PerplexityAnswerWidget instead of old methods
    return PerplexityAnswerWidget(session: session);
  }
  
  // ✅ OLD METHOD (DEPRECATED - kept for reference only)
  Widget _buildCompareContent_OLD(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    final summary = session.summary ?? "";
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ COMPARE: Comparison summary block (short framing paragraph)
        if (summary.isNotEmpty)
          _buildComparisonSummaryBlock(summary, answerContext),
        
        // ✅ COMPARE: Comparison split block (MUST exist - two labeled sides)
        _buildComparisonSplitBlock(summary),
        
        // ✅ COMPARE: Evidence cards (max 2, after reasoning)
        if (answerContext.shouldShowEvidenceSection && session.cards.length <= 2)
          _buildEvidenceSection(context, session, ref, userGoal: answerContext.userGoal),
        
        // ✅ COMPARE: Footer
        _buildCompareFooter(),
        
        // ✅ COMPARE: Ranked follow-ups
        _buildFollowUps(session, ref, isCompare: true),
      ],
    );
  }
  
  // ✅ COMPARE: Build comparison summary block
  Widget _buildComparisonSummaryBlock(String summary, AnswerContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Answer", // ✅ Changed from context.intentHeader to "Answer"
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Side-by-side overview",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Extract first paragraph as framing
          StreamingTextWidget(
            targetText: _extractFramingParagraph(summary),
            enableAnimation: false,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
              height: 1.65,
              letterSpacing: -0.1,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ COMPARE: Extract framing paragraph (first sentence or first ~100 chars)
  String _extractFramingParagraph(String text) {
    final firstSentenceEnd = text.indexOf('.');
    if (firstSentenceEnd > 0 && firstSentenceEnd < 150) {
      return text.substring(0, firstSentenceEnd + 1);
    }
    // Fallback: first ~100 chars
    return text.length > 100 ? text.substring(0, 100) + '...' : text;
  }
  
  // ✅ COMPARE: Build comparison split block (two labeled sides)
  Widget _buildComparisonSplitBlock(String summary) {
    // Extract comparison sides from summary using heuristics
    final sides = _extractComparisonSides(summary);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Side A
            if (sides['sideA'] != null)
              _buildComparisonSide(
                heading: sides['sideAHeading'] ?? "Better for",
                content: sides['sideA']!,
                isFirst: true,
              ),
            
            // Divider
            if (sides['sideA'] != null && sides['sideB'] != null)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: AppColors.border.withOpacity(0.5),
              ),
            
            // Side B
            if (sides['sideB'] != null)
              _buildComparisonSide(
                heading: sides['sideBHeading'] ?? "Better for",
                content: sides['sideB']!,
                isFirst: false,
              ),
          ],
        ),
      ),
    );
  }
  
  // ✅ COMPARE: Extract comparison sides from summary
  Map<String, String?> _extractComparisonSides(String summary) {
    final result = <String, String?>{};
    
    // Heuristic 1: Look for "X excels at" or "X is better when"
    final excelsPattern = RegExp(r'([A-Z][a-zA-Z\s]+?)\s+(?:excels at|is better when|is stronger for|shines in)\s+([^.!?]+)', caseSensitive: false);
    final excelsMatch = excelsPattern.firstMatch(summary);
    if (excelsMatch != null) {
      result['sideAHeading'] = "Better for ${excelsMatch.group(2)?.trim()}";
      result['sideA'] = "${excelsMatch.group(1)?.trim()} excels at ${excelsMatch.group(2)?.trim()}.";
    }
    
    // Heuristic 2: Look for "Y is better" or "Y offers"
    final betterPattern = RegExp(r'([A-Z][a-zA-Z\s]+?)\s+(?:is better|offers|provides|has)\s+([^.!?]+)', caseSensitive: false);
    final betterMatch = betterPattern.firstMatch(summary);
    if (betterMatch != null && betterMatch.group(1) != excelsMatch?.group(1)) {
      result['sideBHeading'] = "Better for ${betterMatch.group(2)?.trim()}";
      result['sideB'] = "${betterMatch.group(1)?.trim()} is better for ${betterMatch.group(2)?.trim()}.";
    }
    
    // Heuristic 3: Split by "vs" or "versus" and extract from each side
    if (result.isEmpty) {
      final vsPattern = RegExp(r'([^v]+?)\s+vs\.?\s+([^.!?]+)', caseSensitive: false);
      final vsMatch = vsPattern.firstMatch(summary);
      if (vsMatch != null) {
        result['sideA'] = vsMatch.group(1)?.trim() ?? "";
        result['sideB'] = vsMatch.group(2)?.trim() ?? "";
        result['sideAHeading'] = "First option";
        result['sideBHeading'] = "Second option";
      }
    }
    
    // Fallback: Split summary into two parts
    if (result.isEmpty) {
      final sentences = summary.split(RegExp(r'[.!?]+\s+'));
      if (sentences.length >= 2) {
        result['sideA'] = sentences[0].trim();
        result['sideB'] = sentences[1].trim();
        result['sideAHeading'] = "First option";
        result['sideBHeading'] = "Second option";
      } else if (sentences.isNotEmpty) {
        // Single sentence - split in half
        final mid = summary.length ~/ 2;
        result['sideA'] = summary.substring(0, mid).trim();
        result['sideB'] = summary.substring(mid).trim();
        result['sideAHeading'] = "First option";
        result['sideBHeading'] = "Second option";
      }
    }
    
    return result;
  }
  
  // ✅ COMPARE: Build a comparison side
  Widget _buildComparisonSide({required String heading, required String content, required bool isFirst}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 12, 16, isFirst ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ DEPRECATED: This old method should NOT be used anymore
  // All queries should use PerplexityAnswerWidget directly (LLM-driven)
  Widget _buildDecideContent(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    print('⚠️ WARNING: _buildDecideContent called - should use PerplexityAnswerWidget instead');
    // ✅ FIXED: Use PerplexityAnswerWidget instead of old methods
    return PerplexityAnswerWidget(session: session);
  }
  
  // ✅ OLD METHOD (DEPRECATED - kept for reference only)
  Widget _buildDecideContent_OLD(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    final summary = session.summary ?? "";
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ DECIDE: Verdict header
        _buildVerdictHeader(summary, answerContext),
        
        // ✅ DECIDE: Good fit / Not ideal blocks
        _buildVerdictBlocks(summary),
        
        // ✅ DECIDE: Evidence cards (max 2, after verdict)
        if (answerContext.shouldShowEvidenceSection && session.cards.length <= 2)
          _buildEvidenceSection(context, session, ref, userGoal: answerContext.userGoal),
        
        // ✅ DECIDE: Follow-ups framed as "See alternatives", "Compare with X"
        _buildFollowUps(session, ref, isDecide: true),
      ],
    );
  }
  
  // ✅ DECIDE: Build verdict header
  Widget _buildVerdictHeader(String summary, AnswerContext context) {
    // Extract verdict from summary (look for "yes", "no", "worth it", "recommend")
    final verdict = _extractVerdict(summary);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Answer", // ✅ Changed from context.intentHeader to "Answer"
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Verdict text (bold, prominent)
          if (verdict['text'] != null)
            Text(
              verdict['text']!,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: verdict['isPositive'] == true 
                  ? AppColors.accent 
                  : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 8),
          // Condition text
          if (verdict['condition'] != null)
            Text(
              verdict['condition']!,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
  
  // ✅ DECIDE: Extract verdict from summary
  Map<String, dynamic> _extractVerdict(String summary) {
    final lower = summary.toLowerCase();
    
    // Look for "yes" or "no" patterns
    if (RegExp(r'\b(yes|recommend|worth it|good choice|solid option)\b').hasMatch(lower)) {
      final conditionMatch = RegExp(r'(?:if|when|for)\s+([^.!?]+)').firstMatch(summary);
      return {
        'text': _extractFirstSentence(summary),
        'isPositive': true,
        'condition': conditionMatch != null ? "If you ${conditionMatch.group(1)?.trim()}" : null,
      };
    } else if (RegExp(r'\b(no|not worth|skip|avoid|not ideal)\b').hasMatch(lower)) {
      final conditionMatch = RegExp(r'(?:if|when|for)\s+([^.!?]+)').firstMatch(summary);
      return {
        'text': _extractFirstSentence(summary),
        'isPositive': false,
        'condition': conditionMatch != null ? "If you ${conditionMatch.group(1)?.trim()}" : null,
      };
    }
    
    // Fallback: use first sentence
    return {
      'text': _extractFirstSentence(summary),
      'isPositive': null,
      'condition': null,
    };
  }
  
  String _extractFirstSentence(String text) {
    final firstSentenceEnd = text.indexOf('.');
    if (firstSentenceEnd > 0) {
      return text.substring(0, firstSentenceEnd + 1);
    }
    return text.length > 100 ? text.substring(0, 100) + '...' : text;
  }
  
  // ✅ DECIDE: Build verdict blocks (Good fit if / Not ideal if)
  Widget _buildVerdictBlocks(String summary) {
    final blocks = _extractVerdictBlocks(summary);
    
    if (blocks.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.map((block) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: block['isPositive'] == true
                  ? AppColors.accent.withOpacity(0.1)
                  : AppColors.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: block['isPositive'] == true
                    ? AppColors.accent.withOpacity(0.3)
                    : AppColors.border.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    block['isPositive'] == true ? Icons.check_circle : Icons.cancel,
                    size: 20,
                    color: block['isPositive'] == true 
                      ? AppColors.accent 
                      : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          block['label'] ?? "",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          block['text'] ?? "",
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  // ✅ DECIDE: Extract verdict blocks from summary
  List<Map<String, dynamic>> _extractVerdictBlocks(String summary) {
    final blocks = <Map<String, dynamic>>[];
    
    // Look for "good fit if", "ideal if", "not ideal if", "skip if"
    final goodFitPattern = RegExp(r'(?:good fit|ideal|recommended|worth it)\s+(?:if|when|for)\s+([^.!?]+)', caseSensitive: false);
    final goodFitMatch = goodFitPattern.firstMatch(summary);
    if (goodFitMatch != null) {
      blocks.add({
        'label': 'Good fit if',
        'text': goodFitMatch.group(1)?.trim() ?? "",
        'isPositive': true,
      });
    }
    
    final notIdealPattern = RegExp(r'(?:not ideal|skip|avoid|not worth|not recommended)\s+(?:if|when|for)\s+([^.!?]+)', caseSensitive: false);
    final notIdealMatch = notIdealPattern.firstMatch(summary);
    if (notIdealMatch != null) {
      blocks.add({
        'label': 'Not ideal if',
        'text': notIdealMatch.group(1)?.trim() ?? "",
        'isPositive': false,
      });
    }
    
    // Fallback: extract pros/cons if available
    if (blocks.isEmpty) {
      final prosPattern = RegExp(r'(?:pros?|advantages?|benefits?)[:\s]+([^.!?]+)', caseSensitive: false);
      final prosMatch = prosPattern.firstMatch(summary);
      if (prosMatch != null) {
        blocks.add({
          'label': 'Good fit if',
          'text': prosMatch.group(1)?.trim() ?? "",
          'isPositive': true,
        });
      }
      
      final consPattern = RegExp(r'(?:cons?|disadvantages?|drawbacks?)[:\s]+([^.!?]+)', caseSensitive: false);
      final consMatch = consPattern.firstMatch(summary);
      if (consMatch != null) {
        blocks.add({
          'label': 'Not ideal if',
          'text': consMatch.group(1)?.trim() ?? "",
          'isPositive': false,
        });
      }
    }
    
    return blocks;
  }
  
  // ✅ DEPRECATED: These old methods should NOT be used anymore
  // All queries should use PerplexityAnswerWidget directly (LLM-driven)
  // These are kept for backward compatibility but should be removed
  Widget _buildBrowseContent(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    print('⚠️ WARNING: _buildBrowseContent called - should use PerplexityAnswerWidget instead');
    // ✅ FIXED: Use PerplexityAnswerWidget instead of old methods
    return PerplexityAnswerWidget(session: session);
  }
  
  Widget _buildLocateContent(BuildContext context, QuerySession session, AnswerContext answerContext, WidgetRef ref) {
    print('⚠️ WARNING: _buildLocateContent called - should use PerplexityAnswerWidget instead');
    // ✅ FIXED: Use PerplexityAnswerWidget instead of old methods
    return PerplexityAnswerWidget(session: session);
  }
  
  // ✅ COMPARE: Footer for comparison
  Widget _buildCompareFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        "Winner depends on your priorities and use case.",
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
  
  // ✅ LEARN: Follow-ups as depth expanders
  Widget _buildLearnFollowUps(QuerySession session, WidgetRef ref) {
    final followUpsAsync = ref.watch(followUpEngineProvider(session));
    
    return followUpsAsync.when(
      data: (followUps) {
        if (followUps.isEmpty) return const SizedBox.shrink();
        final limited = followUps.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Related",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...limited.asMap().entries.map((entry) {
              return _buildDepthExpanderItem(entry.value, entry.key, session);
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
  
  Widget _buildDepthExpanderItem(String suggestion, int index, QuerySession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => model.onFollowUpTap(suggestion, session),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.expand_more,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildTags(BuildContext context, QuerySession session, WidgetRef ref) {
    // ✅ FIX 2: Use UiMode resolver (userGoal ONLY) to determine if shopping tag should be shown
    final answerContext = AnswerContext.fromSession(session, null);
    final uiMode = resolveUiMode(answerContext.userGoal);
    
    final tags = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Clonar',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      // ✅ FIX 2: Only show shopping tag for browse mode (NOT based on intent or cards)
      if (uiMode == UiMode.browse && session.resultType == 'shopping')
        _buildIntentTag(session.resultType, session, ref),
    ];
    
    // ✅ FIX: Add "Paid Experiences" tag for ALL places queries (future: will show Expedia/affiliate API results)
    if (session.resultType == 'places' || session.resultType == 'location') {
      tags.add(_buildPaidExperienceTag());
    }
    
    // ✅ FIX: Add movie-specific tags (Showtimes, Cast & Crew, Trailers, Reviews)
    if (session.resultType == 'movies' && session.cards.isNotEmpty) {
      tags.addAll(_buildMovieTags(context, session, ref));
    }
    
    // ✅ FIX 3: Add horizontal padding to tags (16px like description/images)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags,
      ),
    );
  }
  
  // ✅ FIX: Build "Paid Experiences" tag (always shown for places queries)
  Widget _buildPaidExperienceTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_activity, size: 14, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          const Text(
            'Paid Experiences',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildIntentTag(String intent, QuerySession session, WidgetRef ref) {
    IconData icon;
    String label;
    
    switch (intent) {
      case 'shopping':
        icon = Icons.shopping_bag;
        label = 'Shopping';
        break;
      case 'hotel':
      case 'hotels':
        icon = Icons.hotel;
        label = 'Hotels';
        break;
      case 'places':
      case 'location':
        icon = Icons.location_on;
        label = 'Places';
        break;
      case 'movies':
        icon = Icons.movie;
        label = 'Movies';
        break;
      default:
        icon = Icons.search;
        label = 'Search';
    }
    
    // ✅ FIX: Add click navigation to tags (Hotels/Shopping)
    return GestureDetector(
      onTap: () {
        if (intent == 'hotel' || intent == 'hotels') {
          // Navigate to HotelResultsScreen
          Navigator.push(
            model.context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: session.query),
            ),
          );
        } else if (intent == 'shopping') {
          // ✅ FIX: Each session is isolated - only show products from THIS specific query
          // Example: "new balance shoes" query → only new balance shoes
          //          "nike running shoes" query → only nike shoes (not new balance + nike)
          // Each QuerySession has its own cards array, so session.products only contains
          // products from this specific query, not from other queries in the conversation
          final sessionProducts = session.products;
          if (sessionProducts.isNotEmpty) {
            Navigator.push(
              model.context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: sessionProducts),
              ),
            );
          } else {
            ScaffoldMessenger.of(model.context).showSnackBar(
              const SnackBar(
                content: Text('No products available to display'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget? _buildHotelMap(QuerySession session) {
    List<Map<String, dynamic>>? mapPoints = session.hotelMapPoints;
    
    if ((mapPoints == null || mapPoints.isEmpty) && session.hotelResults.isNotEmpty) {
      mapPoints = session.hotelResults.where((hotel) {
        final lat = hotel['latitude'] ?? hotel['geo']?['latitude'] ?? hotel['gps_coordinates']?['latitude'];
        final lng = hotel['longitude'] ?? hotel['geo']?['longitude'] ?? hotel['gps_coordinates']?['longitude'];
        return lat != null && lng != null;
      }).map((hotel) {
        final lat = hotel['latitude'] ?? hotel['geo']?['latitude'] ?? hotel['gps_coordinates']?['latitude'];
        final lng = hotel['longitude'] ?? hotel['geo']?['longitude'] ?? hotel['gps_coordinates']?['longitude'];
        return {
          'latitude': lat is num ? lat.toDouble() : double.tryParse(lat.toString()) ?? 0.0,
          'longitude': lng is num ? lng.toDouble() : double.tryParse(lng.toString()) ?? 0.0,
          'title': hotel['name']?.toString() ?? 'Hotel',
          'address': hotel['address']?.toString() ?? '',
        };
      }).toList();
    }
    
    if (mapPoints == null || mapPoints.isEmpty) {
      return null;
    }
    
    final hotelDataHash = '${session.hotelResults.length}-${mapPoints.length}'.hashCode;
    
    return RepaintBoundary(
      key: ValueKey('hotel-map-$hotelDataHash'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: () {
            Navigator.of(model.context).push(
              MaterialPageRoute(
                builder: (context) => FullScreenMapScreen(
                  points: mapPoints!,
                  title: session.query,
                ),
              ),
            );
          },
          child: Stack(
            children: [
              HotelMapView(
                key: ValueKey('hotel-map-view-${mapPoints.length}'),
                points: mapPoints,
                height: MediaQuery.of(model.context).size.height * 0.65,
                onTap: () {
                  Navigator.of(model.context).push(
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapScreen(
                        points: mapPoints!,
                        title: session.query,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen, color: AppColors.textPrimary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Tap to view full screen',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ✅ REMOVED: _buildIntentBasedContent - no longer needed, all queries use ResultShellRouter
  // This method was for old card-based rendering, which we've removed
  
  Widget _buildShoppingContent(QuerySession session) {
    const maxVisible = 12;
    final visibleProducts = session.products.take(maxVisible).toList();
    
    return Column(
      children: [
        ...visibleProducts.map((product) => RepaintBoundary(
          key: ValueKey('product-${product.id}'),
          child: _buildProductCard(product),
        )),
        if (session.products.length > visibleProducts.length)
          _buildViewAllProductsButton(session.products),
      ],
    );
  }
  
  Widget _buildHotelSectionsContent(QuerySession session, WidgetRef ref) {
    // ✅ FIX: Render hotel sections (grouped structure from backend)
    final sections = session.hotelSections;
    if (sections == null || sections.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ SessionRenderer: hotelSections is null or empty for query: "${session.query}"');
        debugPrint('  - session.sections: ${session.sections?.length ?? 0}');
        debugPrint('  - session.hotelResults: ${session.hotelResults.length}');
      }
      return const SizedBox.shrink();
    }
    
    const maxVisiblePerSection = 5;
    
    if (kDebugMode) {
      debugPrint('🏨 SessionRenderer: Rendering ${sections.length} hotel sections for query: "${session.query}"');
      for (int i = 0; i < sections.length; i++) {
        final section = sections[i];
        final title = section['title']?.toString() ?? 'Unknown';
        final items = (section['items'] as List?)?.length ?? 0;
        debugPrint('  Section $i: "$title" with $items items');
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...sections.map((section) {
          final title = section['title']?.toString() ?? 'Hotels';
          final items = (section['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          
          // ✅ FIX 4: Relaxed empty check - log but still try to render
          if (items.isEmpty) {
            print("⚠️ Section '$title' has no items - skipping");
            return const SizedBox.shrink();
          }
          
          print("✅ Rendering section '$title' with ${items.length} items");
          final itemsToShow = items.take(maxVisiblePerSection).toList();
          final hiddenCount = items.length - itemsToShow.length;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // Hotel cards in this section
              ...itemsToShow.map((hotel) => RepaintBoundary(
                key: ValueKey('hotel-${hotel['id'] ?? hotel['name'] ?? hotel.hashCode}'),
                child: _buildHotelCard(hotel),
              )),
              // View all button if there are more hotels
              if (hiddenCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildViewAllHotelsButton(session.query),
                ),
              const SizedBox(height: 24),
            ],
          );
        }),
        _buildFollowUps(session, ref),
      ],
    );
  }

  Widget _buildHotelContent(QuerySession session, WidgetRef ref) {
    // ✅ FALLBACK: Old flat list view (for backward compatibility)
    const maxVisible = 8;
    final visibleHotels = session.hotelResults.take(maxVisible).toList();
    
    return Column(
      children: [
        ...visibleHotels.map((hotel) => RepaintBoundary(
          key: ValueKey('hotel-${hotel['id'] ?? hotel['name']}'),
          child: _buildHotelCard(hotel),
        )),
        if (session.hotelResults.length > visibleHotels.length)
          _buildViewAllHotelsButton(session.query),
        _buildFollowUps(session, ref),
      ],
    );
  }
  
  Widget _buildPlacesContent(QuerySession session, WidgetRef ref) {
    const maxVisible = 8;
    final places = session.cards.take(maxVisible).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...places.map((place) => RepaintBoundary(
          key: ValueKey('place-${place['name'] ?? place['title']}'),
          child: _buildPlaceCard(place),
        )),
        if (session.cards.length > places.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+${session.cards.length - places.length} more locations',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildMoviesContent(BuildContext context, QuerySession session, WidgetRef ref) {
    // Show all movies (no limit)
    final movies = session.cards;
    final totalMovies = movies.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...movies.map((movie) => RepaintBoundary(
          key: ValueKey('movie-${movie['id']}'),
          child: _buildMovieCard(context, movie, totalMovies),
        )),
      ],
    );
  }
  
  Widget _buildProductCard(Product product) {
    final validImages = product.images.where((img) => img.trim().isNotEmpty).toList();
    final hasImage = validImages.isNotEmpty;
    
    return GestureDetector(
      onTap: () => model.onProductTap(product),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (product.rating > 0)
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    product.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            if (product.rating > 0) const SizedBox(height: 8),
            if (product.price > 0)
              Text(
                "\$${product.price.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            if (product.price > 0) const SizedBox(height: 12),
            if (hasImage)
              SizedBox(
                width: 160,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: validImages[0],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            if (hasImage) const SizedBox(height: 12),
            Text(
              product.description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHotelCard(Map<String, dynamic> hotel) {
    return _HotelCardWidget(hotel: hotel, onTap: () => model.onHotelTap(hotel));
  }
  
  // Build movie card with navigation
  Widget _buildMovieCard(BuildContext context, Map<String, dynamic> movie, int totalMovies) {
    final title = movie['title']?.toString() ?? 'Unknown Movie';
    // Extract rating - handle both string format "7.5/10" and number format
    final ratingValue = movie['rating'];
    String rating = '';
    if (ratingValue != null) {
      if (ratingValue is String && ratingValue.isNotEmpty && ratingValue != 'null') {
        rating = ratingValue;
      } else if (ratingValue is num && ratingValue > 0) {
        rating = '${ratingValue.toStringAsFixed(1)}/10';
      } else if (ratingValue.toString().isNotEmpty && ratingValue.toString() != 'null') {
        rating = ratingValue.toString();
      }
    }
    final image = movie['poster']?.toString() ?? movie['image']?.toString() ?? '';
    final releaseDate = movie['releaseDate']?.toString() ?? '';
    final description = movie['description']?.toString() ?? '';
    final movieId = movie['id'] as int? ?? 0;
    
    // Extract multiple images if available
    final List<String> images = [];
    // Check for images array first (new format with multiple images)
    if (movie['images'] != null) {
      if (movie['images'] is List) {
        for (var img in movie['images'] as List) {
          final imgUrl = img.toString();
          if (imgUrl.isNotEmpty && !images.contains(imgUrl)) {
            images.add(imgUrl);
          }
        }
      }
    }
    // Fallback to single image if no images array
    if (images.isEmpty && image.isNotEmpty) {
      images.add(image);
    }
    
    return GestureDetector(
      onTap: () {
        if (movieId > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => MovieDetailScreen(
                movieId: movieId,
                movieTitle: title,
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Movie poster(s) - horizontal scrolling if multiple
            if (images.isNotEmpty)
              images.length == 1
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: images[0],
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 200,
                          color: AppColors.surfaceVariant,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 200,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : _MoviePosterCarousel(images: images),
            // ✅ TMDB Rating after poster
            if (rating.isNotEmpty && rating != 'null') ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 18, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      rating,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TMDB',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Release date
                  if (releaseDate.isNotEmpty)
                    Text(
                      releaseDate,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  // ✅ For general queries (multiple movies): Show plot/description
                  // For specific queries (1 movie), plot is shown in Core Details as "Storyline"
                  if (description.isNotEmpty && totalMovies > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Movie poster carousel widget (for multiple images)
  Widget _MoviePosterCarousel({required List<String> images}) {
    return _MoviePosterCarouselWidget(images: images);
  }
  
  // Build movie-specific tags (Showtimes, Cast & Crew, Trailers, Reviews)
  List<Widget> _buildMovieTags(BuildContext context, QuerySession session, WidgetRef ref) {
    if (session.cards.isEmpty) return [];
    
    final firstMovie = session.cards[0];
    final movieId = firstMovie['id'] as int? ?? 0;
    final movieTitle = firstMovie['title']?.toString();
    final isInTheaters = firstMovie['isInTheaters'] == true;
    
    final tags = <Widget>[];
    
    // Showtimes tag - only show if movie is currently in theaters
    if (isInTheaters && movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 2, // Showtimes tab
                  isInTheaters: isInTheaters, // Pass isInTheaters flag to ensure Showtimes tab is visible
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
                  'Showtimes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Cast & Crew tag
    if (movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 1, // Cast tab
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
                  'Cast & Crew',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Trailers & Clips tag
    if (movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 3, // Trailers tab
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
                  'Trailers & Clips',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Reviews tag
    if (movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 4, // Reviews tab
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
                  'Reviews',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return tags;
  }
  
  Future<void> _openHotelWebsite(BuildContext context, Map<String, dynamic> hotel) async {
    final link = hotel['link']?.toString() ?? hotel['website']?.toString() ?? hotel['url']?.toString() ?? '';
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Website not available')),
      );
      return;
    }
    
    try {
      final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open website')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening website: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening website')),
      );
    }
  }
  
  Future<void> _callHotel(BuildContext context, Map<String, dynamic> hotel) async {
    final phone = hotel['phone']?.toString() ?? hotel['phone_number']?.toString() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available')),
      );
      return;
    }
    
    try {
      // Clean phone number (remove spaces, dashes, etc.)
      final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      final uri = Uri.parse('tel:$cleanPhone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot make phone call')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling hotel: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error making phone call')),
      );
    }
  }
  
  Future<void> _openHotelDirections(BuildContext context, Map<String, dynamic> hotel) async {
    final address = hotel['address']?.toString() ?? hotel['location']?.toString() ?? '';
    final lat = hotel['latitude'] ?? hotel['lat'];
    final lng = hotel['longitude'] ?? hotel['lng'];
    
    Uri? mapsUri;
    
    // Prefer coordinates if available
    if (lat != null && lng != null) {
      final latValue = lat is double ? lat : double.tryParse(lat.toString()) ?? 0.0;
      final lngValue = lng is double ? lng : double.tryParse(lng.toString()) ?? 0.0;
      if (latValue != 0.0 && lngValue != 0.0) {
        mapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latValue,$lngValue');
      }
    }
    
    // Fallback to address if no coordinates
    if (mapsUri == null && address.isNotEmpty) {
      mapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    }
    
    if (mapsUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }
    
    try {
      if (await canLaunchUrl(mapsUri)) {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open directions')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening directions: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening directions')),
      );
    }
  }
  
  Widget _buildHotelActionButton(String label, IconData icon, VoidCallback onTap, {required bool enabled}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceVariant : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? AppColors.accent.withOpacity(0.3) : Colors.grey.shade400,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: enabled ? AppColors.accent : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? AppColors.textPrimary : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPlaceCard(Map<String, dynamic> place) {
    return _PlaceCardWidget(place: place);
  }
  
  Widget _buildViewAllHotelsButton(String query) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: AppColors.primary,
        ),
        onPressed: () => model.onViewAllHotels(query),
        icon: const Icon(Icons.travel_explore, size: 16, color: AppColors.primary),
        label: const Text(
          'View full hotel list',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
  
  Widget _buildViewAllProductsButton(List<Product> products) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: AppColors.primary,
        ),
        onPressed: () => model.onViewAllProducts(model.session.query),
        icon: const Icon(Icons.shopping_bag, size: 16, color: AppColors.primary),
        label: Text(
          'View all ${products.length} products',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
  
  // ✅ DEPRECATED: This old method should NOT be used anymore
  // All queries should use PerplexityAnswerWidget directly (LLM-driven)
  Widget _buildAnswerSection(QuerySession session, AnswerContext context) {
    print('⚠️ WARNING: _buildAnswerSection called - should use PerplexityAnswerWidget instead');
    // ✅ FIXED: Use PerplexityAnswerWidget instead of old methods
    return PerplexityAnswerWidget(session: session);
  }
  
  // ✅ OLD METHOD (DEPRECATED - kept for reference only)
  Widget _buildAnswerSection_OLD(QuerySession session, AnswerContext context) {
    final summary = session.summary ?? "";
    
    // ✅ COMPARE: For compare goal, always use neutral tone (ignore confidence)
    final isCompare = context.userGoal == "compare";
    
    // ✅ CONFIDENCE-AWARE: Style based on confidence band (unless compare)
    TextStyle answerStyle = const TextStyle(
      fontSize: 15,
      color: AppColors.textPrimary,
      height: 1.65,
      letterSpacing: -0.1,
      fontWeight: FontWeight.w400,
    );
    
    if (!isCompare) {
      // Only apply confidence styling for non-compare goals
      if (context.confidenceBand == "high") {
        // High confidence: Bold first sentence
        answerStyle = answerStyle.copyWith(fontWeight: FontWeight.w600);
      } else if (context.confidenceBand == "low") {
        // Low confidence: Slightly muted
        answerStyle = answerStyle.copyWith(
          color: AppColors.textPrimary.withOpacity(0.85),
        );
      }
    }
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ FIXED: Use "Answer" header instead of context.intentHeader
          Text(
            "Answer", // ✅ Changed from context.intentHeader to "Answer"
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          // ✅ COMPARE: Subtitle for compare goal
          if (isCompare) ...[
            const SizedBox(height: 4),
            Text(
              "Side-by-side overview",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // ✅ COMPARE: For compare, structure answer with paragraphs and dividers
          // ✅ CONFIDENCE-AWARE: Answer text with confidence-based styling (or neutral for compare)
          isCompare 
            ? _buildCompareAnswerText(summary, answerStyle)
            : _buildConfidenceAwareText(summary, answerStyle),
        ],
      ),
    );
  }
  
  // ✅ COMPARE: Build answer text structured for comparison
  Widget _buildCompareAnswerText(String text, TextStyle baseStyle) {
    // Split into paragraphs (by double newlines or periods followed by space)
    final paragraphs = text.split(RegExp(r'\n\n|\.\s+(?=[A-Z])'));
    final cleanParagraphs = paragraphs.where((p) => p.trim().isNotEmpty).toList();
    
    if (cleanParagraphs.length <= 1) {
      // Single paragraph - just render normally
      return StreamingTextWidget(
        targetText: text,
        enableAnimation: false,
        style: baseStyle,
      );
    }
    
    // Multiple paragraphs - render with subtle dividers
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cleanParagraphs.asMap().entries.map((entry) {
        final index = entry.key;
        final paragraph = entry.value.trim();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) ...[
              // Subtle divider between entities
              const SizedBox(height: 16),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: AppColors.border.withOpacity(0.3),
              ),
              const SizedBox(height: 8),
            ],
            StreamingTextWidget(
              targetText: paragraph + (paragraph.endsWith('.') ? '' : '.'),
              enableAnimation: false,
              style: baseStyle,
            ),
          ],
        );
      }).toList(),
    );
  }
  
  // ✅ CONFIDENCE-AWARE: Build text with bold first sentence for high confidence
  Widget _buildConfidenceAwareText(String text, TextStyle baseStyle) {
    if (baseStyle.fontWeight == FontWeight.w600) {
      // High confidence: Bold first sentence
      final firstSentenceEnd = text.indexOf('.');
      if (firstSentenceEnd > 0) {
        return RichText(
          text: TextSpan(
            style: baseStyle.copyWith(fontWeight: FontWeight.w600),
            children: [
              TextSpan(text: text.substring(0, firstSentenceEnd + 1)),
              TextSpan(
                text: text.substring(firstSentenceEnd + 1),
                style: baseStyle.copyWith(fontWeight: FontWeight.w400),
              ),
            ],
          ),
        );
      }
    }
    
    return StreamingTextWidget(
      targetText: text,
      enableAnimation: false,
      style: baseStyle,
    );
  }
  
  // ✅ DEPRECATED: This old method should NOT be used anymore
  // All queries should use PerplexityAnswerWidget directly (LLM-driven)
  Widget _buildClarificationCard(QuerySession session, AnswerContext context) {
    print('⚠️ WARNING: _buildClarificationCard called - should use PerplexityAnswerWidget instead');
    // ✅ FIXED: Use PerplexityAnswerWidget instead of old methods
    return PerplexityAnswerWidget(session: session);
  }
  
  // ✅ OLD METHOD (DEPRECATED - kept for reference only)
  Widget _buildClarificationCard_OLD(QuerySession session, AnswerContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accent.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.help_outline,
                size: 32,
                color: AppColors.accent,
              ),
              const SizedBox(height: 12),
              Text(
                "Answer", // ✅ Changed from context.intentHeader to "Answer"
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              StreamingTextWidget(
                targetText: session.summary ?? "",
                enableAnimation: false,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary.withOpacity(0.9),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ✅ FIX 3: Get evidence header based on UiMode (userGoal ONLY)
  String _getEvidenceHeader(String userGoal) {
    final uiMode = resolveUiMode(userGoal);
    
    switch (uiMode) {
      case UiMode.decide:
        return "Supporting examples"; // ✅ FIX 3: Decide-specific language (evidence, not shopping)
      case UiMode.browse:
        return "Top picks"; // ✅ FIX 3: Browse-specific language
      case UiMode.compare:
        return "Why this answer?"; // Compare uses default
      case UiMode.learn:
        return "Why this answer?"; // Learn uses default
      case UiMode.locate:
        return "Why this answer?"; // Locate uses default
      case UiMode.clarify:
        return "Why this answer?"; // Clarify uses default
    }
  }
  
  // ✅ ANSWER-FIRST: Build evidence section for cards
  // ✅ FIX 2: Accept userGoal parameter to use non-shopping language for decide queries
  Widget _buildEvidenceSection(BuildContext context, QuerySession session, WidgetRef ref, {String? userGoal}) {
    // ✅ COMPARE: Get answer context to check if this is a compare query
    final answerContext = AnswerContext.fromSession(session, null);
    final isCompare = answerContext.userGoal == "compare";
    final isDecideGoal = answerContext.userGoal == 'decide'; // ✅ FIX 6: Empty / Failed Card Safety
    
    // ✅ FAILURE/TIMEOUT: If cards fail to load, show "Fetching evidence..." but keep answer visible
    final hasCards = session.cards.isNotEmpty || session.results.isNotEmpty;
    final isLoadingCards = session.isStreaming || session.isParsing;
    
    // ✅ FIX 6: Empty / Failed Card Safety for decide queries
    // If userGoal === "decide" AND cards.length === 0:
    // - Do NOT show error cards
    // - Do NOT show shopping placeholders
    // - Answer-only UI must render cleanly
    if (isDecideGoal && !hasCards && !isLoadingCards) {
      return const SizedBox.shrink(); // Clean answer-only UI
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // ✅ FIX 3: Use UiMode (userGoal ONLY) to determine card framing language
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _getEvidenceHeader(userGoal ?? answerContext.userGoal),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ✅ FAILURE/TIMEOUT: Show loading state if cards are being fetched
        if (isLoadingCards && !hasCards)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  "Fetching evidence...",
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        // ✅ REMOVED: Old card-based rendering - all queries now use ResultShellRouter
        // Cards are no longer used, sections are rendered via PerplexityAnswerWidget
      ],
    );
  }
  
  // ✅ COMPARE: Build evidence content in compare layout (2-column grid or grouped)
  Widget _buildCompareEvidenceContent(BuildContext context, QuerySession session, WidgetRef ref) {
    final cards = session.cards;
    
    // If exactly 2 cards, render in 2-column grid
    if (cards.length == 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Option A
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ COMPARE: Option label
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _extractEntityName(cards[0]) ?? "Option A",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // Card content
                  _buildCompareCard(cards[0], session, ref),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Option B
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ COMPARE: Option label
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _extractEntityName(cards[1]) ?? "Option B",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // Card content
                  _buildCompareCard(cards[1], session, ref),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // More than 2 cards - render in grouped sections
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cards.asMap().entries.map((entry) {
        final index = entry.key;
        final card = entry.value;
        final optionLabel = _extractEntityName(card) ?? "Option ${String.fromCharCode(65 + index)}";
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ COMPARE: Option label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  optionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Card content (use existing card rendering but ensure equal weight)
              _buildCompareCard(card, session, ref),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  // ✅ COMPARE: Extract entity name from card (title, name, or brand)
  String? _extractEntityName(Map<String, dynamic> card) {
    return card['title']?.toString() ?? 
           card['name']?.toString() ?? 
           card['brand']?.toString() ??
           card['product_name']?.toString();
  }
  
  // ✅ COMPARE: Build card with equal visual weight (same size, same prominence)
  Widget _buildCompareCard(Map<String, dynamic> card, QuerySession session, WidgetRef ref) {
    // Use existing card rendering but ensure equal weight
    final intent = session.resultType;
    
    // ✅ COMPARE: For 2-column layout, wrap in container to ensure equal width
    Widget cardWidget;
    
    if (intent == 'shopping') {
      // Convert card to Product for product card rendering
      try {
        final product = Product.fromJson(card);
        cardWidget = _buildProductCard(product);
      } catch (e) {
        cardWidget = _buildGenericCompareCard(card);
      }
    } else if (intent == 'hotel' || intent == 'hotels') {
      cardWidget = _buildHotelCard(card);
    } else if (intent == 'places' || intent == 'location') {
      cardWidget = _buildPlaceCard(card);
    } else {
      cardWidget = _buildGenericCompareCard(card);
    }
    
    // ✅ COMPARE: Ensure equal visual weight by constraining height if needed
    // For 2-column layout, cards are already constrained by Expanded
    // For grouped layout, ensure consistent styling
    return cardWidget;
  }
  
  // ✅ COMPARE: Generic card for unknown types (ensures equal weight)
  Widget _buildGenericCompareCard(Map<String, dynamic> card) {
    final title = card['title']?.toString() ?? card['name']?.toString() ?? 'Unknown';
    final description = card['description']?.toString() ?? card['snippet']?.toString() ?? '';
    final image = card['image']?.toString() ?? card['thumbnail']?.toString();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null && image.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: image,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 150,
                  color: AppColors.surfaceVariant,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 150,
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.image, size: 48, color: AppColors.textSecondary),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFollowUps(QuerySession session, WidgetRef ref, {bool isCompare = false, bool isDecide = false}) {
    final followUpsAsync = ref.watch(followUpEngineProvider(session));
    
    return followUpsAsync.when(
      data: (followUps) {
        if (followUps.isEmpty) return const SizedBox.shrink();
        final limited = followUps.take(3).toList();
        
        // ✅ FOLLOW-UP HIERARCHY: Determine header based on goal
        String header;
        if (isCompare) {
          header = "Want to compare further?";
        } else if (isDecide) {
          header = "Explore more";
        } else {
          header = "Want to go deeper?";
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                header,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ✅ FOLLOW-UP HIERARCHY: First follow-up is primary, rest are secondary
            if (limited.isNotEmpty)
              _buildPrimaryFollowUp(limited[0], session, isDecide: isDecide),
            if (limited.length > 1)
              ...limited.skip(1).map((followUp) => _buildSecondaryFollowUp(followUp, session)),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
  
  // ✅ FOLLOW-UP HIERARCHY: Primary follow-up (larger, accent color/outline)
  Widget _buildPrimaryFollowUp(String suggestion, QuerySession session, {bool isDecide = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => model.onFollowUpTap(suggestion, session),
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.accent.withOpacity(0.2),
          highlightColor: AppColors.accent.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.accent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isDecide ? Icons.compare_arrows : Icons.arrow_forward,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // ✅ FOLLOW-UP HIERARCHY: Secondary follow-ups (muted styling)
  Widget _buildSecondaryFollowUp(String suggestion, QuerySession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => model.onFollowUpTap(suggestion, session),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: AppColors.textSecondary.withOpacity(0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildFollowUpItem(String suggestion, int index, QuerySession session) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => model.onFollowUpTap(suggestion, session),
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.accent.withOpacity(0.2),
          highlightColor: AppColors.accent.withOpacity(0.1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    suggestion,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ FIX 1: StatefulWidget for HotelCard to manage PageController
class _HotelCardWidget extends StatefulWidget {
  final Map<String, dynamic> hotel;
  final VoidCallback onTap;
  
  const _HotelCardWidget({required this.hotel, required this.onTap});
  
  @override
  State<_HotelCardWidget> createState() => _HotelCardWidgetState();
}

class _HotelCardWidgetState extends State<_HotelCardWidget> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  
  @override
  void initState() {
    super.initState();
    final images = _extractImages(widget.hotel);
    if (images.length > 1) {
      _pageController = PageController();
      _pageController.addListener(_onPageChanged);
    }
  }
  
  @override
  void dispose() {
    final images = _extractImages(widget.hotel);
    if (images.length > 1) {
      _pageController.removeListener(_onPageChanged);
      _pageController.dispose();
    }
    super.dispose();
  }
  
  void _onPageChanged() {
    if (_pageController.hasClients) {
      final newIndex = _pageController.page?.round() ?? 0;
      if (newIndex != _currentPageIndex) {
        setState(() {
          _currentPageIndex = newIndex;
        });
      }
    }
  }
  
  List<String> _extractImages(Map<String, dynamic> hotel) {
    final List<String> images = [];
    final imagesData = hotel['images'];
    if (imagesData != null) {
      if (imagesData is List) {
        for (final img in imagesData) {
          if (img is String && img.isNotEmpty) {
            images.add(img);
          } else if (img is Map) {
            final thumbnail = img['thumbnail']?.toString();
            final original = img['original_image']?.toString();
            final image = img['image']?.toString();
            final url = img['url']?.toString();
            final urlToAdd = thumbnail ?? original ?? image ?? url;
            if (urlToAdd != null && urlToAdd.isNotEmpty) {
              images.add(urlToAdd);
            }
          }
        }
      } else if (imagesData is String && imagesData.isNotEmpty) {
        images.add(imagesData);
      }
    }
    if (images.isEmpty) {
      final thumbnail = hotel['thumbnail']?.toString();
      if (thumbnail != null && thumbnail.isNotEmpty) {
        images.add(thumbnail);
      }
    }
    return images;
  }
  
  double _safeNumber(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }
  
  bool _hasHotelWebsite(Map<String, dynamic> hotel) {
    return (hotel['website']?.toString() ?? hotel['url']?.toString() ?? '').isNotEmpty;
  }
  
  bool _hasHotelPhone(Map<String, dynamic> hotel) {
    return (hotel['phone']?.toString() ?? hotel['phone_number']?.toString() ?? '').isNotEmpty;
  }
  
  bool _hasHotelLocation(Map<String, dynamic> hotel) {
    final lat = hotel['latitude'] ?? hotel['lat'] ?? hotel['gps_coordinates']?['latitude'];
    final lng = hotel['longitude'] ?? hotel['lng'] ?? hotel['gps_coordinates']?['longitude'];
    return lat != null && lng != null;
  }
  
  void _openHotelWebsite(Map<String, dynamic> hotel) async {
    final url = hotel['website']?.toString() ?? hotel['url']?.toString();
    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
  
  void _callHotel(Map<String, dynamic> hotel) async {
    final phone = hotel['phone']?.toString() ?? hotel['phone_number']?.toString();
    if (phone != null && phone.isNotEmpty) {
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }
  
  void _openHotelDirections(Map<String, dynamic> hotel) async {
    final lat = hotel['latitude'] ?? hotel['lat'] ?? hotel['gps_coordinates']?['latitude'];
    final lng = hotel['longitude'] ?? hotel['lng'] ?? hotel['gps_coordinates']?['longitude'];
    if (lat != null && lng != null) {
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
  
  Widget _buildHotelActionButton(String label, IconData icon, VoidCallback onPressed, {required bool enabled}) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? AppColors.primary : Colors.grey.shade300,
        foregroundColor: enabled ? Colors.white : Colors.grey.shade600,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final name = widget.hotel['name']?.toString() ?? 'Unknown Hotel';
    final rating = _safeNumber(widget.hotel['rating'], 0.0);
    final price = _safeNumber(widget.hotel['price'], 0.0);
    final description = widget.hotel['description']?.toString() ?? widget.hotel['summary']?.toString() ?? '';
    final images = _extractImages(widget.hotel);
    
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppTypography.title1.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (rating > 0) ...[
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    rating.toStringAsFixed(1),
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                if (price > 0)
                  Text(
                    '\$${price.toStringAsFixed(0)}',
                    style: AppTypography.title1.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: images.length == 1
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: images[0],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported, color: Colors.grey),
                          ),
                        ),
                      )
                    : PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(right: index < images.length - 1 ? 8 : 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: images[index],
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // ✅ FIX 1: Image indicator dots update based on current page
              if (images.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == _currentPageIndex ? AppColors.accent : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.image_not_supported, color: Colors.grey, size: 48),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildHotelActionButton(
                    'Website',
                    Icons.language,
                    () => _openHotelWebsite(widget.hotel),
                    enabled: _hasHotelWebsite(widget.hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHotelActionButton(
                    'Call',
                    Icons.phone,
                    () => _callHotel(widget.hotel),
                    enabled: _hasHotelPhone(widget.hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHotelActionButton(
                    'Directions',
                    Icons.directions,
                    () => _openHotelDirections(widget.hotel),
                    enabled: _hasHotelLocation(widget.hotel),
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ✅ FIX 1 & 2: StatefulWidget for PlaceCard to manage PageController and fix layout order
class _PlaceCardWidget extends StatefulWidget {
  final Map<String, dynamic> place;
  
  const _PlaceCardWidget({required this.place});
  
  @override
  State<_PlaceCardWidget> createState() => _PlaceCardWidgetState();
}

class _PlaceCardWidgetState extends State<_PlaceCardWidget> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  
  @override
  void initState() {
    super.initState();
    final images = _extractImages(widget.place);
    if (images.length > 1) {
      _pageController = PageController();
      _pageController.addListener(_onPageChanged);
    }
  }
  
  @override
  void dispose() {
    final images = _extractImages(widget.place);
    if (images.length > 1) {
      _pageController.removeListener(_onPageChanged);
      _pageController.dispose();
    }
    super.dispose();
  }
  
  void _onPageChanged() {
    if (_pageController.hasClients) {
      final newIndex = _pageController.page?.round() ?? 0;
      if (newIndex != _currentPageIndex) {
        setState(() {
          _currentPageIndex = newIndex;
        });
      }
    }
  }
  
  List<String> _extractImages(Map<String, dynamic> place) {
    final List<String> images = [];
    final Set<String> seenUrls = {};
    
    final imagesList = place['images'] as List?;
    final singleImage = place['image']?.toString() ?? 
                        place['thumbnail']?.toString() ?? 
                        place['photo']?.toString();
    
    if (imagesList != null && imagesList.isNotEmpty) {
      for (final img in imagesList) {
        final imgUrl = img?.toString().trim() ?? '';
        if (imgUrl.isNotEmpty && !seenUrls.contains(imgUrl)) {
          images.add(imgUrl);
          seenUrls.add(imgUrl);
        }
      }
    }
    
    if (singleImage != null && singleImage.isNotEmpty) {
      final trimmedSingleImage = singleImage.trim();
      if (!seenUrls.contains(trimmedSingleImage)) {
        images.insert(0, trimmedSingleImage);
        seenUrls.add(trimmedSingleImage);
      }
    }
    
    return images;
  }
  
  double _safeNumber(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }
  
  @override
  Widget build(BuildContext context) {
    final name = widget.place['name']?.toString() ?? widget.place['title']?.toString() ?? 'Unknown Place';
    final description = widget.place['description']?.toString() ?? widget.place['summary']?.toString() ?? '';
    final rating = _safeNumber(widget.place['rating'], 0.0);
    final images = _extractImages(widget.place);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ FIX 2: Place name and rating BEFORE images
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (rating > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
          // ✅ FIX 2: Images AFTER name and rating
          if (images.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: images.length == 1
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: images[0],
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported, color: Colors.grey),
                        ),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: EdgeInsets.only(right: index < images.length - 1 ? 8 : 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: images[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.image_not_supported, color: Colors.grey),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // ✅ FIX 1: Image indicator dots update based on current page
            if (images.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentPageIndex ? AppColors.accent : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ],
          // ✅ FIX 2: Description AFTER images
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Movie poster carousel StatefulWidget
class _MoviePosterCarouselWidget extends StatefulWidget {
  final List<String> images;
  
  const _MoviePosterCarouselWidget({required this.images});
  
  @override
  State<_MoviePosterCarouselWidget> createState() => _MoviePosterCarouselWidgetState();
}

class _MoviePosterCarouselWidgetState extends State<_MoviePosterCarouselWidget> {
  late PageController _pageController;
  int _currentIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index < widget.images.length - 1 ? 8 : 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: widget.images[index],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.images.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _currentIndex ? AppColors.accent : Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Widget to display Core Details and Box Office sections for movies
class _MovieDetailsSections extends StatefulWidget {
  final List<Map<String, dynamic>> movies;

  const _MovieDetailsSections({required this.movies});

  @override
  State<_MovieDetailsSections> createState() => _MovieDetailsSectionsState();
}

class _MovieDetailsSectionsState extends State<_MovieDetailsSections> {
  Map<String, dynamic>? _movieDetails;
  Map<String, dynamic>? _credits;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMovieDetails();
  }

  Future<void> _loadMovieDetails() async {
    if (widget.movies.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final firstMovie = widget.movies[0];
    final movieId = firstMovie['id'] as int? ?? 0;

    if (movieId == 0) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final details = await AgentService.getMovieDetails(movieId);
      final credits = await AgentService.getMovieCredits(movieId);
      
      if (mounted) {
        setState(() {
          _movieDetails = details;
          _credits = credits;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading movie details: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatRuntime(int? minutes) {
    if (minutes == null) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) {
      return '$hours hours $mins minutes';
    } else if (hours > 0) {
      return '$hours hours';
    } else if (mins > 0) {
      return '$mins minutes';
    }
    return '';
  }

  Widget _buildCoreDetailsSection() {
    final crew = _credits?['crew'] as List? ?? [];
    final cast = _credits?['cast'] as List? ?? [];
    final movieDetails = _movieDetails ?? {};
    
    // Extract director
    final director = crew.firstWhere(
      (c) => c['job'] == 'Director',
      orElse: () => null,
    );
    
    // Extract composer
    final composer = crew.firstWhere(
      (c) => c['job'] == 'Original Music Composer' || c['job'] == 'Music',
      orElse: () => null,
    );
    
    // Extract top cast (starring)
    final topCast = cast.take(3).toList();
    
    // Extract runtime
    final runtime = _formatRuntime(movieDetails['runtime'] as int?);
    
    // Extract storyline (overview)
    final storyline = movieDetails['overview']?.toString() ?? '';
    
    if (director == null && topCast.isEmpty && runtime.isEmpty && storyline.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Core Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (director != null) ...[
          _buildDetailRow('Director', '${director['name']?.toString() ?? 'Unknown'}.'),
          const SizedBox(height: 12),
        ],
        if (topCast.isNotEmpty) ...[
          _buildDetailRow(
            'Starring',
            topCast.asMap().entries.map((entry) {
              final index = entry.key;
              final actor = entry.value;
              final name = actor['name']?.toString() ?? 'Unknown';
              final character = actor['character']?.toString();
              if (character != null && character.isNotEmpty) {
                return '$name (as $character)';
              }
              if (index == topCast.length - 1 && topCast.length > 1) {
                return 'and $name';
              }
              return name;
            }).join(', '),
          ),
          const SizedBox(height: 12),
        ],
        if (storyline.isNotEmpty) ...[
          _buildDetailRow('Storyline', '"$storyline"'),
          const SizedBox(height: 12),
        ],
        if (composer != null) ...[
          _buildDetailRow('Music', 'Composed by ${composer['name']?.toString() ?? 'Unknown'}.'),
          const SizedBox(height: 12),
        ],
        if (runtime.isNotEmpty) ...[
          _buildDetailRow('Running Time', 'Approximately $runtime.'),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxOfficeSection() {
    final movieDetails = _movieDetails ?? {};
    final budget = movieDetails['budget'] as int?;
    final revenue = movieDetails['revenue'] as int?;
    final rating = (movieDetails['vote_average'] as num?)?.toDouble() ?? 0.0;
    final voteCount = movieDetails['vote_count'] as int? ?? 0;
    
    // Format currency
    String formatCurrency(int? amount) {
      if (amount == null || amount == 0) return '';
      if (amount >= 1000000000) {
        return '\$${(amount / 1000000000).toStringAsFixed(2)}B';
      } else if (amount >= 1000000) {
        return '\$${(amount / 1000000).toStringAsFixed(2)}M';
      } else if (amount >= 1000) {
        return '\$${(amount / 1000).toStringAsFixed(2)}K';
      }
      return '\$$amount';
    }
    
    final budgetFormatted = formatCurrency(budget);
    final revenueFormatted = formatCurrency(revenue);
    
    // Generate box office content
    final List<String> boxOfficeItems = [];
    
    if (budgetFormatted.isNotEmpty || revenueFormatted.isNotEmpty) {
      if (budgetFormatted.isNotEmpty && revenueFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film had a production budget of $budgetFormatted and grossed $revenueFormatted worldwide.');
      } else if (budgetFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film had a production budget of $budgetFormatted.');
      } else if (revenueFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film grossed $revenueFormatted worldwide.');
      }
    }
    
    if (revenueFormatted.isNotEmpty && budgetFormatted.isNotEmpty && budget != null && budget > 0) {
      final profit = revenue! - budget;
      final profitFormatted = formatCurrency(profit);
      if (profit > 0) {
        boxOfficeItems.add('**Weekend Performance:** The film generated a profit of $profitFormatted.');
      }
    }
    
    if (rating > 0 && voteCount > 0) {
      final ratingText = rating >= 7.0 
          ? 'positive' 
          : rating >= 5.0 
              ? 'mixed' 
              : 'negative';
      boxOfficeItems.add('**Critical Response:** The film has received $ratingText reviews, with an average rating of ${rating.toStringAsFixed(1)}/10 based on ${voteCount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} votes.');
    }
    
    if (boxOfficeItems.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text(
          'Box Office & Reception',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...boxOfficeItems.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildBoxOfficeItem(item),
        )),
      ],
    );
  }

  Widget _buildBoxOfficeItem(String text) {
    // Parse format: "**Label:** content"
    final match = RegExp(r'\*\*(.+?):\*\*\s*(.+)').firstMatch(text);
    if (match != null) {
      final label = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      return RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: content,
              style: const TextStyle(
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }
    // Fallback if format doesn't match
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_movieDetails == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCoreDetailsSection(),
        _buildBoxOfficeSection(),
        const SizedBox(height: 20),
      ],
    );
  }
}

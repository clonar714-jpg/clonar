// ======================================================================
// LEARN RESULT SHELL - Answer-only rendering for learning queries
// ======================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ResultShell.dart';
import '../../theme/AppColors.dart';
import '../../widgets/PerplexityAnswerWidget.dart';
import '../../providers/follow_up_engine_provider.dart';

/// Result shell for "learn" goal - answer only, no cards, no domain chips
class LearnResultShell extends ResultShell {
  const LearnResultShell({
    super.key,
    required super.session,
    required super.context,
    required super.model,
  });

  @override
  Widget buildAnswerSection() {
    // ✅ CRITICAL: Log that we're building answer section
    print('🎯 LearnResultShell.buildAnswerSection called');
    print('  - Session has sections: ${session.sections?.length ?? 0}');
    print('  - Session has summary: ${session.summary != null && session.summary!.isNotEmpty}');
    
    // ✅ PERPLEXITY-STYLE: Use simple PerplexityAnswerWidget
    // No header needed - sections speak for themselves (like Perplexity)
    return PerplexityAnswerWidget(
      sessionId: session.sessionId, // ✅ PERPLEXITY-STYLE: Only store sessionId
    );
  }

  Widget _buildKeyTakeaways(String summary) {
    // ✅ FIX: Use concept-based extraction (same as SessionRenderer)
    final takeaways = _extractKeyTakeaways(summary);
    
    // ✅ UI Enforcement Rule: Hide if empty (better than duplicated ones)
    if (takeaways.isEmpty) return const SizedBox.shrink();
    
    return Container(
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
          const SizedBox(height: 8),
          ...takeaways.map((takeaway) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
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
    
    // Pattern 2: Noun phrases (common technical/domain terms)
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

  @override
  Widget? buildEvidenceSection(WidgetRef ref) {
    // ✅ LEARN: No cards for learn goal
    return null;
  }

  @override
  Widget? buildAdditionalContent(WidgetRef ref) {
    // ✅ LEARN: No additional content
    return null;
  }

  @override
  Widget? buildFollowUps(WidgetRef ref) {
    // Follow-ups appear as depth expanders, not actions
    return _buildDepthExpanders(ref);
  }

  Widget _buildDepthExpanders(WidgetRef ref) {
    // Use existing follow-up provider but style differently
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
              return _buildDepthExpanderItem(entry.value, entry.key);
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildDepthExpanderItem(String suggestion, int index) {
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
}


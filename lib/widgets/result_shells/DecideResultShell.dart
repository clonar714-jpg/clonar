// ======================================================================
// DECIDE RESULT SHELL - Verdict-first rendering for decision queries
// ======================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ResultShell.dart';
import '../../theme/AppColors.dart';
import '../../widgets/PerplexityAnswerWidget.dart';
import '../../providers/follow_up_engine_provider.dart';

/// Result shell for "decide" goal - verdict first, evidence cards as supporting examples
class DecideResultShell extends ResultShell {
  const DecideResultShell({
    super.key,
    required super.session,
    required super.context,
    required super.model,
  });

  @override
  Widget buildAnswerSection() {
    // ✅ SIMPLIFIED: Use PerplexityAnswerWidget for all queries
    // No header needed - sections speak for themselves (like Perplexity)
    return PerplexityAnswerWidget(
      sessionId: session.sessionId, // ✅ PERPLEXITY-STYLE: Only store sessionId
    );
  }

  @override
  Widget? buildEvidenceSection(WidgetRef ref) {
    // ✅ SIMPLIFIED: No cards - Perplexity-style answers don't need cards
    // Sections and sources are enough
    return null;
  }

  @override
  Widget? buildFollowUps(WidgetRef ref) {
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
                "See alternatives", // ✅ FIX 2: Decide-specific follow-up header
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...limited.map((followUp) {
              return _buildDecideFollowUpItem(followUp);
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildDecideFollowUpItem(String suggestion) {
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
                  Icons.compare_arrows,
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

  @override
  Widget? buildAdditionalContent(WidgetRef ref) {
    // ✅ DECIDE: No additional content needed
    return null;
  }
}


// ======================================================================
// CLARIFICATION RESULT SHELL - Clarification-only rendering
// ======================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ResultShell.dart';
import '../../theme/AppColors.dart';
import '../../widgets/StreamingTextWidget.dart';

/// Result shell for clarification-only responses (hard ambiguity)
class ClarificationResultShell extends ResultShell {
  const ClarificationResultShell({
    super.key,
    required super.session,
    required super.context,
    required super.model,
  });

  @override
  Widget buildAnswerSection() {
    // ✅ CRITICAL FIX: Use full answer if available, fallback to summary
    // session.answer contains the complete answer text, session.summary is just the first paragraph
    final answerText = session.answer ?? session.summary ?? "";
    
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
                targetText: answerText,
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

  @override
  Widget? buildEvidenceSection(WidgetRef ref) {
    // ✅ CLARIFICATION: No cards
    return null;
  }

  @override
  Widget? buildFollowUps(WidgetRef ref) {
    // ✅ CLARIFICATION: No follow-ups
    return null;
  }

  @override
  Widget? buildAdditionalContent(WidgetRef ref) {
    // ✅ CLARIFICATION: No additional content
    return null;
  }
}


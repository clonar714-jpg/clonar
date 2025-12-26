// ======================================================================
// RESULT SHELL - Goal-aware UI architecture
// ======================================================================
// Abstract base class for goal-specific result rendering

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/query_session_model.dart';
import '../../models/AnswerContext.dart';
import '../SessionRenderer.dart';

/// Abstract base class for goal-specific result shells
abstract class ResultShell extends StatelessWidget {
  final QuerySession session;
  final AnswerContext context;
  final SessionRenderModel model;
  
  const ResultShell({
    super.key,
    required this.session,
    required this.context,
    required this.model,
  });
  
  /// Build the answer section (goal-specific)
  Widget buildAnswerSection();
  
  /// Build the evidence section (cards) - optional
  Widget? buildEvidenceSection(WidgetRef ref);
  
  /// Build follow-up suggestions - optional
  Widget? buildFollowUps(WidgetRef ref);
  
  /// Build additional content (goal-specific)
  Widget? buildAdditionalContent(WidgetRef ref);
  
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Answer section (always first)
            buildAnswerSection(),
            
            // Evidence section (if applicable)
            if (buildEvidenceSection(ref) != null)
              buildEvidenceSection(ref)!,
            
            // Additional content (goal-specific)
            if (buildAdditionalContent(ref) != null)
              buildAdditionalContent(ref)!,
            
            // Follow-ups (if applicable)
            if (buildFollowUps(ref) != null)
              buildFollowUps(ref)!,
          ],
        );
      },
    );
  }
}


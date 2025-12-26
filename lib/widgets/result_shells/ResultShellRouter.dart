// ======================================================================
// RESULT SHELL ROUTER - Routes to appropriate goal-specific shell
// ======================================================================

import 'package:flutter/material.dart';
import '../../models/query_session_model.dart';
import '../../models/AnswerContext.dart';
import 'ResultShell.dart';
import 'LearnResultShell.dart';
import 'DecideResultShell.dart';
import 'ClarificationResultShell.dart';
import '../SessionRenderer.dart';

// Forward declaration - implementations will be created
// For now, we'll create stub implementations that delegate to existing SessionRenderer logic

/// Router that selects the appropriate result shell based on goal and ambiguity
class ResultShellRouter extends StatelessWidget {
  final QuerySession session;
  final AnswerContext answerContext;
  final SessionRenderModel model;
  
  const ResultShellRouter({
    super.key,
    required this.session,
    required this.answerContext,
    required this.model,
  });
  
  @override
  Widget build(BuildContext context) {
    // ✅ CRITICAL: Log routing decision
    print('🎯 ResultShellRouter: Routing query "${session.query}"');
    print('  - User goal: ${answerContext.userGoal}');
    print('  - Is clarification: ${answerContext.isClarificationOnly}');
    print('  - Session has sections: ${session.sections?.length ?? 0}');
    
    // ✅ CRITICAL: Hard ambiguity always shows clarification
    if (answerContext.isClarificationOnly) {
      print('  - → Routing to ClarificationResultShell');
      return ClarificationResultShell(
        session: session,
        context: answerContext,
        model: model,
      );
    }
    
    // Route based on user goal
    switch (answerContext.userGoal) {
      case 'learn':
        print('  - → Routing to LearnResultShell');
        return LearnResultShell(
          session: session,
          context: answerContext,
          model: model,
        );
      case 'compare':
        // TODO: Create CompareResultShell - for now, fallback to learn shell
        return LearnResultShell(
          session: session,
          context: answerContext,
          model: model,
        );
      case 'decide':
        return DecideResultShell(
          session: session,
          context: answerContext,
          model: model,
        );
      case 'browse':
        // TODO: Create BrowseResultShell - for now, fallback to learn shell
        return LearnResultShell(
          session: session,
          context: answerContext,
          model: model,
        );
      case 'locate':
        // TODO: Create LocateResultShell - for now, fallback to learn shell
        return LearnResultShell(
          session: session,
          context: answerContext,
          model: model,
        );
      default:
        // Default to learn shell for unknown goals
        return LearnResultShell(
          session: session,
          context: answerContext,
          model: model,
        );
    }
  }
}


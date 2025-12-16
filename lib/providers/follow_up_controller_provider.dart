import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/query_session_model.dart';
import 'session_history_provider.dart';
import 'agent_provider.dart';
import 'streaming_text_provider.dart';
import 'scroll_provider.dart';

/// ✅ PHASE 5: Follow-up controller provider - handles follow-up query submission
class FollowUpController extends StateNotifier<void> {
  final Ref ref;

  FollowUpController(this.ref) : super(null);

  /// Handle follow-up query submission
  Future<void> handleFollowUp(String followUp, QuerySession parentSession) async {
    if (kDebugMode) {
      debugPrint('🎯 Handling follow-up: "$followUp" for parent: "${parentSession.query}"');
    }

    try {
      // ✅ Step 1: Reset streaming text
      ref.read(streamingTextProvider.notifier).reset();

      // ✅ Step 2: Create new QuerySession with context
      final newSession = QuerySession(
        query: followUp,
        isStreaming: true,
        isParsing: false,
        // Inherit context from parent session
        imageUrl: parentSession.imageUrl,
      );

      // ✅ Step 3: Push new session into sessionHistoryProvider
      ref.read(sessionHistoryProvider.notifier).addSession(newSession);

      // ✅ Step 4: Build conversation history for context
      final sessions = ref.read(sessionHistoryProvider);
      final history = <Map<String, dynamic>>[];
      
      // Include parent session and previous sessions for context
      for (final session in sessions) {
        if (session.query.isNotEmpty && 
            session.summary != null && 
            session.summary!.isNotEmpty) {
          history.add({
            'query': session.query,
            'summary': session.summary,
            'intent': session.intent ?? session.resultType,
            'cardType': session.cardType ?? session.resultType,
          });
        }
      }

      // ✅ Step 5: Submit query to agent with context
      // Note: We'll need to update agentControllerProvider to accept context
      // For now, we'll use the existing submitQuery method
      await ref.read(agentControllerProvider.notifier).submitQuery(
        followUp,
        imageUrl: parentSession.imageUrl,
      );

      if (kDebugMode) {
        debugPrint('✅ Follow-up query submitted successfully');
      }

      // ✅ PHASE 7: Trigger scroll to bottom via scroll provider
      ref.read(scrollProvider.notifier).scrollToBottom();

    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ Error handling follow-up: $e\n$st');
      }
      rethrow;
    }
  }
}

/// ✅ PHASE 10: Follow-up controller provider with keepAlive
final followUpControllerProvider = StateNotifierProvider<FollowUpController, void>(
  (ref) {
    ref.keepAlive(); // ✅ PHASE 10: Keep alive for better performance
    return FollowUpController(ref);
  },
);


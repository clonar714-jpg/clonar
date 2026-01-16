import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/query_session_model.dart';
import 'agent_provider.dart';
import 'scroll_provider.dart';

/// ✅ PHASE 5: Follow-up controller provider - handles follow-up query submission
class FollowUpController extends StateNotifier<void> {
  final Ref ref;

  FollowUpController(this.ref) : super(null);

  /// Handle follow-up query submission
  Future<void> handleFollowUp(String followUp, QuerySession parentSession) async {
    if (kDebugMode) {
      debugPrint('🎯🎯🎯 HANDLING FOLLOW-UP: "$followUp" for parent: "${parentSession.query}"');
    }

    try {
      print("🔥🔥🔥 FOLLOW-UP: Step 1 - Starting new query");
      // ✅ CRITICAL: Single source of truth - no need to reset streamingTextProvider
      // The sessionHistoryProvider will handle the new session

      print("🔥🔥🔥 FOLLOW-UP: Step 2 - Calling submitQuery");
      // ✅ FIX: Don't create session here - submitQuery will create it
      // Just call submitQuery directly, it will handle session creation and history
      await ref.read(agentControllerProvider.notifier).submitQuery(
        followUp,
        imageUrl: parentSession.imageUrl,
        useStreaming: true, // ✅ Explicitly enable streaming
      );

      print("🔥🔥🔥 FOLLOW-UP: Step 3 - Query submitted, scrolling to top");
      if (kDebugMode) {
        debugPrint('✅ Follow-up query submitted successfully');
      }

      // ✅ FIX: Scroll to top to show new query (user can swipe up to see results)
      ref.read(scrollProvider.notifier).scrollToTop();

    } catch (e, st) {
      print("🔥🔥🔥 FOLLOW-UP ERROR: $e");
      print("🔥🔥🔥 FOLLOW-UP STACK: $st");
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


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/query_session_model.dart';
import 'agent_provider.dart';
import 'scroll_provider.dart';


class FollowUpController extends StateNotifier<void> {
  final Ref ref;

  FollowUpController(this.ref) : super(null);

 
  Future<void> handleFollowUp(String followUp, QuerySession parentSession) async {
    if (kDebugMode) {
      debugPrint('🎯🎯🎯 HANDLING FOLLOW-UP: "$followUp" for parent: "${parentSession.query}"');
    }

    // ✅ HISTORY MODE GUARD: If parent session is finalized, we're viewing history
    // Follow-ups in history mode are allowed (they create new queries), but we check for duplicates
    if (parentSession.isFinalized && kDebugMode) {
      debugPrint('📚 History mode: Parent session is finalized, allowing follow-up (will check for duplicates)');
    }

    try {
      print("🔥🔥🔥 FOLLOW-UP: Step 1 - Starting new query");
      

      print("🔥🔥🔥 FOLLOW-UP: Step 2 - Calling submitQuery");
     
      await ref.read(agentControllerProvider.notifier).submitQuery(
        followUp,
        imageUrl: parentSession.imageUrl,
        useStreaming: true, 
      );

      print("🔥🔥🔥 FOLLOW-UP: Step 3 - Query submitted, scrolling to top");
      if (kDebugMode) {
        debugPrint('✅ Follow-up query submitted successfully');
      }

      
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


final followUpControllerProvider = StateNotifierProvider<FollowUpController, void>(
  (ref) {
    ref.keepAlive(); 
    return FollowUpController(ref);
  },
);


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/query_session_model.dart';

/// ✅ SIMPLIFIED: Follow-up engine provider - returns backend LLM-generated suggestions
/// 
/// The backend (node/src/followup/index.ts) generates all follow-ups using LLM.
/// This provider simply returns them directly - no processing needed.
/// 
/// Backend already handles:
/// - Deduplication (novelty checking against recent follow-ups)
/// - Reranking (embedding-based similarity)
/// - Limiting to top 3 suggestions
final followUpEngineProvider = FutureProvider.family<List<String>, QuerySession>((ref, session) async {
  ref.keepAlive(); 
  
  try {
    // ✅ Return backend suggestions directly - backend handles all logic
    if (session.followUpSuggestions.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('✅ Using backend LLM-generated follow-ups: ${session.followUpSuggestions}');
      }
      return session.followUpSuggestions;
    }
    
    // ✅ No follow-ups from backend - return empty list
    if (kDebugMode) {
      debugPrint('ℹ️ No backend follow-ups found for session: ${session.sessionId}');
    }
    
    return [];
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('❌ Error in follow-up engine: $e\n$st');
    }
    
    return [];
  }
});

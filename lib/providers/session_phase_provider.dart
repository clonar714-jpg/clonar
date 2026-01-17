import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/query_session_model.dart';
import 'session_history_provider.dart';


final sessionPhaseProvider = Provider.family<QueryPhase, String>((ref, sessionId) {
  final sessions = ref.watch(sessionHistoryProvider);
  final session = sessions.firstWhere(
    (s) => s.sessionId == sessionId,
    orElse: () => QuerySession(
      sessionId: sessionId,
      query: '',
      phase: QueryPhase.searching,
    ),
  );
  
  // ✅ HISTORY MODE FIX: If session is finalized, it must be in 'done' phase
  // This prevents history sessions from showing 'searching' phase and triggering re-execution
  if (session.isFinalized && session.phase != QueryPhase.done) {
    return QueryPhase.done;
  }
  
  return session.phase;
});


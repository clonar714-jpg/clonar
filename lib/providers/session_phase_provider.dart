import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/query_session_model.dart';
import 'session_history_provider.dart';

/// ✅ PERPLEXITY-STYLE: Phase-only provider (prevents rebuilds on text changes)
/// Widgets watch phase, not text - this eliminates rebuild loops
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
  return session.phase;
});


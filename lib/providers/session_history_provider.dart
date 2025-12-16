import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/query_session_model.dart';

/// ✅ RIVERPOD: Session history provider to manage list of QuerySession
class SessionHistoryNotifier extends StateNotifier<List<QuerySession>> {
  SessionHistoryNotifier() : super([]);

  void addSession(QuerySession session) {
    state = [...state, session];
  }

  void updateSession(int index, QuerySession session) {
    if (index >= 0 && index < state.length) {
      final newState = List<QuerySession>.from(state);
      newState[index] = session;
      state = newState;
    }
  }

  void replaceLastSession(QuerySession session) {
    if (state.isNotEmpty) {
      final newState = List<QuerySession>.from(state);
      newState[newState.length - 1] = session;
      // ✅ FIX: Force state update by creating new list reference
      state = [...newState]; // Create new list to ensure Riverpod sees the change
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Replaced last session");
        print("  - New session query: ${session.query}");
        print("  - New session isStreaming: ${session.isStreaming}");
        print("  - New session cards: ${session.cards.length}");
        print("  - Total sessions: ${state.length}");
      }
    } else {
      state = [session];
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Added first session");
        print("  - Session query: ${session.query}");
        print("  - Session isStreaming: ${session.isStreaming}");
      }
    }
  }

  void clear() {
    state = [];
  }

  void removeSession(int index) {
    if (index >= 0 && index < state.length) {
      final newState = List<QuerySession>.from(state);
      newState.removeAt(index);
      state = newState;
    }
  }
}

/// ✅ PHASE 10: Session history provider with keepAlive for stability
final sessionHistoryProvider =
    StateNotifierProvider<SessionHistoryNotifier, List<QuerySession>>(
  (ref) {
    ref.keepAlive(); // ✅ PHASE 10: Keep alive to prevent unnecessary recreation
    return SessionHistoryNotifier();
  },
);


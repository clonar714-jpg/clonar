import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/query_session_model.dart';

/// ✅ RIVERPOD: Session history provider to manage list of QuerySession
class SessionHistoryNotifier extends StateNotifier<List<QuerySession>> {
  SessionHistoryNotifier() : super([]);

  void addSession(QuerySession session) {
    state = [...state, session];
  }

  void updateSession(int index, QuerySession incomingSession) {
    if (index >= 0 && index < state.length) {
      final newState = List<QuerySession>.from(state);
      final existingSession = newState[index];
      
      // ✅ CRITICAL: If existing session is finalized, prevent replacement
      // Finalized sessions preserve answer content - only merge metadata
      if (existingSession.isFinalized && !incomingSession.isFinalized) {
        // ✅ FINALIZED: Preserve answer content, update metadata only
        if (kDebugMode) {
          print("🔒 Preventing replacement of finalized session at index $index");
          print("  - Preserving answer content (sections, sources, cards)");
        }
        
        final mergedSession = existingSession.copyWith(
          timestamp: incomingSession.timestamp, // Update timestamp only
          // DO NOT update: summary, sections, sources, cards, images
        );
        newState[index] = mergedSession;
      } else {
        // Not finalized or both finalized - can be replaced/merged
        final mergedSession = existingSession.mergeWith(incomingSession);
        newState[index] = mergedSession;
      }
      
      state = newState;
    }
  }

  /// ✅ CRITICAL FIX: Update session by ID (prevents race conditions)
  /// This ensures only the matching session is updated, not sessions.last
  void updateSessionById(String sessionId, QuerySession updatedSession) {
    final newState = List<QuerySession>.from(state);
    final index = newState.indexWhere((s) => s.sessionId == sessionId);
    
    if (index == -1) {
      if (kDebugMode) {
        print("⚠️ Session not found for update: $sessionId");
        print("  - Available sessions: ${newState.map((s) => s.sessionId).join(', ')}");
      }
      return; // Session not found - skip update
    }
    
    final existingSession = newState[index];
    
    // ✅ CRITICAL: If existing session is finalized, enforce single-writer rule
    if (existingSession.isFinalized) {
      // ✅ FINALIZED: Streaming events can ONLY update summary, never structured data
      // END event is the only place where structured data is written
      if (updatedSession.isFinalized) {
        // Both finalized - allow merge (but mergeWith will preserve finalized data)
        final mergedSession = existingSession.mergeWith(updatedSession);
        newState[index] = mergedSession;
      } else {
        // Existing is finalized, incoming is not - only allow summary updates
        if (kDebugMode) {
          print("🔒 Finalized session - only allowing summary update");
          print("  - Session ID: $sessionId");
          print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
          print("  - Incoming sections: ${updatedSession.sections?.length ?? 0}");
        }
        
        // ✅ SINGLE-WRITER RULE: Only update summary, preserve all structured data
        final mergedSession = existingSession.copyWith(
          summary: updatedSession.summary, // Allow summary update
          isStreaming: updatedSession.isStreaming,
          // DO NOT update: sections, sources, cards, images, answer (preserve finalized data)
        );
        newState[index] = mergedSession;
      }
    } else {
      // Not finalized - allow merge
      final mergedSession = existingSession.mergeWith(updatedSession);
      newState[index] = mergedSession;
    }
    
    state = newState;
    
    if (kDebugMode) {
      print("🔄 Updated session by ID: $sessionId");
      print("  - Query: ${newState[index].query}");
      print("  - Sections: ${newState[index].sections?.length ?? 0}");
      print("  - isFinalized: ${newState[index].isFinalized}");
    }
  }

  /// ✅ MERGE: Replace last session by merging with incoming partial update
  /// This ensures state growth is monotonic - once data exists, it never disappears
  /// Matches ChatGPT/Perplexity behavior: streaming enriches, doesn't replace
  /// 
  /// ✅ PERPLEXITY-STYLE: If existing session is finalized (END event processed),
  /// streaming "message" events cannot overwrite structured data (sections, sources, cards).
  /// Only summary can be updated during streaming. END event is the single authoritative commit.
  /// 
  /// ✅ CRITICAL: Finalized sessions are NEVER replaced by DB-hydrated sessions.
  /// DB does not store sections/sources/cards - only streaming answer has this data.
  /// Finalized sessions preserve their answer content - only metadata can be updated.
  void replaceLastSession(QuerySession incomingSession) {
    if (state.isNotEmpty) {
      final newState = List<QuerySession>.from(state);
      final lastIndex = newState.length - 1;
      final existingSession = newState[lastIndex];
      
      // ✅ CRITICAL: If existing session is finalized, prevent replacement from DB-hydrated session
      // DB-hydrated sessions don't have sections/sources/cards - they would overwrite finalized answer content
      if (existingSession.isFinalized) {
        // ✅ FINALIZED: Check if incoming session would clear structured data
        final wouldClearSections = (existingSession.sections?.length ?? 0) > 0 && 
                                   (incomingSession.sections?.length ?? 0) == 0;
        final wouldClearSources = existingSession.sources.isNotEmpty && 
                                  incomingSession.sources.isEmpty;
        
        if (wouldClearSections || wouldClearSources) {
          // ✅ CRITICAL: Incoming session would clear finalized answer content - preserve it
          if (kDebugMode) {
            print("🔒🔒🔒 CRITICAL: Preventing clearing of finalized session data!");
            print("  - Query: ${existingSession.query}");
            print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
            print("  - Incoming sections: ${incomingSession.sections?.length ?? 0}");
            print("  - Existing sources: ${existingSession.sources.length}");
            print("  - Incoming sources: ${incomingSession.sources.length}");
            print("  - Existing isFinalized: ${existingSession.isFinalized}");
            print("  - Incoming isFinalized: ${incomingSession.isFinalized}");
            print("  - Preserving finalized answer content (sections, sources, cards)");
          }
          
          // ✅ Merge: Preserve finalized answer content, update metadata only
          final mergedSession = existingSession.copyWith(
            timestamp: incomingSession.timestamp, // Update timestamp from DB
            // DO NOT update: summary, sections, sources, cards, images (preserve from streaming)
          );
          newState[lastIndex] = mergedSession;
          state = [...newState];
          return;
        }
        
        // If incoming session has data, allow merge (but mergeWith will preserve finalized data)
        if (kDebugMode && !incomingSession.isFinalized == false) {
          print("🔒 Merging finalized session with non-finalized incoming");
          print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
          print("  - Incoming sections: ${incomingSession.sections?.length ?? 0}");
        }
      }
      
      // ✅ MERGE: Merge incoming partial update with existing session
      // ✅ PERPLEXITY-STYLE: mergeWith() respects isFinalized flag - prevents streaming from overwriting END data
      // This preserves all existing data and only updates what's new
      final mergedSession = existingSession.mergeWith(incomingSession);
      
      // ✅ CRITICAL DEBUG: Log if sections are being cleared
      if (kDebugMode && existingSession.isFinalized) {
        if ((existingSession.sections?.length ?? 0) > 0 && (mergedSession.sections?.length ?? 0) == 0) {
          print("⚠️⚠️⚠️ CRITICAL: Sections cleared during merge!");
          print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
          print("  - Merged sections: ${mergedSession.sections?.length ?? 0}");
          print("  - Incoming sections: ${incomingSession.sections?.length ?? 0}");
          print("  - Existing isFinalized: ${existingSession.isFinalized}");
          print("  - Incoming isFinalized: ${incomingSession.isFinalized}");
        }
      }
      
      newState[lastIndex] = mergedSession;
      
      // ✅ FIX: Force state update by creating new list reference
      state = [...newState]; // Create new list to ensure Riverpod sees the change
      
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Merged last session");
        print("  - Query: ${mergedSession.query}");
        print("  - Summary: ${mergedSession.summary?.length ?? 0} chars");
        print("  - Sections: ${mergedSession.sections?.length ?? 0}");
        print("  - Sources: ${mergedSession.sources.length}");
        print("  - Follow-ups: ${mergedSession.followUpSuggestions.length}");
        print("  - CardsByDomain: ${mergedSession.cardsByDomain?.keys.join(', ') ?? 'none'}");
        print("  - isStreaming: ${mergedSession.isStreaming}");
        print("  - Total sessions: ${state.length}");
      }
    } else {
      // ✅ DEFENSIVE: Create initial session if none exists
      // This handles edge cases where streaming starts before initial session is created
      state = [incomingSession];
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Created initial session (defensive)");
        print("  - Session query: ${incomingSession.query}");
        print("  - Session isStreaming: ${incomingSession.isStreaming}");
      }
    }
  }

  /// Clear all sessions (use with caution)
  /// ✅ CRITICAL: This removes ALL sessions including finalized ones.
  /// Only use when intentionally replacing all sessions (e.g., loading a different chat).
  /// Finalized sessions' answer content will be lost if not preserved elsewhere.
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

  /// Replace all sessions with new list (for chat history replay)
  /// ✅ CRITICAL: Finalized sessions are NEVER replaced - they preserve answer content (sections, sources, cards)
  /// DB-hydrated sessions only update metadata (title, timestamps) - answer content comes from streaming
  /// 
  /// MODE BEHAVIOR:
  /// - HISTORY_MODE: state is empty (cleared before load), so simple replace is used
  /// - NEW_CHAT_MODE: state may have finalized sessions, so merge logic preserves answer content
  void replaceAllSessions(List<QuerySession> incomingSessions) {
    // ✅ PERPLEXITY-STYLE: If existing sessions include finalized ones, merge instead of replace
    // This prevents DB-hydrated sessions (without sections) from overwriting finalized streaming sessions
    // ✅ HISTORY_MODE: When loading old chats, state is empty (cleared in _loadChat), so this branch is skipped
    if (state.isNotEmpty && incomingSessions.isNotEmpty) {
      final mergedSessions = <QuerySession>[];
      
      // Match incoming sessions with existing sessions by query
      for (final incomingSession in incomingSessions) {
        // Find matching existing session by query
        final existingIndex = state.indexWhere((s) => s.query == incomingSession.query);
        
        if (existingIndex >= 0) {
          final existingSession = state[existingIndex];
          
          // ✅ CRITICAL: If existing session is finalized, preserve its answer content
          // DB does not store sections/sources/cards - only streaming answer has this data
          // Merge: keep finalized answer content, update metadata only
          if (existingSession.isFinalized) {
            if (kDebugMode) {
              print("🔒 Preserving finalized session: ${existingSession.query}");
              print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
              print("  - Incoming sections: ${incomingSession.sections?.length ?? 0}");
            }
            
            // ✅ Merge: Preserve finalized answer content, update metadata only
            final merged = existingSession.copyWith(
              // Metadata only - preserve answer content
              timestamp: incomingSession.timestamp, // Update timestamp from DB
              // DO NOT update: summary, sections, sources, cards, images (preserve from streaming)
            );
            mergedSessions.add(merged);
          } else {
            // Not finalized - can be replaced with DB version
            mergedSessions.add(incomingSession);
          }
        } else {
          // No matching session - add new one
          mergedSessions.add(incomingSession);
        }
      }
      
      state = mergedSessions;
      
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Merged sessions (preserved finalized answer content)");
        print("  - Total sessions: ${mergedSessions.length}");
        for (int i = 0; i < mergedSessions.length; i++) {
          final s = mergedSessions[i];
          print("  - Session $i: ${s.query} (${s.summary?.length ?? 0} chars, finalized: ${s.isFinalized}, sections: ${s.sections?.length ?? 0})");
        }
      }
    } else {
      // ✅ HISTORY_MODE: No existing sessions (cleared before load) - simple replace
      // This is the expected path for old chat replay - state is empty, so we do a direct replace
      state = List<QuerySession>.from(incomingSessions);
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Replaced all sessions (HISTORY_MODE - simple replace)");
        print("  - Previous state: empty (cleared before load)");
        print("  - Total sessions: ${incomingSessions.length}");
        for (int i = 0; i < incomingSessions.length; i++) {
          final s = incomingSessions[i];
          print("  - Session $i: \"${s.query.substring(0, s.query.length > 40 ? 40 : s.query.length)}...\" (summary: ${s.summary?.length ?? 0} chars, sections: ${s.sections?.length ?? 0})");
        }
        print("  - ✅ State updated - UI should rebuild automatically");
      }
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

/// ✅ PERPLEXITY-STYLE: Get session by ID (lazy read, not watch)
/// Use ref.read() inside widgets to avoid rebuilds
final sessionByIdProvider = Provider.family<QuerySession?, String>((ref, sessionId) {
  final sessions = ref.watch(sessionHistoryProvider);
  try {
    return sessions.firstWhere((s) => s.sessionId == sessionId);
  } catch (e) {
    return null;
  }
});


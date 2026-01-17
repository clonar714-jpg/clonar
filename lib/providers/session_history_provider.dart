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
      
      
      if (existingSession.isFinalized && !incomingSession.isFinalized) {
        
        if (kDebugMode) {
          print("🔒 Preventing replacement of finalized session at index $index");
          print("  - Preserving answer content (sections, sources, cards)");
        }
        
        final mergedSession = existingSession.copyWith(
          timestamp: incomingSession.timestamp, 
         
        );
        newState[index] = mergedSession;
      } else {
        
        final mergedSession = existingSession.mergeWith(incomingSession);
        newState[index] = mergedSession;
      }
      
      state = newState;
    }
  }

 
  void updateSessionById(String sessionId, QuerySession updatedSession) {
    final newState = List<QuerySession>.from(state);
    final index = newState.indexWhere((s) => s.sessionId == sessionId);
    
    if (index == -1) {
      if (kDebugMode) {
        print("⚠️ Session not found for update: $sessionId");
        print("  - Available sessions: ${newState.map((s) => s.sessionId).join(', ')}");
      }
      return; 
    }
    
    final existingSession = newState[index];
    
    
    if (existingSession.isFinalized) {
      
      if (updatedSession.isFinalized) {
       
        final mergedSession = existingSession.mergeWith(updatedSession);
        newState[index] = mergedSession;
      } else {
        
        if (kDebugMode) {
          print("🔒 Finalized session - only allowing summary update");
          print("  - Session ID: $sessionId");
          print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
          print("  - Incoming sections: ${updatedSession.sections?.length ?? 0}");
        }
        
        
        final mergedSession = existingSession.copyWith(
          summary: updatedSession.summary, 
          isStreaming: updatedSession.isStreaming,
          
        );
        newState[index] = mergedSession;
      }
    } else {
      
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

 
  void replaceLastSession(QuerySession incomingSession) {
    if (state.isNotEmpty) {
      final newState = List<QuerySession>.from(state);
      final lastIndex = newState.length - 1;
      final existingSession = newState[lastIndex];
      
      
      if (existingSession.isFinalized) {
        
        final wouldClearSections = (existingSession.sections?.length ?? 0) > 0 && 
                                   (incomingSession.sections?.length ?? 0) == 0;
        final wouldClearSources = existingSession.sources.isNotEmpty && 
                                  incomingSession.sources.isEmpty;
        
        if (wouldClearSections || wouldClearSources) {
          
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
          
          
          final mergedSession = existingSession.copyWith(
            timestamp: incomingSession.timestamp, 
            
          );
          newState[lastIndex] = mergedSession;
          state = [...newState];
          return;
        }
        
        
        if (kDebugMode && !incomingSession.isFinalized == false) {
          print("🔒 Merging finalized session with non-finalized incoming");
          print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
          print("  - Incoming sections: ${incomingSession.sections?.length ?? 0}");
        }
      }
      
      
      final mergedSession = existingSession.mergeWith(incomingSession);
      
      
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
      
      
      state = [...newState]; 
      
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
      
      state = [incomingSession];
      if (kDebugMode) {
        print("🔄 SessionHistoryNotifier: Created initial session (defensive)");
        print("  - Session query: ${incomingSession.query}");
        print("  - Session isStreaming: ${incomingSession.isStreaming}");
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

 
  void replaceAllSessions(List<QuerySession> incomingSessions) {
   
    if (state.isNotEmpty && incomingSessions.isNotEmpty) {
      final mergedSessions = <QuerySession>[];
      
      
      for (final incomingSession in incomingSessions) {
        
        final existingIndex = state.indexWhere((s) => s.query == incomingSession.query);
        
        if (existingIndex >= 0) {
          final existingSession = state[existingIndex];
          
          
          if (existingSession.isFinalized) {
            if (kDebugMode) {
              print("🔒 Preserving finalized session: ${existingSession.query}");
              print("  - Existing sections: ${existingSession.sections?.length ?? 0}");
              print("  - Incoming sections: ${incomingSession.sections?.length ?? 0}");
            }
            
            
            final merged = existingSession.copyWith(
              
              timestamp: incomingSession.timestamp, 
              
            );
            mergedSessions.add(merged);
          } else {
            
            mergedSessions.add(incomingSession);
          }
        } else {
          
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


final sessionHistoryProvider =
    StateNotifierProvider<SessionHistoryNotifier, List<QuerySession>>(
  (ref) {
    ref.keepAlive(); 
    return SessionHistoryNotifier();
  },
);


final sessionByIdProvider = Provider.family<QuerySession?, String>((ref, sessionId) {
  final sessions = ref.watch(sessionHistoryProvider);
  try {
    return sessions.firstWhere((s) => s.sessionId == sessionId);
  } catch (e) {
    return null;
  }
});


import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import '../models/query_session_model.dart';
import '../isolates/text_parsing_isolate.dart'; // ✅ FIX 2
import '../services/AgentService.dart';
import '../services/agent_stream_service.dart'; // ✅ NEW: Global SSE service
import 'session_history_provider.dart';
import 'session_stream_provider.dart'; // ✅ PERPLEXITY-STYLE: Stream controller for text chunks

enum AgentState { idle, loading, streaming, completed, error }

/// ✅ PHASE 7: Memoized agent state provider
final agentStateProvider = StateProvider<AgentState>((ref) {
  ref.keepAlive();
  return AgentState.idle;
});

/// ✅ PHASE 7: Memoized agent response provider with select support
final agentResponseProvider =
    StateProvider<Map<String, dynamic>?>((ref) {
  ref.keepAlive();
  return null;
});

class AgentController extends StateNotifier<void> {
  final Ref ref;
  
  // ✅ SSE OWNERSHIP: Track active stream session
  // This ensures we can identify which session owns the current stream
  // The stream itself is consumed via await for, but we track it here
  String? _activeSessionId; // Track which session owns the current stream
  // Note: We don't store StreamSubscription directly because await for creates it implicitly
  // We track via _activeSessionId and can cancel by breaking the loop or handling errors
  
  // ✅ TASK 3: Track processed eventIds per session for idempotency
  // Map<sessionId, Set<eventId>>
  final Map<String, Set<String>> _processedEventIds = {};
  
  AgentController(this.ref) : super(null);
  
  @override
  void dispose() {
    // ✅ CRITICAL: Only clear tracking on explicit controller disposal (app shutdown)
    // Do NOT cancel on widget rebuilds or provider updates
    // The stream will close naturally when the await for loop exits
    print("🛑 AgentController.dispose() called - clearing stream tracking");
    if (_activeSessionId != null) {
      print("⚠️ WARNING: Active stream exists during dispose - Session: $_activeSessionId");
      _activeSessionId = null;
    }
    super.dispose();
  }
  
  /// ✅ EXPLICIT CANCEL: User-initiated query cancellation
  /// Note: This marks the session for cancellation, but the actual stream
  /// cancellation happens when the await for loop checks the flag
  void cancelQuery(String sessionId) {
    if (_activeSessionId == sessionId) {
      print("🛑 User canceled query for session: $sessionId");
      // Clear tracking - the stream will be canceled when loop exits
      _activeSessionId = null;
      // Update session state to show cancellation
      final currentSessions = ref.read(sessionHistoryProvider);
      final currentSession = currentSessions.firstWhere(
        (s) => s.sessionId == sessionId,
        orElse: () => QuerySession(sessionId: sessionId, query: ''),
      );
      final canceledSession = currentSession.copyWith(
        isStreaming: false,
        isParsing: false,
        error: 'Query canceled by user',
      );
      ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, canceledSession);
      ref.read(agentStateProvider.notifier).state = AgentState.error;
    }
  }

  /// ✅ Build conversation history from sessions
  /// Includes all sessions with non-empty query and summary (including streaming sessions)
  /// ✅ CRITICAL FIX: Include streaming sessions so follow-up queries have context
  /// This matches ChatGPT/Perplexity behavior where partial summaries are included
  List<Map<String, dynamic>> _buildConversationHistory() {
    final sessions = ref.read(sessionHistoryProvider);
    final history = <Map<String, dynamic>>[];
    
    for (final session in sessions) {
      // ✅ FIX #1: Include streaming sessions with partial summary
      // This ensures follow-up queries have context even if parent is still streaming
      // Matches ChatGPT/Perplexity behavior
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
    
    return history;
  }

  Future<void> submitQuery(String query, {String? imageUrl, bool useStreaming = true}) async {
    print("🔥🔥🔥🔥🔥 submitQuery CALLED - Query: '$query', useStreaming: $useStreaming, imageUrl: $imageUrl");
    
    // ✅ FIX #1: Prevent duplicate query submissions (check both streaming AND finalized sessions)
    final existingSessions = ref.read(sessionHistoryProvider);
    final trimmedQuery = query.trim();
    final now = DateTime.now();
    
    // ✅ CRITICAL FIX: Check for ANY matching session (streaming, parsing, OR finalized)
    // This prevents duplicate submissions even if the previous session is already completed
    final matchingStreamingSession = existingSessions.firstWhere(
      (s) => s.query.trim() == trimmedQuery && 
             s.imageUrl == imageUrl &&
             (s.isStreaming || s.isParsing),
      orElse: () => QuerySession(sessionId: '', query: ''), // Dummy session if not found
    );
    
    final matchingFinalizedSession = existingSessions.firstWhere(
      (s) => s.query.trim() == trimmedQuery && 
             s.imageUrl == imageUrl &&
             s.isFinalized &&
             s.error == null, // Only block if finalized AND not errored
      orElse: () => QuerySession(sessionId: '', query: ''), // Dummy session if not found
    );
    
    // ✅ SAFE RETRY: Allow retry if session is stuck > 30 seconds OR errored
    if (matchingStreamingSession.query.isNotEmpty) {
      final sessionAge = now.difference(matchingStreamingSession.timestamp);
      final isStuck = sessionAge.inSeconds > 30;
      final canRetry = isStuck || matchingStreamingSession.error != null;
      
      if (!canRetry) {
        print("🔥🔥🔥❌❌❌ SKIPPING DUPLICATE: Query '$trimmedQuery' is already processing");
        print("🔥🔥🔥❌❌❌ Session age: ${sessionAge.inSeconds}s (stuck threshold: 30s)");
        if (kDebugMode) {
          debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already processing)');
        }
        return; // Don't submit duplicate query
      } else {
        print("🔥🔥🔥✅✅✅ ALLOWING RETRY: Session is ${isStuck ? 'stuck' : 'errored'}");
      }
    }
    
    // ✅ CRITICAL FIX: Block duplicate if a finalized (successful) session already exists
    if (matchingFinalizedSession.query.isNotEmpty) {
      print("🔥🔥🔥❌❌❌ SKIPPING DUPLICATE: Query '$trimmedQuery' already completed successfully");
      print("🔥🔥🔥❌❌❌ Finalized session exists with summary length: ${matchingFinalizedSession.summary?.length ?? 0}");
      if (kDebugMode) {
        debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already completed)');
      }
      return; // Don't submit duplicate query - user already has the answer
    }
    
    print("🔥🔥🔥✅✅✅ NOT A DUPLICATE - Proceeding with query submission");
    print("🔥🔥🔥✅✅✅ Existing sessions count: ${existingSessions.length}");
    
    // ✅ CRITICAL: Single source of truth - only sessionHistoryProvider is used
    // Removed streamingTextProvider reset - not needed
    
    ref.read(agentStateProvider.notifier).state = AgentState.loading;

    // ✅ CRITICAL: Generate unique sessionId for this query
    final sessionId = QuerySession.generateSessionId();
    print("🔥🔥🔥✅✅✅ Generated sessionId: $sessionId");

    // ✅ PERPLEXITY-STYLE: Create initial session with loading state reset
    // Reset all state on query submission (token-aware loading)
    final initialSession = QuerySession(
      sessionId: sessionId, // ✅ CRITICAL: Unique ID for this session
      query: query,
      isStreaming: true, // ✅ Loading starts immediately on submit
      isParsing: false,
      hasReceivedFirstChunk: false, // ✅ PERPLEXITY-STYLE: Reset to false - loading shows until first chunk
      answer: null, // ✅ Clear previous answer
      summary: null, // ✅ Clear previous summary
      sections: null, // ✅ Clear previous sections
      sources: const [], // ✅ Clear previous sources
      imageUrl: imageUrl,
    );
    
    // Add to session history
    ref.read(sessionHistoryProvider.notifier).addSession(initialSession);

    // ✅ Build conversation history from completed sessions
    final conversationHistory = _buildConversationHistory();
    
    // ✅ Debug logging
    if (kDebugMode) {
      debugPrint('📚 Conversation history size: ${conversationHistory.length}');
      if (conversationHistory.isEmpty) {
        final allSessions = ref.read(sessionHistoryProvider);
        if (allSessions.length > 1) {
          debugPrint('⚠️ WARNING: Submitting query with empty conversation history but ${allSessions.length} sessions exist');
          debugPrint('   This may indicate sessions are not completed (isStreaming: ${allSessions.any((s) => s.isStreaming)}, isParsing: ${allSessions.any((s) => s.isParsing)})');
        }
      } else {
        debugPrint('✅ Sending conversation history with ${conversationHistory.length} completed session(s)');
      }
    }

    print("🔥🔥🔥✅✅✅ submitQuery ENTRY - Query: '$query', useStreaming: $useStreaming");
    print("🔥🔥🔥✅✅✅ Conversation history length: ${conversationHistory.length}");
    
    try {
      // ✅ TASK 4: Support streaming responses (opt-in via useStreaming flag)
      print("🔥🔥🔥✅✅✅ submitQuery: useStreaming=$useStreaming");
      if (useStreaming) {
        print("🔥🔥🔥✅✅✅ CALLING _handleStreamingResponse...");
        print("🔥🔥🔥✅✅✅ Query: '$query'");
        print("🔥🔥🔥✅✅✅ ImageUrl: $imageUrl");
        print("🔥🔥🔥✅✅✅ Initial session query: '${initialSession.query}'");
        try {
          await _handleStreamingResponse(query, imageUrl, initialSession, conversationHistory);
        } catch (streamError, streamStackTrace) {
          if (kDebugMode) {
            debugPrint('❌ Stream error: $streamError');
          }
          print("🔥🔥🔥❌❌❌ ERROR TYPE: ${streamError.runtimeType}");
          print("🔥🔥🔥❌❌❌ STACK: $streamStackTrace");
          rethrow;
        }
        return;
      }
      
      // ✅ Non-streaming: Use AgentService.askAgent() to ensure conversationHistory is sent
      print("🔥 ABOUT TO CALL AgentService.askAgent for query: '$query'");
      final responseData = await AgentService.askAgent(
        query,
        stream: false, // Explicitly false when useStreaming is false
        conversationHistory: conversationHistory,
        imageUrl: imageUrl,
      );
      
      print("🔥 AgentService.askAgent returned - responseData keys: ${responseData.keys.join(', ')}");
      print("🔥 ResponseData success: ${responseData['success']}");
      print("🔥 ResponseData has summary: ${responseData.containsKey('summary')}");
      print("🔥 ResponseData has cards: ${responseData.containsKey('cards')} (type: ${responseData['cards'].runtimeType})");
      
      // Update agent response provider
      ref.read(agentResponseProvider.notifier).state = responseData;
      
      print("🔥 Agent response provider updated, starting extraction...");
      
      if (kDebugMode) {
        debugPrint('✅ Received response from backend, processing...');
        debugPrint('  - Response keys: ${responseData.keys.join(", ")}');
      }

      // Extract fields from response (already parsed by AgentService)
      final summary = responseData['summary']?.toString();
      final answer = responseData['answer']?.toString() ?? summary; // ✅ CRITICAL: Extract full answer, fallback to summary
      final intent = responseData['intent']?.toString();
      final cardType = responseData['cardType']?.toString();
      
      // ✅ WIDGET SYSTEM: Extract widgets from response and convert to cardsByDomain format
      Map<String, dynamic>? cardsByDomain;
      List<Map<String, dynamic>> cards = []; // ✅ DEPRECATED: Keep for backward compatibility
      
      // ✅ NEW: Read widgets from response
      if (responseData['widgets'] != null && responseData['widgets'] is List) {
        final widgets = (responseData['widgets'] as List).cast<Map<String, dynamic>>();
        
        // Convert widgets to cardsByDomain format
        final cardsByDomainMap = <String, dynamic>{
          'products': <Map<String, dynamic>>[],
          'hotels': <Map<String, dynamic>>[],
          'places': <Map<String, dynamic>>[],
          'movies': <Map<String, dynamic>>[],
        };
        
        final allCards = <Map<String, dynamic>>[];
        
        for (final widget in widgets) {
          final widgetType = widget['type']?.toString();
          final widgetData = widget['data'];
          final success = widget['success'] == true;
          
          if (!success || widgetData == null) continue;
          
          // Widget data is already in card format (ProductCard[], HotelCard[], etc.)
          if (widgetData is List) {
            final cardList = widgetData
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            
            switch (widgetType) {
              case 'product':
                (cardsByDomainMap['products'] as List).addAll(cardList);
                allCards.addAll(cardList);
                break;
              case 'hotel':
                (cardsByDomainMap['hotels'] as List).addAll(cardList);
                allCards.addAll(cardList);
                break;
              case 'place':
                (cardsByDomainMap['places'] as List).addAll(cardList);
                allCards.addAll(cardList);
                break;
              case 'movie':
                (cardsByDomainMap['movies'] as List).addAll(cardList);
                allCards.addAll(cardList);
                break;
            }
          }
        }
        
        cardsByDomain = cardsByDomainMap;
        cards = allCards; // For backward compatibility with UI
      }
      
      // ✅ PERPLEXITY-STYLE: Extract UI requirements
      Map<String, dynamic>? uiRequirements;
      if (responseData['uiRequirements'] != null && responseData['uiRequirements'] is Map) {
        uiRequirements = Map<String, dynamic>.from(responseData['uiRequirements']);
      }
      
      final results = responseData['results'] ?? [];
      
      // ✅ FIX: Extract sections with proper type checking (avoid type cast error)
      List<Map<String, dynamic>> sections = [];
      if (responseData['sections'] != null) {
        if (responseData['sections'] is List) {
          sections = (responseData['sections'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
      }
      
      // ✅ FIX: Extract mapPoints with proper type checking
      List<Map<String, dynamic>> mapPoints = [];
      if (responseData['map'] != null) {
        if (responseData['map'] is List) {
          mapPoints = (responseData['map'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
      }
      
      // ✅ FIX: Extract destinationImages with proper type checking
      List<String> destinationImages = [];
      if (responseData['destination_images'] != null) {
        if (responseData['destination_images'] is List) {
          destinationImages = (responseData['destination_images'] as List).map((e) => e.toString()).toList();
        }
      }
      
      // ✅ NEW: Extract videos with proper type checking
      List<Map<String, dynamic>> videos = [];
      if (responseData['videos'] != null) {
        if (responseData['videos'] is List) {
          videos = (responseData['videos'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
      }
      
      // ✅ FIX: Extract locationCards with proper type checking
      List<Map<String, dynamic>> locationCards = [];
      if (responseData['locationCards'] != null) {
        if (responseData['locationCards'] is List) {
          locationCards = (responseData['locationCards'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
      }
      
      // ✅ FIX: Extract sources with proper type checking (avoid type cast error)
      List<Map<String, dynamic>> sources = [];
      if (responseData['sources'] != null) {
        if (responseData['sources'] is List) {
          sources = (responseData['sources'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
      }
      
      // ✅ FIX: Extract followUpSuggestions with proper type checking
      List<String> followUpSuggestions = [];
      if (responseData['followUpSuggestions'] != null) {
        if (responseData['followUpSuggestions'] is List) {
          followUpSuggestions = (responseData['followUpSuggestions'] as List).map((e) => e.toString()).toList();
        }
      } else if (responseData['followUps'] != null) {
        if (responseData['followUps'] is List) {
          followUpSuggestions = (responseData['followUps'] as List).map((e) => e.toString()).toList();
        }
      }
      
      // ✅ FIX: Log extraction with print() for visibility
      print("🔥 EXTRACTED FROM RESPONSE:");
      print("  - Summary: ${summary != null && summary.isNotEmpty ? 'YES (${summary.length} chars)' : 'NO'}");
      print("  - Intent: $intent");
      print("  - Sections: ${sections.length} items (CRITICAL - should be 3+)");
      print("  - Sources: ${sources.length} items (CRITICAL - should be 9+)");
      print("  - FollowUpSuggestions: ${followUpSuggestions.length} items");
      if (cardsByDomain != null) {
        print("  - CardsByDomain: ${cardsByDomain.keys.join(', ')}");
        if (cardsByDomain['products'] is List) print("    - Products: ${(cardsByDomain['products'] as List).length}");
        if (cardsByDomain['hotels'] is List) print("    - Hotels: ${(cardsByDomain['hotels'] as List).length}");
        if (cardsByDomain['places'] is List) print("    - Places: ${(cardsByDomain['places'] as List).length}");
        if (cardsByDomain['movies'] is List) print("    - Movies: ${(cardsByDomain['movies'] as List).length}");
      }
      if (uiRequirements != null) {
        print("  - UIRequirements: ${uiRequirements.toString()}");
      }
      if (sections.isNotEmpty) {
        print("  - First section title: ${sections[0]['title']}");
        print("  - First section content length: ${(sections[0]['content']?.toString() ?? '').length}");
      }
      
      if (kDebugMode) {
        debugPrint('📦 Agent Response Data:');
        debugPrint('  - Intent: $intent');
        debugPrint('  - CardType: $cardType');
        debugPrint('  - Cards count: ${cards.length}');
        debugPrint('  - Sections count: ${sections.length}');
        debugPrint('  - Map points count: ${mapPoints.length}');
        debugPrint('  - LocationCards count: ${locationCards.length}');
        debugPrint('  - Results count: ${results is List ? results.length : 'N/A'}');
        debugPrint('  - DestinationImages count: ${destinationImages.length}');
        debugPrint('  - Sources count: ${sources.length}');
        debugPrint('  - FollowUpSuggestions count: ${followUpSuggestions.length}');
      }

      // ✅ CRITICAL: Single source of truth - summary is already in session
      // No need to update streamingTextProvider

      // ✅ FIX 2: Parse text with locations ONCE in isolate (cache result)
      List<Map<String, dynamic>>? parsedSegments;
      if (summary != null && summary.isNotEmpty && locationCards.isNotEmpty) {
        try {
          parsedSegments = await compute(_parseTextWithLocationsWrapper, {
            'text': summary,
            'locationCards': locationCards,
          });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Error parsing text with locations: $e');
          }
        }
      }

      // ✅ TASK 3: Move image aggregation to isolate to prevent UI blocking
      // Extract cards from widgets for image aggregation
      final cardsForImages = <Map<String, dynamic>>[];
      if (cardsByDomain != null) {
        if (cardsByDomain['products'] is List) {
          cardsForImages.addAll((cardsByDomain['products'] as List).cast<Map<String, dynamic>>());
        }
        if (cardsByDomain['hotels'] is List) {
          cardsForImages.addAll((cardsByDomain['hotels'] as List).cast<Map<String, dynamic>>());
        }
        if (cardsByDomain['places'] is List) {
          cardsForImages.addAll((cardsByDomain['places'] as List).cast<Map<String, dynamic>>());
        }
        if (cardsByDomain['movies'] is List) {
          cardsForImages.addAll((cardsByDomain['movies'] as List).cast<Map<String, dynamic>>());
        }
      }
      
      final allImages = await compute(_aggregateImagesWrapper, {
        'destinationImages': destinationImages,
        'cards': cardsForImages.isNotEmpty ? cardsForImages : cards,
        'results': results,
      });

      // Update session with response data
      // ✅ PERPLEXITY-STYLE: Non-streaming responses are also finalized (complete answer received)
      final updatedSession = initialSession.copyWith(
        summary: summary,
        answer: answer, // ✅ CRITICAL: Store full answer text
        intent: intent,
        cardType: cardType,
        cards: cards, // ✅ DEPRECATED: Keep for backward compatibility
        cardsByDomain: cardsByDomain, // ✅ NEW: Structured cards by domain
        uiRequirements: uiRequirements, // ✅ NEW: UI requirements from backend
        results: results,
        sections: sections, // ✅ FIX: Extract sections for hotels
        mapPoints: mapPoints, // ✅ FIX: Extract map points for hotels
        destinationImages: destinationImages,
        videos: videos.isNotEmpty ? videos : null, // ✅ NEW: Videos from search results
        locationCards: locationCards,
        sources: sources, // ✅ FIX: Extract sources
        followUpSuggestions: followUpSuggestions, // ✅ FIX: Extract follow-up suggestions
        isStreaming: false, // ✅ CRITICAL: Must be false to clear loading
        isParsing: false, // ✅ CRITICAL: Must be false to clear loading
        isFinalized: true, // ✅ PERPLEXITY-STYLE: Mark as finalized - prevents DB from overwriting answer content
        parsedSegments: parsedSegments, // ✅ FIX 2: Cached parsed segments
        allImages: allImages, // ✅ FIX 3: Pre-aggregated images
      );
      
      // ✅ FIX: Verify updated session has data
      print("🔥 UPDATED SESSION CREATED:");
      print("  - Query: ${updatedSession.query}");
      print("  - isStreaming: ${updatedSession.isStreaming} (MUST be false)");
      print("  - isParsing: ${updatedSession.isParsing} (MUST be false)");
      print("  - Summary: ${updatedSession.summary != null && updatedSession.summary!.isNotEmpty ? 'YES' : 'NO'}");
      print("  - Cards: ${updatedSession.cards.length}");
      print("  - LocationCards: ${updatedSession.locationCards.length}");
      print("  - Results: ${updatedSession.results.length}");
      print("  - Sections: ${updatedSession.sections?.length ?? 0}");
      print("  - Sources: ${updatedSession.sources.length}");
      if (updatedSession.sources.isNotEmpty) {
        print("  - First source title: ${updatedSession.sources[0]['title'] ?? 'N/A'}");
        print("  - First source link: ${updatedSession.sources[0]['link'] ?? updatedSession.sources[0]['url'] ?? 'N/A'}");
      }

      // ✅ REMOVED: Old hotel-specific logging - no longer needed
      // All queries now use sections directly, no hotel/learn distinction

      // ✅ FIX 3: Force UI state update - explicitly replace session to trigger rebuild
      print("🔥 ABOUT TO UPDATE SESSION IN PROVIDER");
      print("  - Updated session isStreaming: ${updatedSession.isStreaming}");
      print("  - Updated session isParsing: ${updatedSession.isParsing}");
      print("  - Updated session cards: ${updatedSession.cards.length}");
      print("  - Updated session summary: ${updatedSession.summary != null && updatedSession.summary!.isNotEmpty}");
      
      ref.read(sessionHistoryProvider.notifier).updateSessionById(initialSession.sessionId, updatedSession);
      
      // ✅ FIX 3: Force state update by reading provider again (ensures Riverpod sees the change)
      // Wait a tiny bit to ensure state propagation
      await Future.delayed(const Duration(milliseconds: 50));
      
      final verifySessions = ref.read(sessionHistoryProvider);
      print("🔥 SESSION UPDATED - Provider now has ${verifySessions.length} session(s)");
      if (verifySessions.isNotEmpty) {
        final lastSession = verifySessions.last;
        print("🔥 LAST SESSION DATA (AFTER UPDATE):");
        print("  - Query: ${lastSession.query}");
        print("  - Intent: ${lastSession.intent}");
        print("  - isStreaming: ${lastSession.isStreaming} (CRITICAL: must be false)");
        print("  - isParsing: ${lastSession.isParsing} (CRITICAL: must be false)");
        print("  - Has summary: ${lastSession.summary != null && lastSession.summary!.isNotEmpty}");
        print("  - Sections count: ${lastSession.sections?.length ?? 0}");
        // ✅ REMOVED: Misleading "HotelSections count" log - sections are generic, not hotel-specific
        print("  - Sources count: ${lastSession.sources.length}");
        print("  - FollowUpSuggestions count: ${lastSession.followUpSuggestions.length}");
        if (lastSession.sections != null && lastSession.sections!.isNotEmpty) {
          print("  - First section title: ${lastSession.sections![0]['title']}");
          print("  - First section has content: ${lastSession.sections![0]['content'] != null && (lastSession.sections![0]['content']?.toString() ?? '').isNotEmpty}");
          print("  - All section titles: ${lastSession.sections!.map((s) => s['title']).join(', ')}");
        }
        
        // ✅ SIMPLIFIED: Only check for summary and sections
        final hasAnyData = (lastSession.summary != null && lastSession.summary!.isNotEmpty) ||
                           (lastSession.sections != null && lastSession.sections!.isNotEmpty);
        print("  - HAS ANY DATA: $hasAnyData");
        print("  - SHOULD SHOW CONTENT: ${!lastSession.isStreaming && !lastSession.isParsing && hasAnyData}");
      }
      
      if (kDebugMode) {
        debugPrint('✅ Session updated in provider - UI should rebuild now');
      }

      // ✅ FIX 3: Update state to completed (force state change)
      ref.read(agentStateProvider.notifier).state = AgentState.completed;
      
      print("🔥 Agent state set to completed - UI should rebuild now");

      // ✅ FIX: Removed auto-scroll to bottom - user should see query at top and swipe up to see results

      if (kDebugMode) {
        debugPrint('✅ Agent query completed: $query');
      }
    } catch (e, stackTrace) {
      // ✅ CRITICAL: Log ALL errors with print() to see what's failing
      print("❌❌❌ EXCEPTION IN submitQuery:");
      print("  - Error: $e");
      print("  - Error type: ${e.runtimeType}");
      print("  - Stack trace: $stackTrace");
      
      // ✅ FIX: Detect connection errors and provide helpful message
      String errorMessage = 'An error occurred while processing your request.';
      if (e.toString().contains('Connection refused') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        errorMessage = 'Unable to connect to the server. Please make sure:\n\n'
            '1. The backend server is running on port 4000\n'
            '2. Your device and computer are on the same network\n'
            '3. Try: http://127.0.0.1:4000/api/test in your browser';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. The server may be taking too long to respond.';
      }
      
      // Update session with error state
      final errorSession = initialSession.copyWith(
        isStreaming: false,
        isParsing: false,
        error: errorMessage, // ✅ NEW: Set error message
        summary: errorMessage, // ✅ Also set as summary so UI shows it
      );
      ref.read(sessionHistoryProvider.notifier).updateSessionById(initialSession.sessionId, errorSession);
      
      ref.read(agentStateProvider.notifier).state = AgentState.error;
      
      if (kDebugMode) {
        debugPrint('❌ Agent query error: $e');
        debugPrint('❌ Stack trace: $stackTrace');
      }
    }
  }

  Future<void> submitFollowUp(String followUpQuery, String parentQuery) async {
    await submitQuery(followUpQuery);
  }

  // ✅ TASK 4: Handle streaming SSE response with partial updates
  Future<void> _handleStreamingResponse(String query, String? imageUrl, QuerySession initialSession, List<Map<String, dynamic>> conversationHistory) async {
    print("🔥🔥🔥 _handleStreamingResponse CALLED");
    print("🔥🔥🔥 Query: $query");
    print("🔥🔥🔥 SessionId: ${initialSession.sessionId}"); // ✅ CRITICAL: Log sessionId
    print("🔥🔥🔥 Conversation history length: ${conversationHistory.length}");
    
    // ✅ CRITICAL: Extract sessionId for ID-based updates
    final sessionId = initialSession.sessionId;
    
    try {
      // ✅ NEW FORMAT: Build request body in new format
      // Generate chatId and messageId
      final generatedChatId = _generateChatId();
      final generatedMessageId = _generateMessageId();
      
      // Convert conversationHistory to history format
      final history = _convertConversationHistoryToHistory(conversationHistory);
      
      final requestBody = <String, dynamic>{
        "message": {
          "messageId": generatedMessageId,
          "chatId": generatedChatId,
          "content": query,
        },
        "chatId": generatedChatId,
        "chatModel": {
          "providerId": "openai",
          "key": "gpt-4o-mini",
        },
        "embeddingModel": {
          "providerId": "openai",
          "key": "text-embedding-3-small",
        },
        "history": history,
        "sources": ["web"],
        "optimizationMode": "balanced",
        "systemInstructions": "",
      };
      
      // Legacy fields for reference
      requestBody["query"] = query;
      requestBody["conversationHistory"] = conversationHistory;
      
      if (imageUrl != null) {
        requestBody["imageUrl"] = imageUrl;
      }
      
      print("🔥🔥🔥 SENDING STREAMING REQUEST...");
      print("🔥🔥🔥 Request body: $requestBody");
      print("🔥🔥🔥 Endpoint: /chat?stream=true");
      
      // ✅ CRITICAL: Use global singleton SSE service (survives widget rebuilds)
      // This uses the SINGLE HttpClient created at app startup
      final streamService = AgentStreamService();
      
      Stream<String> stream;
      try {
        print("🔥🔥🔥 ABOUT TO CALL AgentStreamService.postStream...");
        print("🔥🔥🔥 Using SINGLE HttpClient instance (survives rebuilds)");
        stream = await streamService.postStream(
          "/chat?stream=true",
          requestBody,
          sessionId: sessionId,
        );
        print("🔥🔥🔥 STREAM RECEIVED FROM AgentStreamService");
        print("🔥🔥🔥 STREAM TYPE: ${stream.runtimeType}");
      } on TimeoutException catch (e, stackTrace) {
        print("🔥🔥🔥❌❌❌ TIMEOUT ERROR: $e");
        print("🔥🔥🔥❌❌❌ The server did not respond within timeout");
        print("🔥🔥🔥❌❌❌ This usually means:");
        print("🔥🔥🔥❌❌❌   1. Server is not running or not accessible");
        print("🔥🔥🔥❌❌❌   2. Server is taking too long to initialize SSE headers");
        print("🔥🔥🔥❌❌❌   3. Network connectivity issue");
        print("🔥🔥🔥❌❌❌ STACK: $stackTrace");
        
        // ✅ FIX #2: Update session with error state (not completed)
        final errorMessage = "Connection timeout. Please check:\n1. Server is running\n2. Network connection\n3. Try again";
        final errorSession = initialSession.copyWith(
          summary: errorMessage,
          isStreaming: false,
          isParsing: false,
          error: "Connection timeout", // ✅ CRITICAL: Set error field for retry logic
        );
        ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, errorSession);
        ref.read(agentStateProvider.notifier).state = AgentState.error; // ✅ CRITICAL: Set error state (not completed)
        return; // Exit early
      } catch (e, stackTrace) {
        print("🔥🔥🔥❌❌❌ ERROR GETTING STREAMING RESPONSE: $e");
        print("🔥🔥🔥❌❌❌ ERROR TYPE: ${e.runtimeType}");
        print("🔥🔥🔥❌❌❌ STACK: $stackTrace");
        
        // Update session with error state
        final errorSession = initialSession.copyWith(
          summary: "Error connecting to server: ${e.toString()}",
          isStreaming: false,
          isParsing: false,
        );
        ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, errorSession);
        ref.read(agentStateProvider.notifier).state = AgentState.completed;
        return; // Exit early instead of rethrowing
      }
      
      // ✅ SSE OWNERSHIP: Cancel any existing stream first (shouldn't happen, but safety check)
      if (_activeSessionId != null) {
        print("⚠️ WARNING: Active stream exists for session: $_activeSessionId, starting new stream");
        _activeSessionId = null; // Clear old tracking
      }
      
      // ✅ CRITICAL: Mark this session as the active one BEFORE consuming stream
      // This ensures we can identify which session owns the stream, even during widget rebuilds
      _activeSessionId = sessionId;
      
      // ✅ TASK 3: Initialize processed eventIds set for this session
      _processedEventIds[sessionId] = <String>{};
      
      String buffer = '';
      String accumulatedText = ''; // ✅ FIX: Accumulate streaming text in real-time
      
      // ✅ CRITICAL: Wrap in try-catch to handle stream errors gracefully
      // The stream subscription is implicitly created by await for, but we track it via _activeSessionId
      try {
        await for (var chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        
        // Keep last incomplete line in buffer
        if (lines.isNotEmpty) {
          buffer = lines.removeLast();
        } else {
          buffer = '';
        }

        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty) continue;
          
          // ✅ FIX: Skip SSE comment lines (heartbeat keep-alive messages)
          if (line.startsWith(':')) {
            continue; // Skip heartbeat/comment lines
          }
          
          // ✅ FIX: Handle JSON response (non-SSE) - backend might return JSON instead of SSE
          if (!line.startsWith('data: ')) {
            // Try to parse as complete JSON response
            try {
              final jsonData = jsonDecode(line) as Map<String, dynamic>;
              
              // Process as if it's an end event with all data
              final finalSummary = jsonData['summary']?.toString() ?? accumulatedText;
              final finalAnswer = jsonData['answer']?.toString() ?? finalSummary; // ✅ CRITICAL: Extract full answer
              final sections = jsonData['sections'] as List<dynamic>? ?? [];
              final sources = jsonData['sources'] as List<dynamic>? ?? [];
              final followUpSuggestions = jsonData['followUpSuggestions'] as List<dynamic>? ?? [];
              final cardsByDomain = jsonData['cards'] as Map<String, dynamic>?;
              final destinationImages = (jsonData['destination_images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              
              // ✅ PERPLEXITY-STYLE: Non-SSE JSON response is also finalized (complete answer)
              final completeSession = initialSession.copyWith(
                summary: finalSummary,
                answer: finalAnswer, // ✅ CRITICAL: Store full answer text
                sections: sections.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                sources: sources.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                followUpSuggestions: followUpSuggestions.map((f) => f.toString()).toList(),
                cardsByDomain: cardsByDomain != null ? Map<String, dynamic>.from(cardsByDomain) : null,
                destinationImages: destinationImages,
                isStreaming: false,
                isParsing: false,
                isFinalized: true, // ✅ PERPLEXITY-STYLE: Mark as finalized - prevents DB from overwriting
              );
              
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, completeSession);
              ref.read(agentStateProvider.notifier).state = AgentState.completed;
              
              return; // Exit early since we got complete response
            } catch (e) {
              if (kDebugMode) {
                debugPrint('⚠️ Failed to parse non-SSE line as JSON: $e');
              }
              continue; // Skip this line
            }
          }

          try {
            final jsonStr = line.substring(6); // Remove "data: " prefix
            if (jsonStr.trim() == '[DONE]') {
              continue;
            }
            
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type'] as String?;
            
            // ✅ TASK 3: Extract eventId and sessionId for idempotency
            final eventId = data['eventId'] as String?;
            final eventSessionId = data['sessionId'] as String?;
            
            // ✅ TASK 3: Deduplicate events - ignore if already processed
            if (eventId != null) {
              // For updateBlock events, use (sessionId + blockId + eventId) as unique key
              String dedupeKey = eventId;
              if (type == 'updateBlock') {
                final blockId = data['blockId'] as String?;
                if (blockId != null) {
                  dedupeKey = '${eventSessionId ?? sessionId}_${blockId}_$eventId';
                }
              } else {
                // For other events, use (sessionId + eventId)
                dedupeKey = '${eventSessionId ?? sessionId}_$eventId';
              }
              
              final processedIds = _processedEventIds[sessionId] ?? <String>{};
              if (processedIds.contains(dedupeKey)) {
                if (kDebugMode) {
                  debugPrint('⚠️ Duplicate event ignored: eventId=$eventId, type=$type, sessionId=$eventSessionId');
                }
                continue; // ✅ CRITICAL: Skip duplicate event BEFORE mutating state
              }
              
              // Mark as processed
              processedIds.add(dedupeKey);
              _processedEventIds[sessionId] = processedIds;
            }

            // ✅ NEW: Handle block-based events from new backend
            if (type == 'block') {
              final block = data['block'] as Map<String, dynamic>?;
              if (block != null) {
                final blockType = block['type'] as String?;
                final blockData = block['data'];
                
                // ✅ ENHANCEMENT 1: Process reasoning blocks (text blocks starting with 💭)
                if (blockType == 'text' && blockData is String) {
                  final textContent = blockData as String;
                  
                  // Check if this is a reasoning block (starts with 💭)
                  if (textContent.startsWith('💭')) {
                    // Extract reasoning text (remove emoji prefix)
                    final reasoningText = textContent.substring(1).trim();
                    
                    // Get current session
                    final currentSessions = ref.read(sessionHistoryProvider);
                    final currentSession = currentSessions.firstWhere(
                      (s) => s.sessionId == sessionId,
                      orElse: () => initialSession,
                    );
                    
                    // Append reasoning step (don't replace, accumulate)
                    final updatedReasoningSteps = [
                      ...currentSession.reasoningSteps,
                      reasoningText,
                    ];
                    
                    // ✅ FIX: Ensure session is marked as streaming so UI shows reasoning immediately
                    // Reasoning appears during research phase (before answer), so we need to show it right away
                    final partialSession = currentSession.copyWith(
                      reasoningSteps: updatedReasoningSteps,
                      isStreaming: true, // ✅ Ensure streaming is true so UI shows reasoning
                      isFinalized: false,
                    );
                    
                    // ✅ CRITICAL: Force immediate UI update for reasoning
                    ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                    
                    // ✅ DEBUG: Log reasoning processing
                    if (kDebugMode) {
                      debugPrint('💭 Reasoning block processed: "$reasoningText"');
                      debugPrint('💭 Total reasoning steps: ${updatedReasoningSteps.length}');
                      debugPrint('💭 Session ID: $sessionId');
                      debugPrint('💭 isStreaming: ${partialSession.isStreaming}');
                    }
                    
                    print('💭💭💭 REASONING BLOCK RECEIVED AND PROCESSED 💭💭💭');
                    print('💭 Reasoning text: "$reasoningText"');
                    print('💭 Session ID: $sessionId');
                    print('💭 Total steps: ${updatedReasoningSteps.length}');
                  } else {
                    // Regular text block - accumulate the text
                    accumulatedText = textContent;
                    
                    // ✅ CRITICAL: Single source of truth - only update session
                    // Update session with accumulated text
                    final currentSessions = ref.read(sessionHistoryProvider);
                    final currentSession = currentSessions.firstWhere(
                      (s) => s.sessionId == sessionId,
                      orElse: () => initialSession,
                    );
                    
                    // ✅ PERPLEXITY-STYLE: Mark first chunk as received (token-aware loading)
                    final partialSession = currentSession.copyWith(
                      summary: accumulatedText,
                      isStreaming: true,
                      isFinalized: false,
                      hasReceivedFirstChunk: true, // ✅ First content chunk arrived
                    );
                    ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                  }
                }
                
                // ✅ ENHANCEMENT 2: Process source blocks in real-time
                if (blockType == 'source' && blockData is List) {
                  // Extract sources from block
                  final newSources = (blockData as List<dynamic>)
                      .map((s) => Map<String, dynamic>.from(s as Map<String, dynamic>))
                      .toList();
                  
                  // Get current session
                  final currentSessions = ref.read(sessionHistoryProvider);
                  final currentSession = currentSessions.firstWhere(
                    (s) => s.sessionId == sessionId,
                    orElse: () => initialSession,
                  );
                  
                  // Merge sources (deduplicate by URL)
                  final existingUrls = currentSession.sources
                      .map((s) => (s['url'] ?? s['link'] ?? '').toString())
                      .toSet();
                  
                  final uniqueNewSources = newSources.where((s) {
                    final url = (s['url'] ?? s['link'] ?? '').toString();
                    return url.isNotEmpty && !existingUrls.contains(url);
                  }).toList();
                  
                  if (uniqueNewSources.isNotEmpty) {
                    final updatedSources = [
                      ...currentSession.sources,
                      ...uniqueNewSources,
                    ];
                    
                    final partialSession = currentSession.copyWith(
                      sources: updatedSources,
                      isStreaming: true,
                      isFinalized: false,
                    );
                    ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                  }
                }
              }
              continue; // Processed block event
            } else if (type == 'section') {
              // ✅ PERPLEXITY-STYLE: Handle section events (explanation section)
              final sectionData = data['section'] as Map<String, dynamic>?;
              if (sectionData != null) {
                final currentSessions = ref.read(sessionHistoryProvider);
                final currentSession = currentSessions.firstWhere(
                  (s) => s.sessionId == sessionId,
                  orElse: () => initialSession,
                );
                
                // Add section to session
                final existingSections = currentSession.sections ?? [];
                final newSection = Map<String, dynamic>.from(sectionData);
                
                // Check if section already exists (by title) to avoid duplicates
                final sectionExists = existingSections.any(
                  (s) => s['title'] == newSection['title'],
                );
                
                if (!sectionExists) {
                  final updatedSections = [
                    ...existingSections,
                    newSection,
                  ];
                  
                  final partialSession = currentSession.copyWith(
                    sections: updatedSections,
                    isStreaming: true,
                    isFinalized: false,
                  );
                  ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                  
                  if (kDebugMode) {
                    debugPrint('📋 Received section: ${newSection['title']}');
                    debugPrint('  - Sections count: ${updatedSections.length}');
                  }
                }
              }
              continue; // Processed section event
            } else if (type == 'updateBlock') {
              // Update block event - update existing block
              // ✅ FIX: Backend sends 'patch' not 'operations'
              final patch = data['patch'] as List<dynamic>?;
              
              // Apply patch operations to update accumulated text
              if (patch != null && patch.isNotEmpty) {
                for (final op in patch) {
                  if (op is Map && op['op'] == 'replace' && op['path'] == '/data') {
                    final newValue = op['value'];
                    if (newValue is String && newValue.isNotEmpty) {
                      // ✅ PERPLEXITY-STYLE: Calculate delta (new text - old text)
                      final oldLength = accumulatedText.length;
                      accumulatedText = newValue; // ✅ This is the FULL updated text, not a delta
                      final delta = accumulatedText.substring(oldLength); // Extract new chunk
                      
                      // ✅ PERPLEXITY-STYLE: First token transitions phase and initializes stream
                      final currentSessions = ref.read(sessionHistoryProvider);
                      final currentSession = currentSessions.firstWhere(
                        (s) => s.sessionId == sessionId,
                        orElse: () => initialSession,
                      );
                      
                      if (currentSession.phase == QueryPhase.searching) {
                        // Initialize stream controller
                        ref.read(sessionStreamProvider.notifier).initialize(sessionId);
                        
                        // ✅ ONE-TIME TRANSITION: searching → answering
                        final transitionedSession = currentSession.copyWith(
                          phase: QueryPhase.answering, // ← Phase transition
                          isStreaming: true,
                          isFinalized: false,
                          hasReceivedFirstChunk: true,
                        );
                        ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, transitionedSession);
                        
                        if (kDebugMode) {
                          debugPrint('🔄 Phase transition: searching → answering (first updateBlock)');
                        }
                      }
                      
                      // ✅ PERPLEXITY-STYLE: Push delta to stream (NO session update)
                      if (delta.isNotEmpty) {
                        ref.read(sessionStreamProvider.notifier).addChunk(delta);
                      }
                    } else if (kDebugMode) {
                      debugPrint('⚠️ updateBlock: value is not a string or is empty');
                    }
                  }
                }
              } else if (kDebugMode) {
                debugPrint('⚠️ updateBlock: event has no patch array or patch is empty');
              }
              continue; // Processed updateBlock event
            } else if (type == 'researchProgress') {
              // ✅ ENHANCEMENT 3: Process research progress events
              final progressData = data;
              final step = progressData['researchStep'] as int?;
              final maxSteps = progressData['maxResearchSteps'] as int?;
              final currentAction = progressData['currentAction'] as String?;
              
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              final partialSession = currentSession.copyWith(
                researchStep: step,
                maxResearchSteps: maxSteps,
                currentAction: currentAction,
                isStreaming: true,
                isFinalized: false,
              );
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
              
              continue; // Processed researchProgress event
            } else if (type == 'researchComplete') {
              // ✅ ENHANCEMENT 3: Research complete - clear progress indicators
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              // Clear progress when research completes (answer generation starts)
              final partialSession = currentSession.copyWith(
                researchStep: null,
                maxResearchSteps: null,
                currentAction: null,
                isStreaming: true,
                isFinalized: false,
              );
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
              
              continue; // Processed researchComplete event
            } else if (type == 'start') {
              // Start event - no action needed
              continue; // Processed start event
            }

            // ✅ FIX: Handle real-time streaming events from backend (legacy format)
            if (type == 'verdict') {
              // ✅ PERPLEXITY-STYLE: Verdict events are streaming - only update summary
              // ✅ CRITICAL: Get session by ID (not by position)
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              if (currentSession.isFinalized) {
                if (kDebugMode) {
                  debugPrint('⚠️ Ignoring verdict event - session is finalized');
                }
                continue;
              }
              
              // First sentence - display immediately
              final firstSentence = data['data']?.toString() ?? '';
              if (firstSentence.isNotEmpty) {
                accumulatedText = firstSentence;
                
                // ✅ CRITICAL: Single source of truth - only update session
                // ✅ PERPLEXITY-STYLE: ONLY update summary, NEVER touch structured data
                final partialSession = currentSession.copyWith(
                  summary: accumulatedText, // ✅ ONLY summary - preserve sections, sources, cards
                  isStreaming: true,
                  isFinalized: false, // ✅ Still streaming
                );
                ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                
                if (kDebugMode) {
                  debugPrint('📝 Received verdict (first sentence): $firstSentence');
                }
              }
            } else if (type == 'message') {
              // ✅ PERPLEXITY-STYLE: Streaming "message" events can ONLY append to summary
              // They CANNOT touch structured data (sections, sources, cards, images)
              // If session is finalized, ignore these events entirely
              
              // ✅ CRITICAL: Get session by ID (not by position)
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              if (currentSession.isFinalized) {
                // ✅ FINALIZED: Ignore streaming events - END event already committed final state
                if (kDebugMode) {
                  debugPrint('⚠️ Ignoring message event - session is finalized');
                }
                continue; // Skip this event
              }
              
              // Streaming chunks - append to accumulated text
              final chunk = data['data']?.toString() ?? '';
              if (chunk.isNotEmpty) {
                accumulatedText += chunk;
                
                // ✅ PERPLEXITY-STYLE: First token transitions phase and initializes stream
                if (currentSession.phase == QueryPhase.searching) {
                  // Initialize stream controller
                  ref.read(sessionStreamProvider.notifier).initialize(sessionId);
                  
                  // ✅ ONE-TIME TRANSITION: searching → answering
                  final transitionedSession = currentSession.copyWith(
                    phase: QueryPhase.answering, // ← Phase transition
                    isStreaming: true,
                    isFinalized: false,
                    hasReceivedFirstChunk: true,
                  );
                  ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, transitionedSession);
                  
                  if (kDebugMode) {
                    debugPrint('🔄 Phase transition: searching → answering (first token)');
                  }
                }
                
                // ✅ PERPLEXITY-STYLE: Push chunk to stream (NO session update)
                ref.read(sessionStreamProvider.notifier).addChunk(chunk);
                
                if (kDebugMode) {
                  debugPrint('📝 Received message chunk (${chunk.length} chars), total: ${accumulatedText.length}');
                }
              }
            } else if (type == 'summary') {
              // ✅ PERPLEXITY-STYLE: Summary events are streaming - only update summary
              // ✅ CRITICAL: Get session by ID (not by position)
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              if (currentSession.isFinalized) {
                if (kDebugMode) {
                  debugPrint('⚠️ Ignoring summary event - session is finalized');
                }
                continue;
              }
              
              // ✅ LEGACY: Handle summary event (if backend sends it)
              final summary = data['summary']?.toString();
              final intent = data['intent']?.toString();
              final cardType = data['cardType']?.toString();
              
              if (summary != null && summary.isNotEmpty) {
                accumulatedText = summary; // Update accumulated text
                // ✅ CRITICAL: Single source of truth - summary is already in session
              }

              // ✅ PERPLEXITY-STYLE: ONLY update summary/intent/cardType, NEVER touch structured data
              final partialSession = currentSession.copyWith(
                summary: summary,
                intent: intent,
                cardType: cardType,
                isStreaming: true, // Still streaming
                isFinalized: false, // ✅ Not finalized yet
              );
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
              
              if (kDebugMode) {
                debugPrint('📝 Received summary (partial update)');
              }
            } else if (type == 'end') {
              // ✅ END EVENT: Clear stream tracking and commit final state
              
              // ✅ CRITICAL: Clear stream tracking on END event
              // The await for loop will exit naturally after processing this event
              if (_activeSessionId == sessionId) {
                _activeSessionId = null;
              }
              
              // ✅ TASK 3: Clean up processed eventIds for this session (optional - can keep for debugging)
              // _processedEventIds.remove(sessionId); // Uncomment if you want to free memory
              
              // ✅ FIX: Process final data from end event (includes sections, sources, cards, images, videos, maps)
              final endData = data;
              // ✅ CRITICAL FIX: Prioritize accumulatedText (from streaming chunks) over end event data
              // accumulatedText contains ALL streaming chunks, while end event might have empty/short summary
              final endSummary = endData['summary']?.toString() ?? '';
              final endAnswer = endData['answer']?.toString() ?? '';
              // Use accumulatedText if it's longer (more complete), otherwise use end event data
              final finalSummary = (accumulatedText.length > endSummary.length) 
                  ? accumulatedText 
                  : (endSummary.isNotEmpty ? endSummary : accumulatedText);
              final finalAnswer = (accumulatedText.length > endAnswer.length)
                  ? accumulatedText
                  : (endAnswer.isNotEmpty ? endAnswer : accumulatedText);
              final sections = endData['sections'] as List<dynamic>? ?? [];
              final endEventSources = endData['sources'] as List<dynamic>? ?? [];
              
              // ✅ FIX: Merge sources from end event with accumulated sources from source blocks
              // Get current session to access accumulated sources
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              // Merge sources: accumulated sources (from source blocks) + end event sources
              final accumulatedSources = currentSession.sources;
              final endEventSourcesList = (endEventSources ?? []).map((s) => Map<String, dynamic>.from(s as Map<String, dynamic>)).toList();
              
              // Deduplicate by URL
              final sourceUrls = <String>{};
              final mergedSources = <Map<String, dynamic>>[];
              
              // Add accumulated sources first (from real-time source blocks)
              for (final source in accumulatedSources) {
                final url = (source['url'] ?? source['link'] ?? '').toString();
                if (url.isNotEmpty && !sourceUrls.contains(url)) {
                  sourceUrls.add(url);
                  mergedSources.add(Map<String, dynamic>.from(source));
                }
              }
              
              // Add end event sources (if not already present)
              for (final source in endEventSourcesList) {
                final url = (source['url'] ?? source['link'] ?? '').toString();
                if (url.isNotEmpty && !sourceUrls.contains(url)) {
                  sourceUrls.add(url);
                  mergedSources.add(source);
                }
              }
              
              final sources = mergedSources;
              final followUpSuggestions = endData['followUpSuggestions'] as List<dynamic>? ?? [];
              
              // ✅ WIDGET SYSTEM: Extract widgets from end event and convert to cardsByDomain
              Map<String, dynamic>? cardsByDomain;
              List<Map<String, dynamic>> allCards = [];
              
              // ✅ NEW: Read widgets from end event
              if (endData['widgets'] != null && endData['widgets'] is List) {
                final widgets = (endData['widgets'] as List).cast<Map<String, dynamic>>();
                
                // Convert widgets to cardsByDomain format
                final cardsByDomainMap = <String, dynamic>{
                  'products': <Map<String, dynamic>>[],
                  'hotels': <Map<String, dynamic>>[],
                  'places': <Map<String, dynamic>>[],
                  'movies': <Map<String, dynamic>>[],
                };
                
                for (final widget in widgets) {
                  final widgetType = widget['type']?.toString();
                  final widgetData = widget['data'];
                  final success = widget['success'] == true;
                  
                  if (!success || widgetData == null) continue;
                  
                  if (widgetData is List) {
                    final cardList = widgetData
                        .cast<Map<String, dynamic>>();
                    
                    switch (widgetType) {
                      case 'product':
                        (cardsByDomainMap['products'] as List).addAll(cardList);
                        allCards.addAll(cardList);
                        break;
                      case 'hotel':
                        (cardsByDomainMap['hotels'] as List).addAll(cardList);
                        allCards.addAll(cardList);
                        break;
                      case 'place':
                        (cardsByDomainMap['places'] as List).addAll(cardList);
                        allCards.addAll(cardList);
                        break;
                      case 'movie':
                        (cardsByDomainMap['movies'] as List).addAll(cardList);
                        allCards.addAll(cardList);
                        break;
                    }
                  }
                }
                
                cardsByDomain = cardsByDomainMap;
              }
              
              final destinationImages = (endData['destination_images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              final videos = endData['videos'] as List<dynamic>? ?? [];
              final mapPoints = endData['mapPoints'] as List<dynamic>? ?? [];
              
              // ✅ ARCHITECTURE FIX: Extract backend UI decision contract
              final scenario = endData['scenario'] as String?;
              final uiDecision = endData['uiDecision'] as Map<String, dynamic>?;
              
              // ✅ Aggregate images in isolate
              final allImages = await compute(_aggregateImagesWrapper, {
                'destinationImages': destinationImages,
                'cards': allCards,
                'results': [],
              });
              
              // ✅ PERPLEXITY-STYLE: END event is the SINGLE authoritative state commit
              // This sets ALL structured data and marks session as finalized
              // Once finalized, streaming "message" events cannot overwrite this data
              // ✅ CRITICAL: Reuse currentSession from earlier (already fetched for source merging)
              
              // ✅ PERPLEXITY-STYLE: Close stream controller on END event
              ref.read(sessionStreamProvider.notifier).close();
              
              final completeSession = currentSession.copyWith(
                summary: finalSummary,
                answer: finalAnswer, // ✅ CRITICAL: Store full answer text (not just summary)
                sections: sections.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                sources: sources.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                followUpSuggestions: followUpSuggestions.map((f) => f.toString()).toList(),
                cardsByDomain: cardsByDomain != null ? Map<String, dynamic>.from(cardsByDomain) : null,
                cards: allCards, // ✅ DEPRECATED: Keep for backward compatibility
                scenario: scenario, // ✅ ARCHITECTURE FIX: Backend scenario
                uiDecision: uiDecision != null ? Map<String, dynamic>.from(uiDecision) : null, // ✅ ARCHITECTURE FIX: Backend UI decision
                destinationImages: destinationImages,
                videos: videos.isNotEmpty ? videos.map((v) => Map<String, dynamic>.from(v as Map)).toList() : null,
                mapPoints: mapPoints.isNotEmpty ? mapPoints.map((m) => Map<String, dynamic>.from(m as Map)).toList() : null,
                allImages: allImages,
                phase: QueryPhase.done, // ✅ PERPLEXITY-STYLE: Transition to done phase
                isStreaming: false, // ✅ CRITICAL: Must be false to clear loading
                isParsing: false, // ✅ CRITICAL: Must be false to clear loading
                isFinalized: true, // ✅ PERPLEXITY-STYLE: Mark as finalized - prevents streaming from overwriting
              );
              
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, completeSession);
              ref.read(agentStateProvider.notifier).state = AgentState.completed;
              
              if (kDebugMode) {
                debugPrint('🏁 Stream ended - Final answer length: ${finalAnswer.length}');
                debugPrint('  - Summary length: ${finalSummary.length}');
                debugPrint('  - Accumulated text length: ${accumulatedText.length}');
                debugPrint('  - Sections: ${sections.length}');
                debugPrint('  - Sources: ${sources.length}');
                debugPrint('  - Cards: ${allCards.length}');
              }
              break;
            } else if (type == 'error') {
              // ✅ ERROR EVENT: Clear stream tracking and throw error
              print("🔥🔥🔥 ERROR EVENT RECEIVED - Clearing stream tracking");
              if (_activeSessionId == sessionId) {
                _activeSessionId = null;
              }
              throw Exception(data['error'] ?? data['data'] ?? 'Streaming error');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to parse SSE line: $line, error: $e');
            }
            continue;
          }
        }
        } // Close the await for loop
      } catch (streamError, streamStackTrace) {
        // ✅ STREAM ERROR: Handle connection errors gracefully
        print("🔥🔥🔥 STREAM ERROR: $streamError");
        print("🔥🔥🔥 STREAM ERROR TYPE: ${streamError.runtimeType}");
        print("🔥🔥🔥 STREAM STACK: $streamStackTrace");
        
        // ✅ CRITICAL: Clear stream tracking on error
        if (_activeSessionId == sessionId) {
          _activeSessionId = null;
          print("🔥🔥🔥 Stream tracking cleared due to error");
        }
        
        // Check if it's a connection closed error
        if (streamError.toString().contains('Connection closed') || 
            streamError.toString().contains('ClientException')) {
          print("🔥🔥🔥 Connection was closed by server or client");
          // If we have accumulated text, use it
          if (accumulatedText.isNotEmpty) {
            final partialSession = initialSession.copyWith(
              summary: accumulatedText,
              isStreaming: false,
              isParsing: false,
              isFinalized: true,
            );
            ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
            ref.read(agentStateProvider.notifier).state = AgentState.completed;
            return;
          }
        }
        rethrow; // Re-throw to be caught by outer catch
      } finally {
        // ✅ CRITICAL: Ensure stream tracking is cleared even if loop exits unexpectedly
        // This should only happen if END event was received (already cleared above)
        if (_activeSessionId == sessionId) {
          print("⚠️ WARNING: Stream tracking still active after loop exit - clearing");
          _activeSessionId = null;
        }
      }
    } catch (e, stackTrace) {
      // Fallback to error state
      print("🔥🔥🔥 CRITICAL STREAMING ERROR: $e");
      print("🔥🔥🔥 STACK TRACE: $stackTrace");
      
      // ✅ FIX: Detect connection errors and provide helpful message
      String errorMessage = 'An error occurred while processing your request.';
      if (e.toString().contains('Connection refused') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        errorMessage = 'Unable to connect to the server. Please make sure:\n\n'
            '1. The backend server is running on port 4000\n'
            '2. Your device and computer are on the same network\n'
            '3. Try: http://127.0.0.1:4000/api/test in your browser';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. The server may be taking too long to respond.';
      }
      
      final errorSession = initialSession.copyWith(
        isStreaming: false,
        isParsing: false,
        error: errorMessage, // ✅ NEW: Set error message
        summary: errorMessage, // ✅ Also set as summary so UI shows it
      );
      
      print("🔥🔥🔥 UPDATING SESSION WITH ERROR:");
      print("  - error: ${errorSession.error}");
      print("  - summary: ${errorSession.summary}");
      print("  - isStreaming: ${errorSession.isStreaming}");
      print("  - isParsing: ${errorSession.isParsing}");
      
      ref.read(sessionHistoryProvider.notifier).updateSessionById(initialSession.sessionId, errorSession);
      ref.read(agentStateProvider.notifier).state = AgentState.error;
      
      print("🔥🔥🔥 SESSION UPDATED - UI should rebuild now");
      
      if (kDebugMode) {
        debugPrint('❌ Streaming error: $e');
      }
    }
  }

  /// ✅ NEW: Generate a unique message ID
  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9999 - 1000) * (DateTime.now().microsecond / 1000000)).round()}';
  }

  /// ✅ NEW: Generate a unique chat ID
  String _generateChatId() {
    return 'chat_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9999 - 1000) * (DateTime.now().microsecond / 1000000)).round()}';
  }

  /// ✅ NEW: Convert conversationHistory format to history format
  /// Old format: [{query: "...", summary: "..."}]
  /// New format: [["human", "..."], ["assistant", "..."]]
  List<List<String>> _convertConversationHistoryToHistory(
    List<Map<String, dynamic>> conversationHistory,
  ) {
    final history = <List<String>>[];
    
    for (final item in conversationHistory) {
      // Add user query
      if (item['query'] != null && item['query'].toString().isNotEmpty) {
        history.add(['human', item['query'].toString()]);
      }
      
      // Add assistant response (summary or answer)
      final summary = item['summary']?.toString() ?? item['answer']?.toString();
      if (summary != null && summary.isNotEmpty) {
        history.add(['assistant', summary]);
      }
    }
    
    return history;
  }
}

/// ✅ SSE OWNERSHIP: Non-autoDispose provider that owns SSE streams
/// This ensures AgentController survives widget rebuilds and keyboard events
final agentControllerProvider =
    StateNotifierProvider<AgentController, void>(
  (ref) {
    // ✅ CRITICAL: Keep provider alive to prevent stream cancellation on rebuild
    ref.keepAlive();
    return AgentController(ref);
  },
);

// ✅ FIX 2: Wrapper for fastParseTextWithLocations (compute requires single param)
List<Map<String, dynamic>> _parseTextWithLocationsWrapper(Map<String, dynamic> input) {
  return fastParseTextWithLocations(
    input['text'] as String,
    (input['locationCards'] as List).cast<Map<String, dynamic>>(),
  );
}

// ✅ TASK 3: Wrapper for image aggregation (compute requires single param)
// Moves image aggregation off UI thread to prevent blocking
List<String> _aggregateImagesWrapper(Map<String, dynamic> input) {
  final allImages = <String>[];
  final destinationImages = (input['destinationImages'] as List?)?.cast<String>() ?? [];
  final cards = (input['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final results = (input['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  
  // From destination images
  allImages.addAll(destinationImages.where((img) => img.isNotEmpty && img.startsWith('http')));
  
  // From cards (products, hotels, etc.)
  for (final card in cards) {
    if (card['images'] != null) {
      if (card['images'] is List) {
        for (final img in card['images'] as List) {
          final imgStr = img?.toString() ?? '';
          if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
            allImages.add(imgStr);
          }
        }
      } else if (card['images'] is String) {
        final imgStr = card['images'] as String;
        if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
          allImages.add(imgStr);
        }
      }
    }
    if (card['image'] != null) {
      final imgStr = card['image']?.toString() ?? '';
      if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
        allImages.add(imgStr);
      }
    }
  }
  
  // From results (hotels, places, etc.)
  for (final result in results) {
    if (result['images'] != null && result['images'] is List) {
      for (final img in result['images'] as List) {
        final imgStr = img?.toString() ?? '';
        if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
          allImages.add(imgStr);
        }
      }
    }
    if (result['image_url'] != null) {
      final imgStr = result['image_url']?.toString() ?? '';
      if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
        allImages.add(imgStr);
      }
    }
  }
  
  return allImages;
}

// ✅ REMOVED: _parseAgentResponse is no longer needed
// AgentService.askAgent() now handles response parsing and returns Map<String, dynamic> directly


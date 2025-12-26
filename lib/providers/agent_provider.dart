import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import '../core/api_client.dart';
import '../models/query_session_model.dart';
import '../isolates/text_parsing_isolate.dart'; // ✅ FIX 2
import '../services/AgentService.dart';
import 'session_history_provider.dart';
import 'streaming_text_provider.dart';

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

  AgentController(this.ref) : super(null);

  /// ✅ Build conversation history from completed sessions
  /// Only includes sessions with non-empty query and summary
  List<Map<String, dynamic>> _buildConversationHistory() {
    final sessions = ref.read(sessionHistoryProvider);
    final history = <Map<String, dynamic>>[];
    
    for (final session in sessions) {
      // Only include completed sessions (has summary and not currently streaming/parsing)
      if (session.query.isNotEmpty && 
          session.summary != null && 
          session.summary!.isNotEmpty &&
          !session.isStreaming &&
          !session.isParsing) {
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
    
    // ✅ FIX: Prevent duplicate query submissions (but allow follow-ups even if same query)
    final existingSessions = ref.read(sessionHistoryProvider);
    final trimmedQuery = query.trim();
    final queryAlreadyExists = existingSessions.any((s) => 
      s.query.trim() == trimmedQuery && 
      s.imageUrl == imageUrl &&
      (s.isStreaming || s.isParsing) // Only prevent if query is still processing
    );
    
    if (queryAlreadyExists) {
      print("🔥🔥🔥❌❌❌ SKIPPING DUPLICATE: Query '$trimmedQuery' is already processing");
      print("🔥🔥🔥❌❌❌ Existing sessions:");
      for (var s in existingSessions) {
        print("🔥🔥🔥❌❌❌   - Query: '${s.query}', isStreaming: ${s.isStreaming}, isParsing: ${s.isParsing}");
      }
      if (kDebugMode) {
        debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already processing)');
      }
      return; // Don't submit duplicate query
    }
    
    print("🔥🔥🔥✅✅✅ NOT A DUPLICATE - Proceeding with query submission");
    print("🔥🔥🔥✅✅✅ Existing sessions count: ${existingSessions.length}");
    
    // ✅ PHASE 4: Reset streaming text on new query
    ref.read(streamingTextProvider.notifier).reset();
    
    ref.read(agentStateProvider.notifier).state = AgentState.loading;

    // Create initial session
    final initialSession = QuerySession(
      query: query,
      isStreaming: true,
      isParsing: false,
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
          print("🔥🔥🔥✅✅✅ _handleStreamingResponse RETURNED SUCCESSFULLY");
        } catch (streamError, streamStackTrace) {
          print("🔥🔥🔥❌❌❌ _handleStreamingResponse THREW EXCEPTION: $streamError");
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
      final intent = responseData['intent']?.toString();
      final cardType = responseData['cardType']?.toString();
      
      // ✅ PERPLEXITY-STYLE: Extract structured cards by domain
      Map<String, dynamic>? cardsByDomain;
      List<Map<String, dynamic>> cards = []; // ✅ DEPRECATED: Keep for backward compatibility
      
      if (responseData['cards'] != null) {
        if (responseData['cards'] is Map) {
          // ✅ NEW: Structured cards object { products: [], hotels: [], places: [], movies: [] }
          final cardsMap = responseData['cards'] as Map;
          cardsByDomain = Map<String, dynamic>.from(cardsMap);
          
          // ✅ Flatten for backward compatibility (deprecated)
          final allCards = <Map<String, dynamic>>[];
          if (cardsMap['products'] is List) {
            allCards.addAll((cardsMap['products'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)));
          }
          if (cardsMap['hotels'] is List) {
            allCards.addAll((cardsMap['hotels'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)));
          }
          if (cardsMap['places'] is List) {
            allCards.addAll((cardsMap['places'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)));
          }
          if (cardsMap['movies'] is List) {
            allCards.addAll((cardsMap['movies'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)));
          }
          cards = allCards;
        } else if (responseData['cards'] is List) {
          // ✅ OLD: Flat list (backward compatibility)
          cards = (responseData['cards'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
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

      // ✅ PHASE 4: Start streaming animation for summary
      if (summary != null && summary.isNotEmpty) {
        ref.read(streamingTextProvider.notifier).start(summary);
      }

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
      final allImages = await compute(_aggregateImagesWrapper, {
        'destinationImages': destinationImages,
        'cards': cards,
        'results': results,
      });

      // Update session with response data
      final updatedSession = initialSession.copyWith(
        summary: summary,
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
      
      ref.read(sessionHistoryProvider.notifier).replaceLastSession(updatedSession);
      
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
      
      // Update session with error state
      final errorSession = initialSession.copyWith(
        isStreaming: false,
        isParsing: false,
      );
      ref.read(sessionHistoryProvider.notifier).replaceLastSession(errorSession);
      
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
    print("🔥🔥🔥 Conversation history length: ${conversationHistory.length}");
    
    try {
      // ✅ Build request body with conversationHistory
      final requestBody = <String, dynamic>{
        "query": query,
        "conversationHistory": conversationHistory,
      };
      if (imageUrl != null) {
        requestBody["imageUrl"] = imageUrl;
      }
      
      print("🔥🔥🔥 SENDING STREAMING REQUEST...");
      print("🔥🔥🔥 Request body: $requestBody");
      print("🔥🔥🔥 Endpoint: /agent?stream=true");
      
      final streamedResponse;
      try {
        print("🔥🔥🔥 ABOUT TO CALL ApiClient.postStream...");
        streamedResponse = await ApiClient.postStream("/agent?stream=true", requestBody);
        print("🔥🔥🔥 STREAMING RESPONSE RECEIVED: status=${streamedResponse.statusCode}");
        print("🔥🔥🔥 Response headers: ${streamedResponse.headers}");
        print("🔥🔥🔥 Response content-type: ${streamedResponse.headers['content-type']}");
      } catch (e, stackTrace) {
        print("🔥🔥🔥❌❌❌ ERROR GETTING STREAMING RESPONSE: $e");
        print("🔥🔥🔥❌❌❌ ERROR TYPE: ${e.runtimeType}");
        print("🔥🔥🔥❌❌❌ STACK: $stackTrace");
        rethrow;
      }
      
      if (streamedResponse.statusCode != 200) {
        print("🔥🔥🔥 STREAMING REQUEST FAILED: ${streamedResponse.statusCode}");
        final errorBody = await streamedResponse.stream.bytesToString();
        print("🔥🔥🔥 ERROR BODY: $errorBody");
        throw Exception("Streaming request failed: ${streamedResponse.statusCode}");
      }

      print("🔥🔥🔥 CREATING STREAM DECODER...");
      final stream = streamedResponse.stream.transform(utf8.decoder);
      print("🔥🔥🔥 STREAM DECODER CREATED");
      String buffer = '';

      String accumulatedText = ''; // ✅ FIX: Accumulate streaming text in real-time
      
      print("🔥🔥🔥 STREAMING STARTED - Waiting for events...");
      
      await for (var chunk in stream) {
        print("🔥🔥🔥 STREAM CHUNK RECEIVED (${chunk.length} chars)");
        print("🔥🔥🔥 CHUNK PREVIEW: ${chunk.substring(0, chunk.length > 200 ? 200 : chunk.length)}");
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
          
          // ✅ FIX: Handle JSON response (non-SSE) - backend might return JSON instead of SSE
          if (!line.startsWith('data: ')) {
            print("🔥🔥🔥 NON-SSE LINE DETECTED (JSON response?): ${line.substring(0, 200)}");
            // Try to parse as complete JSON response
            try {
              final jsonData = jsonDecode(line) as Map<String, dynamic>;
              print("🔥🔥🔥 PARSED AS JSON - Processing as complete response");
              
              // Process as if it's an end event with all data
              final finalSummary = jsonData['summary']?.toString() ?? accumulatedText;
              final sections = jsonData['sections'] as List<dynamic>? ?? [];
              final sources = jsonData['sources'] as List<dynamic>? ?? [];
              final followUpSuggestions = jsonData['followUpSuggestions'] as List<dynamic>? ?? [];
              final cardsByDomain = jsonData['cards'] as Map<String, dynamic>?;
              final destinationImages = (jsonData['destination_images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              
              // Update session with final data
              final completeSession = initialSession.copyWith(
                summary: finalSummary,
                sections: sections.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                sources: sources.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                followUpSuggestions: followUpSuggestions.map((f) => f.toString()).toList(),
                cardsByDomain: cardsByDomain != null ? Map<String, dynamic>.from(cardsByDomain) : null,
                destinationImages: destinationImages,
                isStreaming: false,
                isParsing: false,
              );
              
              ref.read(sessionHistoryProvider.notifier).replaceLastSession(completeSession);
              ref.read(agentStateProvider.notifier).state = AgentState.completed;
              
              print("🔥🔥🔥 JSON RESPONSE PROCESSED - Session updated");
              return; // Exit early since we got complete response
            } catch (e) {
              print("🔥🔥🔥 FAILED TO PARSE AS JSON: $e");
              continue; // Skip this line
            }
          }

          try {
            final jsonStr = line.substring(6); // Remove "data: " prefix
            if (jsonStr.trim() == '[DONE]') {
              print("🔥🔥🔥 RECEIVED [DONE] marker");
              continue;
            }
            
            print("🔥🔥🔥 PARSING SSE EVENT: $jsonStr");
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type'] as String?;
            print("🔥🔥🔥 EVENT TYPE: $type");

            // ✅ FIX: Handle real-time streaming events from backend
            if (type == 'verdict') {
              // First sentence - display immediately
              final firstSentence = data['data']?.toString() ?? '';
              if (firstSentence.isNotEmpty) {
                accumulatedText = firstSentence;
                ref.read(streamingTextProvider.notifier).start(accumulatedText);
                
                // Update session with streaming text
                final partialSession = initialSession.copyWith(
                  summary: accumulatedText,
                  isStreaming: true,
                );
                ref.read(sessionHistoryProvider.notifier).replaceLastSession(partialSession);
                
                if (kDebugMode) {
                  debugPrint('📝 Received verdict (first sentence): $firstSentence');
                }
              }
            } else if (type == 'message') {
              // Streaming chunks - append to accumulated text
              final chunk = data['data']?.toString() ?? '';
              if (chunk.isNotEmpty) {
                accumulatedText += chunk;
                ref.read(streamingTextProvider.notifier).start(accumulatedText);
                
                // Update session with accumulated text
                final partialSession = initialSession.copyWith(
                  summary: accumulatedText,
                  isStreaming: true,
                );
                ref.read(sessionHistoryProvider.notifier).replaceLastSession(partialSession);
                
                if (kDebugMode) {
                  debugPrint('📝 Received message chunk (${chunk.length} chars), total: ${accumulatedText.length}');
                }
              }
            } else if (type == 'summary') {
              // ✅ LEGACY: Handle summary event (if backend sends it)
              final summary = data['summary']?.toString();
              final intent = data['intent']?.toString();
              final cardType = data['cardType']?.toString();
              
              if (summary != null && summary.isNotEmpty) {
                accumulatedText = summary; // Update accumulated text
                ref.read(streamingTextProvider.notifier).start(accumulatedText);
              }

              // Update session with summary (partial update)
              final partialSession = initialSession.copyWith(
                summary: summary,
                intent: intent,
                cardType: cardType,
                isStreaming: true, // Still streaming cards
              );
              ref.read(sessionHistoryProvider.notifier).replaceLastSession(partialSession);
              
              if (kDebugMode) {
                debugPrint('📝 Received summary (partial update)');
              }
            } else if (type == 'end') {
              // ✅ FIX: Process final data from end event (includes sections, sources, cards, images, videos, maps)
              final endData = data;
              final finalSummary = endData['summary']?.toString() ?? accumulatedText;
              final finalAnswer = endData['answer']?.toString() ?? finalSummary;
              final sections = endData['sections'] as List<dynamic>? ?? [];
              final sources = endData['sources'] as List<dynamic>? ?? [];
              final followUpSuggestions = endData['followUpSuggestions'] as List<dynamic>? ?? [];
              
              // ✅ Extract cards from end event (now included in end event)
              final cardsByDomain = endData['cards'] as Map<String, dynamic>?;
              final destinationImages = (endData['destination_images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              final videos = endData['videos'] as List<dynamic>? ?? [];
              final mapPoints = endData['mapPoints'] as List<dynamic>? ?? [];
              
              // ✅ Parse cards from cardsByDomain
              List<Map<String, dynamic>> allCards = [];
              if (cardsByDomain != null) {
                // Flatten all cards from all domains
                if (cardsByDomain['products'] is List) {
                  allCards.addAll((cardsByDomain['products'] as List).cast<Map<String, dynamic>>());
                }
                if (cardsByDomain['hotels'] is List) {
                  allCards.addAll((cardsByDomain['hotels'] as List).cast<Map<String, dynamic>>());
                }
                if (cardsByDomain['places'] is List) {
                  allCards.addAll((cardsByDomain['places'] as List).cast<Map<String, dynamic>>());
                }
                if (cardsByDomain['movies'] is List) {
                  allCards.addAll((cardsByDomain['movies'] as List).cast<Map<String, dynamic>>());
                }
              }
              
              // ✅ Aggregate images in isolate
              final allImages = await compute(_aggregateImagesWrapper, {
                'destinationImages': destinationImages,
                'cards': allCards,
                'results': [],
              });
              
              // Update session with final data
              final completeSession = initialSession.copyWith(
                summary: finalSummary,
                sections: sections.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                sources: sources.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                followUpSuggestions: followUpSuggestions.map((f) => f.toString()).toList(),
                cardsByDomain: cardsByDomain != null ? Map<String, dynamic>.from(cardsByDomain) : null,
                cards: allCards, // ✅ DEPRECATED: Keep for backward compatibility
                destinationImages: destinationImages,
                videos: videos.isNotEmpty ? videos.map((v) => Map<String, dynamic>.from(v as Map)).toList() : null,
                mapPoints: mapPoints.isNotEmpty ? mapPoints.map((m) => Map<String, dynamic>.from(m as Map)).toList() : null,
                allImages: allImages,
                isStreaming: false, // ✅ CRITICAL: Must be false to clear loading
                isParsing: false, // ✅ CRITICAL: Must be false to clear loading
              );
              
              ref.read(sessionHistoryProvider.notifier).replaceLastSession(completeSession);
              ref.read(agentStateProvider.notifier).state = AgentState.completed;
              
              print("🔥 END EVENT RECEIVED - Session updated:");
              print("  - Summary: ${finalSummary.isNotEmpty ? 'YES (${finalSummary.length} chars)' : 'NO'}");
              print("  - Sections: ${sections.length}");
              print("  - Sources: ${sources.length}");
              print("  - Cards: ${allCards.length}");
              print("  - isStreaming: ${completeSession.isStreaming} (MUST be false)");
              print("  - isParsing: ${completeSession.isParsing} (MUST be false)");
              
              if (kDebugMode) {
                debugPrint('🏁 Stream ended - Final answer length: ${finalAnswer.length}');
                debugPrint('  - Sections: ${sections.length}');
                debugPrint('  - Sources: ${sources.length}');
                debugPrint('  - Cards: ${allCards.length}');
              }
              break;
            } else if (type == 'error') {
              throw Exception(data['error'] ?? 'Streaming error');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to parse SSE line: $line, error: $e');
            }
            continue;
          }
        }
      }
    } catch (e, stackTrace) {
      // Fallback to error state
      print("🔥🔥🔥 CRITICAL STREAMING ERROR: $e");
      print("🔥🔥🔥 STACK TRACE: $stackTrace");
      
      final errorSession = initialSession.copyWith(
        isStreaming: false,
        isParsing: false,
      );
      ref.read(sessionHistoryProvider.notifier).replaceLastSession(errorSession);
      ref.read(agentStateProvider.notifier).state = AgentState.error;
      
      if (kDebugMode) {
        debugPrint('❌ Streaming error: $e');
      }
    }
  }
}

final agentControllerProvider =
    StateNotifierProvider<AgentController, void>(
  (ref) => AgentController(ref),
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


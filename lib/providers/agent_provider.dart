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
import 'scroll_provider.dart';

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

  Future<void> submitQuery(String query, {String? imageUrl, bool useStreaming = false}) async {
    // ✅ FIX: Prevent duplicate query submissions
    final existingSessions = ref.read(sessionHistoryProvider);
    final trimmedQuery = query.trim();
    final queryAlreadyExists = existingSessions.any((s) => 
      s.query.trim() == trimmedQuery && 
      s.imageUrl == imageUrl &&
      (s.isStreaming || s.isParsing) // Only prevent if query is still processing
    );
    
    if (queryAlreadyExists) {
      if (kDebugMode) {
        debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already processing)');
      }
      return; // Don't submit duplicate query
    }
    
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

    try {
      // ✅ TASK 4: Support streaming responses (opt-in via useStreaming flag)
      if (useStreaming) {
        await _handleStreamingResponse(query, imageUrl, initialSession, conversationHistory);
        return;
      }
      
      // ✅ Non-streaming: Use AgentService.askAgent() to ensure conversationHistory is sent
      print("🔥 ABOUT TO CALL AgentService.askAgent for query: '$query'");
      final responseData = await AgentService.askAgent(
        query,
        stream: false,
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
      
      // ✅ FIX: Extract cards with proper type checking
      List<Map<String, dynamic>> cards = [];
      if (responseData['cards'] != null) {
        if (responseData['cards'] is List) {
          cards = (responseData['cards'] as List).map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
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
      print("  - CardType: $cardType");
      print("  - Cards: ${cards.length} items (type: ${responseData['cards'].runtimeType})");
      print("  - Results: ${results is List ? results.length : 'N/A'} items");
      print("  - Sections: ${sections.length} items");
      print("  - LocationCards: ${locationCards.length} items");
      print("  - DestinationImages: ${destinationImages.length} items");
      
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
        cards: cards,
        results: results,
        sections: sections, // ✅ FIX: Extract sections for hotels
        mapPoints: mapPoints, // ✅ FIX: Extract map points for hotels
        destinationImages: destinationImages,
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

      // ✅ DEBUG: Log hotel sections extraction
      if (kDebugMode && (intent == 'hotel' || intent == 'hotels')) {
        debugPrint('🏨 Hotel Response Debug:');
        debugPrint('  - Sections count: ${sections.length}');
        debugPrint('  - Map points count: ${mapPoints.length}');
        debugPrint('  - Updated session sections: ${updatedSession.sections?.length ?? 0}');
        debugPrint('  - Updated session hotelSections getter: ${updatedSession.hotelSections?.length ?? 0}');
        if (sections.isNotEmpty) {
          debugPrint('  - First section title: ${sections.first['title']}');
          debugPrint('  - First section items count: ${(sections.first['items'] as List?)?.length ?? 0}');
        }
      }

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
        print("  - HotelSections count: ${lastSession.hotelSections?.length ?? 0}");
        print("  - HotelResults count: ${lastSession.hotelResults.length}");
        print("  - Cards count: ${lastSession.cards.length}");
        print("  - LocationCards count: ${lastSession.locationCards.length}");
        print("  - Results count: ${lastSession.results.length}");
        
        // ✅ CRITICAL CHECK: Verify session actually has data
        final hasAnyData = (lastSession.summary != null && lastSession.summary!.isNotEmpty) ||
                           lastSession.cards.isNotEmpty ||
                           lastSession.locationCards.isNotEmpty ||
                           lastSession.rawResults.isNotEmpty ||
                           (lastSession.hotelSections != null && lastSession.hotelSections!.isNotEmpty) ||
                           lastSession.hotelResults.isNotEmpty;
        print("  - HAS ANY DATA: $hasAnyData");
        print("  - SHOULD SHOW CONTENT: ${!lastSession.isStreaming && !lastSession.isParsing && hasAnyData}");
      }
      
      if (kDebugMode) {
        debugPrint('✅ Session updated in provider - UI should rebuild now');
      }

      // ✅ FIX 3: Update state to completed (force state change)
      ref.read(agentStateProvider.notifier).state = AgentState.completed;
      
      print("🔥 Agent state set to completed - UI should rebuild now");

      // ✅ PHASE 7: Trigger scroll to bottom when streaming finishes
      ref.read(scrollProvider.notifier).scrollToBottom();

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
    try {
      // ✅ Build request body with conversationHistory
      final requestBody = <String, dynamic>{
        "query": query,
        "conversationHistory": conversationHistory,
      };
      if (imageUrl != null) {
        requestBody["imageUrl"] = imageUrl;
      }
      
      final streamedResponse = await ApiClient.postStream("/agent?stream=true", requestBody);

      if (streamedResponse.statusCode != 200) {
        throw Exception("Streaming request failed: ${streamedResponse.statusCode}");
      }

      final stream = streamedResponse.stream.transform(utf8.decoder);
      String buffer = '';
      Map<String, dynamic>? summaryData;

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
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          try {
            final jsonStr = line.substring(6); // Remove "data: " prefix
            if (jsonStr.trim() == '[DONE]') continue;
            
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type'] as String?;

            if (type == 'summary') {
              // ✅ TASK 4: Render summary immediately (partial UI update)
              summaryData = data;
              final summary = data['summary']?.toString();
              final intent = data['intent']?.toString();
              final cardType = data['cardType']?.toString();
              
              if (summary != null && summary.isNotEmpty) {
                ref.read(streamingTextProvider.notifier).start(summary);
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
            } else if (type == 'cards') {
              // ✅ TASK 4: Append cards after summary (incremental update)
              final cards = data['cards'] as List<dynamic>? ?? [];
              final results = data['results'] ?? [];
              final destinationImages = data['destination_images'] as List<dynamic>? ?? [];
              final locationCards = data['locationCards'] as List<dynamic>? ?? [];
              
              // Parse and aggregate in isolate
              final parsedCards = cards.cast<Map<String, dynamic>>();
              final parsedLocationCards = locationCards.cast<Map<String, dynamic>>();
              final parsedDestinationImages = (destinationImages.map((e) => e.toString()).toList()).cast<String>();
              
              // Parse text with locations in isolate
              List<Map<String, dynamic>>? parsedSegments;
              if (summaryData?['summary'] != null && parsedLocationCards.isNotEmpty) {
                try {
                  parsedSegments = await compute(_parseTextWithLocationsWrapper, {
                    'text': summaryData!['summary'] as String,
                    'locationCards': parsedLocationCards,
                  });
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('⚠️ Error parsing text with locations: $e');
                  }
                }
              }

              // Aggregate images in isolate
              final allImages = await compute(_aggregateImagesWrapper, {
                'destinationImages': parsedDestinationImages,
                'cards': parsedCards,
                'results': results,
              });

              // Update session with complete data
              final completeSession = initialSession.copyWith(
                summary: summaryData?['summary']?.toString(),
                intent: summaryData?['intent']?.toString(),
                cardType: summaryData?['cardType']?.toString(),
                cards: parsedCards,
                results: results,
                destinationImages: parsedDestinationImages,
                locationCards: parsedLocationCards,
                isStreaming: false,
                isParsing: false,
                parsedSegments: parsedSegments,
                allImages: allImages,
              );
              
              ref.read(sessionHistoryProvider.notifier).replaceLastSession(completeSession);
              ref.read(agentStateProvider.notifier).state = AgentState.completed;
              ref.read(scrollProvider.notifier).scrollToBottom();
              
              if (kDebugMode) {
                debugPrint('✅ Received cards (complete update)');
              }
            } else if (type == 'end') {
              // Stream complete
              if (kDebugMode) {
                debugPrint('🏁 Stream ended');
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
    } catch (e) {
      // Fallback to error state
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


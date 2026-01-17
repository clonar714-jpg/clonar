import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import '../models/query_session_model.dart';
import '../isolates/text_parsing_isolate.dart'; 
import '../services/AgentService.dart';
import '../services/agent_stream_service.dart'; 
import 'session_history_provider.dart';
import 'session_stream_provider.dart'; 

enum AgentState { idle, loading, streaming, completed, error }


final agentStateProvider = StateProvider<AgentState>((ref) {
  ref.keepAlive();
  return AgentState.idle;
});


final agentResponseProvider =
    StateProvider<Map<String, dynamic>?>((ref) {
  ref.keepAlive();
  return null;
});

class AgentController extends StateNotifier<void> {
  final Ref ref;
  
  
  
  String? _activeSessionId; 
 
  
  
  final Map<String, Set<String>> _processedEventIds = {};
  
  AgentController(this.ref) : super(null);
  
  @override
  void dispose() {
   
    print("🛑 AgentController.dispose() called - clearing stream tracking");
    if (_activeSessionId != null) {
      print("⚠️ WARNING: Active stream exists during dispose - Session: $_activeSessionId");
      _activeSessionId = null;
    }
    super.dispose();
  }
  
 
  void cancelQuery(String sessionId) {
    if (_activeSessionId == sessionId) {
      print("🛑 User canceled query for session: $sessionId");
      
      _activeSessionId = null;
      
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

 
  List<Map<String, dynamic>> _buildConversationHistory() {
    final sessions = ref.read(sessionHistoryProvider);
    final history = <Map<String, dynamic>>[];
    
    for (final session in sessions) {
      
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
    
    
    final existingSessions = ref.read(sessionHistoryProvider);
    final trimmedQuery = query.trim();
    final now = DateTime.now();
    
    // ✅ HISTORY MODE GUARD: If ALL existing sessions are finalized, we're in history mode
    // In history mode, we should NEVER re-execute existing queries
    final allSessionsFinalized = existingSessions.isNotEmpty && 
                                 existingSessions.every((s) => s.isFinalized);
    
    if (allSessionsFinalized && kDebugMode) {
      debugPrint('📚 HISTORY MODE DETECTED: All ${existingSessions.length} sessions are finalized');
      debugPrint('   - This is a read-only history view - checking for duplicate before allowing new query');
    }
    
    final matchingStreamingSession = existingSessions.firstWhere(
      (s) => s.query.trim() == trimmedQuery && 
             s.imageUrl == imageUrl &&
             (s.isStreaming || s.isParsing),
      orElse: () => QuerySession(sessionId: '', query: ''), 
    );
    
    final matchingFinalizedSession = existingSessions.firstWhere(
      (s) => s.query.trim() == trimmedQuery && 
             s.imageUrl == imageUrl &&
             s.isFinalized &&
             s.error == null, 
      orElse: () => QuerySession(sessionId: '', query: ''), 
    );
    
    // ✅ DEBUG: Log all existing sessions for duplicate check
    if (kDebugMode) {
      debugPrint('🔍 Duplicate check for query: "$trimmedQuery"');
      debugPrint('   - Existing sessions: ${existingSessions.length}');
      for (int i = 0; i < existingSessions.length; i++) {
        final s = existingSessions[i];
        debugPrint('   - Session $i: "${s.query}" (finalized: ${s.isFinalized}, summary: ${s.summary?.length ?? 0} chars, error: ${s.error})');
      }
      debugPrint('   - Matching finalized: ${matchingFinalizedSession.query.isNotEmpty}');
    }
    
    if (matchingStreamingSession.query.isNotEmpty) {
      final sessionAge = now.difference(matchingStreamingSession.timestamp);
      final isStuck = sessionAge.inSeconds > 30;
      final canRetry = isStuck || matchingStreamingSession.error != null;
      
      if (!canRetry) {
        print(" SKIPPING DUPLICATE: Query '$trimmedQuery' is already processing");
        print(" Session age: ${sessionAge.inSeconds}s (stuck threshold: 30s)");
        if (kDebugMode) {
          debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already processing)');
        }
        return; 
      } else {
        print(" ALLOWING RETRY: Session is ${isStuck ? 'stuck' : 'errored'}");
      }
    }
    
    
    if (matchingFinalizedSession.query.isNotEmpty) {
      print("🔥🔥🔥❌❌❌ SKIPPING DUPLICATE: Query '$trimmedQuery' already completed successfully");
      print("🔥🔥🔥❌❌❌ Finalized session exists with summary length: ${matchingFinalizedSession.summary?.length ?? 0}");
      if (kDebugMode) {
        debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already completed)');
      }
      return; 
    }
    
    print("🔥🔥🔥✅✅✅ NOT A DUPLICATE - Proceeding with query submission");
    print("🔥🔥🔥✅✅✅ Existing sessions count: ${existingSessions.length}");
    

    
    ref.read(agentStateProvider.notifier).state = AgentState.loading;

    
    final sessionId = QuerySession.generateSessionId();
    print("🔥🔥🔥✅✅✅ Generated sessionId: $sessionId");

    
    final initialSession = QuerySession(
      sessionId: sessionId, 
      query: query,
      isStreaming: true, 
      isParsing: false,
      hasReceivedFirstChunk: false, 
      answer: null, 
      summary: null, 
      sections: null, 
      sources: const [], 
      imageUrl: imageUrl,
    );
    
    
    ref.read(sessionHistoryProvider.notifier).addSession(initialSession);

    
    final conversationHistory = _buildConversationHistory();
    
    
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
      
      
      ref.read(agentResponseProvider.notifier).state = responseData;
      
      print("🔥 Agent response provider updated, starting extraction...");
      
      if (kDebugMode) {
        debugPrint('✅ Received response from backend, processing...');
        debugPrint('  - Response keys: ${responseData.keys.join(", ")}');
      }

      
      final summary = responseData['summary']?.toString();
      final answer = responseData['answer']?.toString() ?? summary; // ✅ CRITICAL: Extract full answer, fallback to summary
      final intent = responseData['intent']?.toString();
      final cardType = responseData['cardType']?.toString();
      
      
      Map<String, dynamic>? cardsByDomain;
      List<Map<String, dynamic>> cards = []; 
      
      
      if (responseData['widgets'] != null && responseData['widgets'] is List) {
        final widgets = (responseData['widgets'] as List).cast<Map<String, dynamic>>();
        
        
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
        cards = allCards; 
      }
      
     
      Map<String, dynamic>? uiRequirements;
      if (responseData['uiRequirements'] != null && responseData['uiRequirements'] is Map) {
        uiRequirements = Map<String, dynamic>.from(responseData['uiRequirements']);
      }
      
      final results = responseData['results'] ?? [];
      
      
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
      
      
      List<String> destinationImages = [];
      if (responseData['destination_images'] != null) {
        if (responseData['destination_images'] is List) {
          destinationImages = (responseData['destination_images'] as List).map((e) => e.toString()).toList();
        }
      }
      
      
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

     
      final updatedSession = initialSession.copyWith(
        summary: summary,
        answer: answer, 
        intent: intent,
        cardType: cardType,
        cards: cards, 
        cardsByDomain: cardsByDomain, 
        uiRequirements: uiRequirements, 
        results: results,
        sections: sections, 
        mapPoints: mapPoints, 
        destinationImages: destinationImages,
        videos: videos.isNotEmpty ? videos : null, 
        locationCards: locationCards,
        sources: sources, 
        followUpSuggestions: followUpSuggestions, 
        isStreaming: false, 
        isParsing: false, 
        isFinalized: true, 
        parsedSegments: parsedSegments, 
        allImages: allImages, 
      );
      

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

     
      print("🔥 ABOUT TO UPDATE SESSION IN PROVIDER");
      print("  - Updated session isStreaming: ${updatedSession.isStreaming}");
      print("  - Updated session isParsing: ${updatedSession.isParsing}");
      print("  - Updated session cards: ${updatedSession.cards.length}");
      print("  - Updated session summary: ${updatedSession.summary != null && updatedSession.summary!.isNotEmpty}");
      
      ref.read(sessionHistoryProvider.notifier).updateSessionById(initialSession.sessionId, updatedSession);
      
      
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
        
        print("  - Sources count: ${lastSession.sources.length}");
        print("  - FollowUpSuggestions count: ${lastSession.followUpSuggestions.length}");
        if (lastSession.sections != null && lastSession.sections!.isNotEmpty) {
          print("  - First section title: ${lastSession.sections![0]['title']}");
          print("  - First section has content: ${lastSession.sections![0]['content'] != null && (lastSession.sections![0]['content']?.toString() ?? '').isNotEmpty}");
          print("  - All section titles: ${lastSession.sections!.map((s) => s['title']).join(', ')}");
        }
        
        
        final hasAnyData = (lastSession.summary != null && lastSession.summary!.isNotEmpty) ||
                           (lastSession.sections != null && lastSession.sections!.isNotEmpty);
        print("  - HAS ANY DATA: $hasAnyData");
        print("  - SHOULD SHOW CONTENT: ${!lastSession.isStreaming && !lastSession.isParsing && hasAnyData}");
      }
      
      if (kDebugMode) {
        debugPrint('✅ Session updated in provider - UI should rebuild now');
      }

      
      ref.read(agentStateProvider.notifier).state = AgentState.completed;
      
      print("🔥 Agent state set to completed - UI should rebuild now");

     

      if (kDebugMode) {
        debugPrint('✅ Agent query completed: $query');
      }
    } catch (e, stackTrace) {
      
      print("❌❌❌ EXCEPTION IN submitQuery:");
      print("  - Error: $e");
      print("  - Error type: ${e.runtimeType}");
      print("  - Stack trace: $stackTrace");
      
      
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
        error: errorMessage, 
        summary: errorMessage, 
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

  
  Future<void> _handleStreamingResponse(String query, String? imageUrl, QuerySession initialSession, List<Map<String, dynamic>> conversationHistory) async {
    print("🔥🔥🔥 _handleStreamingResponse CALLED");
    print("🔥🔥🔥 Query: $query");
    print("🔥🔥🔥 SessionId: ${initialSession.sessionId}"); 
    print("🔥🔥🔥 Conversation history length: ${conversationHistory.length}");
    
   
    final sessionId = initialSession.sessionId;
    
    try {
      
      final generatedChatId = _generateChatId();
      final generatedMessageId = _generateMessageId();
      
      
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
      
      
      requestBody["query"] = query;
      requestBody["conversationHistory"] = conversationHistory;
      
      if (imageUrl != null) {
        requestBody["imageUrl"] = imageUrl;
      }
      
      print("🔥🔥🔥 SENDING STREAMING REQUEST...");
      print("🔥🔥🔥 Request body: $requestBody");
      print("🔥🔥🔥 Endpoint: /chat?stream=true");
      
      
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
        
        
        final errorMessage = "Connection timeout. Please check:\n1. Server is running\n2. Network connection\n3. Try again";
        final errorSession = initialSession.copyWith(
          summary: errorMessage,
          isStreaming: false,
          isParsing: false,
          error: "Connection timeout", 
        );
        ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, errorSession);
        ref.read(agentStateProvider.notifier).state = AgentState.error; 
        return; 
      } catch (e, stackTrace) {
        print("🔥🔥🔥❌❌❌ ERROR GETTING STREAMING RESPONSE: $e");
        print("🔥🔥🔥❌❌❌ ERROR TYPE: ${e.runtimeType}");
        print("🔥🔥🔥❌❌❌ STACK: $stackTrace");
        
        
        final errorSession = initialSession.copyWith(
          summary: "Error connecting to server: ${e.toString()}",
          isStreaming: false,
          isParsing: false,
        );
        ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, errorSession);
        ref.read(agentStateProvider.notifier).state = AgentState.completed;
        return; 
      }
      
      
      if (_activeSessionId != null) {
        print("⚠️ WARNING: Active stream exists for session: $_activeSessionId, starting new stream");
        _activeSessionId = null; // Clear old tracking
      }
      
      
      _activeSessionId = sessionId;
      
      
      _processedEventIds[sessionId] = <String>{};
      
      String buffer = '';
      String accumulatedText = ''; 
      
      
      try {
        await for (var chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        
        
        if (lines.isNotEmpty) {
          buffer = lines.removeLast();
        } else {
          buffer = '';
        }

        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty) continue;
          
          
          if (line.startsWith(':')) {
            continue; 
          }
          
          
          if (!line.startsWith('data: ')) {
           
            try {
              final jsonData = jsonDecode(line) as Map<String, dynamic>;
              

              final finalSummary = jsonData['summary']?.toString() ?? accumulatedText;
              final finalAnswer = jsonData['answer']?.toString() ?? finalSummary; // ✅ CRITICAL: Extract full answer
              final sections = jsonData['sections'] as List<dynamic>? ?? [];
              final sources = jsonData['sources'] as List<dynamic>? ?? [];
              final followUpSuggestions = jsonData['followUpSuggestions'] as List<dynamic>? ?? [];
              final cardsByDomain = jsonData['cards'] as Map<String, dynamic>?;
              final destinationImages = (jsonData['destination_images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              
              
              final completeSession = initialSession.copyWith(
                summary: finalSummary,
                answer: finalAnswer, 
                sections: sections.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                sources: sources.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                followUpSuggestions: followUpSuggestions.map((f) => f.toString()).toList(),
                cardsByDomain: cardsByDomain != null ? Map<String, dynamic>.from(cardsByDomain) : null,
                destinationImages: destinationImages,
                isStreaming: false,
                isParsing: false,
                isFinalized: true, 
              );
              
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, completeSession);
              ref.read(agentStateProvider.notifier).state = AgentState.completed;
              
              return; 
            } catch (e) {
              if (kDebugMode) {
                debugPrint('⚠️ Failed to parse non-SSE line as JSON: $e');
              }
              continue; 
            }
          }

          try {
            final jsonStr = line.substring(6); 
            if (jsonStr.trim() == '[DONE]') {
              continue;
            }
            
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type'] as String?;
            
            
            final eventId = data['eventId'] as String?;
            final eventSessionId = data['sessionId'] as String?;
            
            
            if (eventId != null) {
              
              String dedupeKey = eventId;
              if (type == 'updateBlock') {
                final blockId = data['blockId'] as String?;
                if (blockId != null) {
                  dedupeKey = '${eventSessionId ?? sessionId}_${blockId}_$eventId';
                }
              } else {
                
                dedupeKey = '${eventSessionId ?? sessionId}_$eventId';
              }
              
              final processedIds = _processedEventIds[sessionId] ?? <String>{};
              if (processedIds.contains(dedupeKey)) {
                if (kDebugMode) {
                  debugPrint('⚠️ Duplicate event ignored: eventId=$eventId, type=$type, sessionId=$eventSessionId');
                }
                continue; 
              }
              
              
              processedIds.add(dedupeKey);
              _processedEventIds[sessionId] = processedIds;
            }

            
            if (type == 'block') {
              final block = data['block'] as Map<String, dynamic>?;
              if (block != null) {
                final blockType = block['type'] as String?;
                final blockData = block['data'];
                
                
                if (blockType == 'text' && blockData is String) {
                  final textContent = blockData as String;
                  
                 
                  if (textContent.startsWith('💭')) {
                    
                    final reasoningText = textContent.substring(1).trim();
                    
                    
                    final currentSessions = ref.read(sessionHistoryProvider);
                    final currentSession = currentSessions.firstWhere(
                      (s) => s.sessionId == sessionId,
                      orElse: () => initialSession,
                    );
                    
                    
                    final updatedReasoningSteps = [
                      ...currentSession.reasoningSteps,
                      reasoningText,
                    ];
                    
                    
                    final partialSession = currentSession.copyWith(
                      reasoningSteps: updatedReasoningSteps,
                      isStreaming: true, 
                      isFinalized: false,
                    );
                    
                    
                    ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                    
                    
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
                    
                    accumulatedText = textContent;
                    
                   
                    final currentSessions = ref.read(sessionHistoryProvider);
                    final currentSession = currentSessions.firstWhere(
                      (s) => s.sessionId == sessionId,
                      orElse: () => initialSession,
                    );
                    
                    
                    final partialSession = currentSession.copyWith(
                      summary: accumulatedText,
                      isStreaming: true,
                      isFinalized: false,
                      hasReceivedFirstChunk: true, 
                    );
                    ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                  }
                }
                
                
                if (blockType == 'source' && blockData is List) {
                  
                  final newSources = (blockData as List<dynamic>)
                      .map((s) => Map<String, dynamic>.from(s as Map<String, dynamic>))
                      .toList();
                  
                  
                  final currentSessions = ref.read(sessionHistoryProvider);
                  final currentSession = currentSessions.firstWhere(
                    (s) => s.sessionId == sessionId,
                    orElse: () => initialSession,
                  );
                  
                  
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
              
              final sectionData = data['section'] as Map<String, dynamic>?;
              if (sectionData != null) {
                final currentSessions = ref.read(sessionHistoryProvider);
                final currentSession = currentSessions.firstWhere(
                  (s) => s.sessionId == sessionId,
                  orElse: () => initialSession,
                );
                
               
                final existingSections = currentSession.sections ?? [];
                final newSection = Map<String, dynamic>.from(sectionData);
                

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
              
              final patch = data['patch'] as List<dynamic>?;
              
              
              if (patch != null && patch.isNotEmpty) {
                for (final op in patch) {
                  if (op is Map && op['op'] == 'replace' && op['path'] == '/data') {
                    final newValue = op['value'];
                    if (newValue is String && newValue.isNotEmpty) {
                      
                      final oldLength = accumulatedText.length;
                      accumulatedText = newValue; 
                      final delta = accumulatedText.substring(oldLength); // Extract new chunk
                      
                      
                      final currentSessions = ref.read(sessionHistoryProvider);
                      final currentSession = currentSessions.firstWhere(
                        (s) => s.sessionId == sessionId,
                        orElse: () => initialSession,
                      );
                      
                      // ✅ HISTORY MODE GUARD: Never transition finalized sessions (they're read-only history)
                      if (currentSession.isFinalized) {
                        if (kDebugMode) {
                          debugPrint('🔒 HISTORY MODE: Ignoring streaming update for finalized session: $sessionId');
                        }
                        continue; // Skip this update - finalized sessions are immutable
                      }
                      
                      if (currentSession.phase == QueryPhase.searching) {
                        
                        ref.read(sessionStreamProvider.notifier).initialize(sessionId);
                        
                        
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
              continue; 
            } else if (type == 'researchProgress') {
              
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
              
              continue; 
            } else if (type == 'researchComplete') {
              
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              
              final partialSession = currentSession.copyWith(
                researchStep: null,
                maxResearchSteps: null,
                currentAction: null,
                isStreaming: true,
                isFinalized: false,
              );
              ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
              
              continue; 
            } else if (type == 'start') {
              
              continue; 
            }

            
            if (type == 'verdict') {
              
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
              
              
              final firstSentence = data['data']?.toString() ?? '';
              if (firstSentence.isNotEmpty) {
                accumulatedText = firstSentence;
                

                final partialSession = currentSession.copyWith(
                  summary: accumulatedText, 
                  isStreaming: true,
                  isFinalized: false, 
                );
                ref.read(sessionHistoryProvider.notifier).updateSessionById(sessionId, partialSession);
                
                if (kDebugMode) {
                  debugPrint('📝 Received verdict (first sentence): $firstSentence');
                }
              }
            } else if (type == 'message') {
             
              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              if (currentSession.isFinalized) {
               
                if (kDebugMode) {
                  debugPrint('⚠️ Ignoring message event - session is finalized');
                }
                continue; 
              }
              
              
              final chunk = data['data']?.toString() ?? '';
              if (chunk.isNotEmpty) {
                accumulatedText += chunk;
                
                // ✅ HISTORY MODE: Phase transitions are already blocked by finalized check above (line 1144)
                // This ensures finalized sessions never enter 'searching' or 'answering' phases
                if (currentSession.phase == QueryPhase.searching) {
                  // Initialize stream controller
                  ref.read(sessionStreamProvider.notifier).initialize(sessionId);
                  
                  
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
                
               
                ref.read(sessionStreamProvider.notifier).addChunk(chunk);
                
                if (kDebugMode) {
                  debugPrint('📝 Received message chunk (${chunk.length} chars), total: ${accumulatedText.length}');
                }
              }
            } else if (type == 'summary') {
              
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
              
              
              final summary = data['summary']?.toString();
              final intent = data['intent']?.toString();
              final cardType = data['cardType']?.toString();
              
              if (summary != null && summary.isNotEmpty) {
                accumulatedText = summary; 
                
              }

              
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
              
              if (_activeSessionId == sessionId) {
                _activeSessionId = null;
              }
              
          
              final endData = data;
             
              final endSummary = endData['summary']?.toString() ?? '';
              final endAnswer = endData['answer']?.toString() ?? '';
              
              final finalSummary = (accumulatedText.length > endSummary.length) 
                  ? accumulatedText 
                  : (endSummary.isNotEmpty ? endSummary : accumulatedText);
              final finalAnswer = (accumulatedText.length > endAnswer.length)
                  ? accumulatedText
                  : (endAnswer.isNotEmpty ? endAnswer : accumulatedText);
              final sections = endData['sections'] as List<dynamic>? ?? [];
              final endEventSources = endData['sources'] as List<dynamic>? ?? [];
              

              final currentSessions = ref.read(sessionHistoryProvider);
              final currentSession = currentSessions.firstWhere(
                (s) => s.sessionId == sessionId,
                orElse: () => initialSession,
              );
              
              
              final accumulatedSources = currentSession.sources;
              final endEventSourcesList = (endEventSources ?? []).map((s) => Map<String, dynamic>.from(s as Map<String, dynamic>)).toList();
              
              
              final sourceUrls = <String>{};
              final mergedSources = <Map<String, dynamic>>[];
              
              
              for (final source in accumulatedSources) {
                final url = (source['url'] ?? source['link'] ?? '').toString();
                if (url.isNotEmpty && !sourceUrls.contains(url)) {
                  sourceUrls.add(url);
                  mergedSources.add(Map<String, dynamic>.from(source));
                }
              }
              
              
              for (final source in endEventSourcesList) {
                final url = (source['url'] ?? source['link'] ?? '').toString();
                if (url.isNotEmpty && !sourceUrls.contains(url)) {
                  sourceUrls.add(url);
                  mergedSources.add(source);
                }
              }
              
              final sources = mergedSources;
              final followUpSuggestions = endData['followUpSuggestions'] as List<dynamic>? ?? [];
              
              
              Map<String, dynamic>? cardsByDomain;
              List<Map<String, dynamic>> allCards = [];
              
              
              if (endData['widgets'] != null && endData['widgets'] is List) {
                final widgets = (endData['widgets'] as List).cast<Map<String, dynamic>>();
                
                
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
              
              
              final scenario = endData['scenario'] as String?;
              final uiDecision = endData['uiDecision'] as Map<String, dynamic>?;
              
              
              final allImages = await compute(_aggregateImagesWrapper, {
                'destinationImages': destinationImages,
                'cards': allCards,
                'results': [],
              });
              
              
              ref.read(sessionStreamProvider.notifier).close();
              
              final completeSession = currentSession.copyWith(
                summary: finalSummary,
                answer: finalAnswer, 
                sections: sections.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                sources: sources.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
                followUpSuggestions: followUpSuggestions.map((f) => f.toString()).toList(),
                cardsByDomain: cardsByDomain != null ? Map<String, dynamic>.from(cardsByDomain) : null,
                cards: allCards, 
                scenario: scenario, 
                uiDecision: uiDecision != null ? Map<String, dynamic>.from(uiDecision) : null, // ✅ ARCHITECTURE FIX: Backend UI decision
                destinationImages: destinationImages,
                videos: videos.isNotEmpty ? videos.map((v) => Map<String, dynamic>.from(v as Map)).toList() : null,
                mapPoints: mapPoints.isNotEmpty ? mapPoints.map((m) => Map<String, dynamic>.from(m as Map)).toList() : null,
                allImages: allImages,
                phase: QueryPhase.done, 
                isStreaming: false, 
                isParsing: false, 
                isFinalized: true, 
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
        } 
      } catch (streamError, streamStackTrace) {
        
        print("🔥🔥🔥 STREAM ERROR: $streamError");
        print("🔥🔥🔥 STREAM ERROR TYPE: ${streamError.runtimeType}");
        print("🔥🔥🔥 STREAM STACK: $streamStackTrace");
        
        
        if (_activeSessionId == sessionId) {
          _activeSessionId = null;
          print("🔥🔥🔥 Stream tracking cleared due to error");
        }
        
        
        if (streamError.toString().contains('Connection closed') || 
            streamError.toString().contains('ClientException')) {
          print("🔥🔥🔥 Connection was closed by server or client");
          
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
        rethrow; 
      } finally {
        
        if (_activeSessionId == sessionId) {
          print("⚠️ WARNING: Stream tracking still active after loop exit - clearing");
          _activeSessionId = null;
        }
      }
    } catch (e, stackTrace) {
      
      print("🔥🔥🔥 CRITICAL STREAMING ERROR: $e");
      print("🔥🔥🔥 STACK TRACE: $stackTrace");
      
      
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
        error: errorMessage, 
        summary: errorMessage, 
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

  
  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9999 - 1000) * (DateTime.now().microsecond / 1000000)).round()}';
  }

  
  String _generateChatId() {
    return 'chat_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9999 - 1000) * (DateTime.now().microsecond / 1000000)).round()}';
  }

  
  List<List<String>> _convertConversationHistoryToHistory(
    List<Map<String, dynamic>> conversationHistory,
  ) {
    final history = <List<String>>[];
    
    for (final item in conversationHistory) {
      
      if (item['query'] != null && item['query'].toString().isNotEmpty) {
        history.add(['human', item['query'].toString()]);
      }
      
      
      final summary = item['summary']?.toString() ?? item['answer']?.toString();
      if (summary != null && summary.isNotEmpty) {
        history.add(['assistant', summary]);
      }
    }
    
    return history;
  }
}


final agentControllerProvider =
    StateNotifierProvider<AgentController, void>(
  (ref) {
    
    ref.keepAlive();
    return AgentController(ref);
  },
);


List<Map<String, dynamic>> _parseTextWithLocationsWrapper(Map<String, dynamic> input) {
  return fastParseTextWithLocations(
    input['text'] as String,
    (input['locationCards'] as List).cast<Map<String, dynamic>>(),
  );
}


List<String> _aggregateImagesWrapper(Map<String, dynamic> input) {
  final allImages = <String>[];
  final destinationImages = (input['destinationImages'] as List?)?.cast<String>() ?? [];
  final cards = (input['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final results = (input['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  
  
  allImages.addAll(destinationImages.where((img) => img.isNotEmpty && img.startsWith('http')));
  
  
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



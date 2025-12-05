import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'CacheService.dart';

/// Helper function for caching detail API responses
/// Used across all detail screens (hotels, products, movies, etc.)
Future<Map<String, dynamic>?> _getCachedDetailResponse(String cacheKey) async {
  return await CacheService.get(cacheKey);
}

Future<void> _setCachedDetailResponse(String cacheKey, Map<String, dynamic> data, Duration expiry) async {
  await CacheService.set(cacheKey, data, expiry: expiry, query: cacheKey);
}

class AgentService {
  // ✅ Perplexity-style persistent cache (initialized on first use)
  static bool _cacheInitialized = false;
  
  // Initialize cache service
  static Future<void> _ensureCacheInitialized() async {
    if (!_cacheInitialized) {
      await CacheService.initialize();
      await CacheService.cleanExpired(); // Clean expired entries on startup
      _cacheInitialized = true;
    }
  }

  // 🔧 Automatically detects correct base URL for your setup
  static String get baseUrl {
    // For Android emulator → connects to host machine
    if (Platform.isAndroid) {
      return "http://10.0.2.2:4000";
    }
    // For iOS simulator → host machine
    else if (Platform.isIOS) {
      return "http://127.0.0.1:4000";
    }
    // For web or desktop (Flutter web / macOS / Windows)
    else {
      return "http://localhost:4000";
    }
  }

  /// Calls the /api/autocomplete endpoint for search suggestions
  static Future<List<String>> getAutocompleteSuggestions(String query) async {
    if (query.trim().length < 2) {
      return [];
    }

    try {
      final url = Uri.parse('$baseUrl/api/autocomplete');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final suggestions = data['suggestions'] as List<dynamic>?;
        return suggestions?.map((s) => s.toString()).toList() ?? [];
      } else {
        print('❌ Autocomplete API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching autocomplete suggestions: $e');
      return [];
    }
  }

  /// Calls the /api/autocomplete/location endpoint for location autocomplete
  /// Returns a list of location suggestions with description and place_id
  static Future<List<Map<String, dynamic>>> getLocationAutocomplete(String query) async {
    if (query.trim().length < 2) {
      return [];
    }

    try {
      final url = Uri.parse('$baseUrl/api/autocomplete/location');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final predictions = data['predictions'] as List<dynamic>?;
        if (predictions != null) {
          return predictions.map((p) {
            final pred = p as Map<String, dynamic>;
            final structured = pred['structured_formatting'] as Map<String, dynamic>?;
            return <String, dynamic>{
              'description': pred['description'] as String? ?? '',
              'place_id': pred['place_id'] as String? ?? '',
              'main_text': structured?['main_text'] as String? ?? '',
              'secondary_text': structured?['secondary_text'] as String? ?? '',
            };
          }).toList();
        }
        return [];
      } else {
        print('❌ Location Autocomplete API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching location autocomplete: $e');
      return [];
    }
  }

  /// Get movie details from TMDB (cached for 14 days - movie data changes slowly)
  static Future<Map<String, dynamic>> getMovieDetails(int movieId) async {
    try {
      // ✅ CACHE: Check cache first
      final cacheKey = CacheService.generateCacheKey('movie-details-$movieId');
      final cachedData = await _getCachedDetailResponse(cacheKey);
      if (cachedData != null) {
        print('✅ Movie details cache HIT for movie ID: $movieId');
        return cachedData;
      }
      
      print('❌ Movie details cache MISS for movie ID: $movieId');
    final url = Uri.parse('$baseUrl/api/movies/$movieId');
    final response = await http.get(url);

    if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // ✅ CACHE: Store in cache (14 days - movie data is very stable)
        await _setCachedDetailResponse(cacheKey, data, const Duration(days: 14));
        return data;
      } else {
        throw Exception('Failed to fetch movie details: ${response.statusCode}');
  }
    } catch (e) {
      print('❌ Error fetching movie details: $e');
      rethrow;
    }
  }

  /// Get movie credits (cast and crew) - cached for 14 days
  static Future<Map<String, dynamic>> getMovieCredits(int movieId) async {
    try {
      // ✅ CACHE: Check cache first
      final cacheKey = CacheService.generateCacheKey('movie-credits-$movieId');
      final cachedData = await _getCachedDetailResponse(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }
      
    final url = Uri.parse('$baseUrl/api/movies/$movieId/credits');
    final response = await http.get(url);

    if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // ✅ CACHE: Store in cache (14 days)
        await _setCachedDetailResponse(cacheKey, data, const Duration(days: 14));
        return data;
      } else {
        throw Exception('Failed to fetch movie credits: ${response.statusCode}');
  }
    } catch (e) {
      print('❌ Error fetching movie credits: $e');
      rethrow;
    }
  }

  /// Get movie videos (trailers) - cached for 14 days
  static Future<Map<String, dynamic>> getMovieVideos(int movieId) async {
    try {
      // ✅ CACHE: Check cache first
      final cacheKey = CacheService.generateCacheKey('movie-videos-$movieId');
      final cachedData = await _getCachedDetailResponse(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }
      
    final url = Uri.parse('$baseUrl/api/movies/$movieId/videos');
    final response = await http.get(url);

    if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // ✅ CACHE: Store in cache (14 days)
        await _setCachedDetailResponse(cacheKey, data, const Duration(days: 14));
        return data;
      } else {
        throw Exception('Failed to fetch movie videos: ${response.statusCode}');
  }
    } catch (e) {
      print('❌ Error fetching movie videos: $e');
      rethrow;
    }
  }

  /// Get movie reviews - cached for 7 days (reviews update slowly)
  static Future<Map<String, dynamic>> getMovieReviews(int movieId, {int page = 1}) async {
    try {
      // ✅ CACHE: Check cache first (include page in cache key)
      final cacheKey = CacheService.generateCacheKey('movie-reviews-$movieId-page$page');
      final cachedData = await _getCachedDetailResponse(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }
      
      final url = Uri.parse('$baseUrl/api/movies/$movieId/reviews?page=$page');
    final response = await http.get(url);

    if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // ✅ CACHE: Store in cache (7 days - reviews update slowly)
        await _setCachedDetailResponse(cacheKey, data, const Duration(days: 7));
        return data;
      } else {
        throw Exception('Failed to fetch movie reviews: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching movie reviews: $e');
      rethrow;
    }
  }

  /// Get person details (biography, etc.) - cached for 14 days (biography changes rarely)
  static Future<Map<String, dynamic>> getPersonDetails(int personId) async {
    try {
      // ✅ CACHE: Check cache first
      final cacheKey = CacheService.generateCacheKey('person-details-$personId');
      final cachedData = await _getCachedDetailResponse(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }
      
      final url = Uri.parse('$baseUrl/api/movies/person/$personId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // ✅ CACHE: Store in cache (14 days - biography changes rarely)
        await _setCachedDetailResponse(cacheKey, data, const Duration(days: 14));
        return data;
      } else {
        throw Exception('Failed to fetch person details: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching person details: $e');
      rethrow;
    }
  }

  /// Get movie reviews summary
  static Future<String> getMovieReviewsSummary(int movieId, List<dynamic> reviews, String? movieTitle) async {
    try {
      final url = Uri.parse('$baseUrl/api/movies/$movieId/reviews/summary');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reviews': reviews,
          'movieTitle': movieTitle,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['summary']?.toString() ?? 'Unable to generate summary.';
      } else {
        throw Exception('Failed to fetch review summary: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching review summary: $e');
      rethrow;
    }
  }

  /// Get movie images
  /// Get movie images - cached for 14 days (images don't change)
  static Future<Map<String, dynamic>> getMovieImages(int movieId) async {
    try {
      // ✅ CACHE: Check cache first
      final cacheKey = CacheService.generateCacheKey('movie-images-$movieId');
      final cachedData = await _getCachedDetailResponse(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }
      
    final url = Uri.parse('$baseUrl/api/movies/$movieId/images');
    final response = await http.get(url);

    if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // ✅ CACHE: Store in cache (14 days - images don't change)
        await _setCachedDetailResponse(cacheKey, data, const Duration(days: 14));
        return data;
      } else {
        throw Exception('Failed to fetch movie images: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching movie images: $e');
      rethrow;
    }
  }

  /// Calls the /api/agent endpoint on your Node backend
  /// Returns regular JSON response for non-streaming queries
  /// 
  /// [previousContext] - Optional context from previous session (intent, cardType, slots, sessionId)
  /// [lastFollowUp] - The last follow-up question that was clicked (for deduplication)
  /// [parentQuery] - The original query that generated the follow-ups
  static Future<Map<String, dynamic>> askAgent(
    String query, {
    bool stream = false,
    List<Map<String, dynamic>>? conversationHistory,
    Map<String, dynamic>? previousContext,
    String? lastFollowUp,
    String? parentQuery,
    bool useCache = true, // ✅ Allow bypassing cache if needed
  }) async {
    // ✅ Perplexity-style persistent caching
    if (!stream && useCache) {
      await _ensureCacheInitialized();
      
      // Generate smart cache key (query + context hash)
      final cacheKey = CacheService.generateCacheKey(
        query,
        conversationHistory: conversationHistory,
        context: previousContext,
      );
      
      // Check persistent cache
      final cachedResponse = await CacheService.get(cacheKey);
      if (cachedResponse != null) {
        final expiry = CacheService.getSmartExpiry(query);
        if (expiry == Duration.zero) {
          print('⚠️ Cache returned but query type should not be cached - this is a bug');
        }
        return cachedResponse;
      }
      
      // Log why cache missed
      final expiry = CacheService.getSmartExpiry(query);
      if (expiry == Duration.zero) {
        print('⏭️ Cache SKIP for query: "$query" (query type: no cache)');
      } else {
        print('❌ Cache MISS for query: "$query" (will cache for ${expiry.inMinutes} minutes)');
      }
    }
    
    final url = stream 
        ? Uri.parse('$baseUrl/api/agent?stream=true')
        : Uri.parse('$baseUrl/api/agent');
    
    print('🔍 Calling Agent API at $url with query: "$query" (stream: $stream)');
    if (previousContext != null) {
      print('📦 Sending context: intent=${previousContext['intent']}, cardType=${previousContext['cardType']}, sessionId=${previousContext['sessionId']}');
    }

    try {
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      if (stream) {
        request.headers['Accept'] = 'text/event-stream';
      }
      
      // Build request body with context support
      final body = <String, dynamic>{
        "query": query,
        "conversationHistory": conversationHistory ?? [],
      };
      
      // ✅ FOLLOW-UP PATCH: Add lastFollowUp and parentQuery
      if (lastFollowUp != null && lastFollowUp.isNotEmpty) {
        body['lastFollowUp'] = lastFollowUp;
      }
      if (parentQuery != null && parentQuery.isNotEmpty) {
        body['parentQuery'] = parentQuery;
      }
      
      // ✅ STEP 9: Add context fields if provided
      if (previousContext != null) {
        if (previousContext['sessionId'] != null) {
          body['sessionId'] = previousContext['sessionId'];
        }
        if (previousContext['conversationId'] != null) {
          body['conversationId'] = previousContext['conversationId'];
        }
        if (previousContext['userId'] != null) {
          body['userId'] = previousContext['userId'];
        }
        // Context object for backend to understand follow-up state
        if (previousContext['intent'] != null || 
            previousContext['cardType'] != null || 
            previousContext['slots'] != null) {
          body['context'] = {
            'intent': previousContext['intent'],
            'cardType': previousContext['cardType'],
            'slots': previousContext['slots'],
          };
        }
      }
      
      request.body = jsonEncode(body);

      final response = await request.send();

    if (response.statusCode == 200) {
        if (stream && response.headers['content-type']?.contains('text/event-stream') == true) {
          // Handle streaming response (don't cache)
          print('✅ Agent API streaming response');
          return await _parseStreamingResponse(response);
        } else {
          // Handle regular JSON response
          final responseBody = await response.stream.bytesToString();
          final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
          
          // ✅ Perplexity-style persistent caching with smart expiry
          if (useCache) {
            await _ensureCacheInitialized();
            final cacheKey = CacheService.generateCacheKey(
              query,
              conversationHistory: conversationHistory,
              context: previousContext,
            );
            // Pass query for smart expiry calculation
            await CacheService.set(cacheKey, responseData, query: query);
          }
          
          print('✅ Agent API success');
          return responseData;
        }
      } else {
        final errorBody = await response.stream.bytesToString();
        print('❌ Agent API returned ${response.statusCode}');
        throw Exception(
            "Agent API failed: ${response.statusCode} $errorBody");
      }
    } on SocketException catch (e) {
      print('⚠️ Connection error: $e');
      throw Exception(
          'Agent API connection failed: ${e.message} (Check if Node server is running on port 4000)');
    } catch (e) {
      print('⚠️ Unknown error calling Agent API: $e');
      throw Exception('Unexpected error: $e');
  }
  }

  /// Parse streaming Server-Sent Events (SSE) response
  static Future<Map<String, dynamic>> _parseStreamingResponse(http.StreamedResponse response) async {
    String fullAnswer = '';
    final stream = response.stream.transform(utf8.decoder);
    
    await for (var chunk in stream) {
      final lines = chunk.split('\n');
      
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || !line.startsWith('data: ')) continue;
        
        try {
          final jsonStr = line.substring(6); // Remove "data: " prefix
          final data = jsonDecode(jsonStr);
          
          if (data['type'] == 'message' && data['data'] != null) {
            fullAnswer += data['data'];
          } else if (data['type'] == 'end') {
            // Stream complete
            return {
              'intent': data['intent'] ?? 'answer',
              'summary': data['summary'] ?? fullAnswer,
              'answer': data['summary'] ?? fullAnswer,
              'results': [],
              'products': []
            };
          } else if (data['type'] == 'error') {
            throw Exception(data['error'] ?? 'Streaming error');
          }
        } catch (e) {
          // Skip malformed JSON
          continue;
        }
      }
    }
    
    // Fallback: return accumulated answer
    return {
      'intent': 'answer',
      'summary': fullAnswer.isNotEmpty ? fullAnswer : 'No answer received',
      'answer': fullAnswer.isNotEmpty ? fullAnswer : 'No answer received',
      'sources': [],
      'results': [],
      'products': []
    };
  }

  /// Stream agent response for real-time UI updates
  static Stream<String> streamAgentResponse(String query) async* {
    final url = Uri.parse('$baseUrl/api/agent?stream=true');
    print('🌊 Starting streaming request to $url');

    try {
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      request.body = jsonEncode({"query": query});

      final response = await request.send();

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception("Agent API failed: ${response.statusCode} $errorBody");
      }

      final stream = response.stream.transform(utf8.decoder);
      String buffer = '';

      await for (var chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        
        // Keep the last line (which might be incomplete) in buffer
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
            
            final data = jsonDecode(jsonStr);

            if (data['type'] == 'message' && data['data'] != null) {
              yield data['data']; // Emit each token
            } else if (data['type'] == 'end') {
              // Stream complete - sources will be included in the end event
              // but we don't yield them here, they're handled separately
              return;
            } else if (data['type'] == 'error') {
              throw Exception(data['error'] ?? 'Streaming error');
            }
          } catch (e) {
            // Skip malformed JSON
            print('⚠️ Failed to parse SSE line: $line, error: $e');
            continue;
          }
        }
      }
      
      // Process any remaining buffer content
      if (buffer.trim().isNotEmpty && buffer.startsWith('data: ')) {
        try {
          final jsonStr = buffer.substring(6).trim();
          if (jsonStr != '[DONE]') {
            final data = jsonDecode(jsonStr);
            if (data['type'] == 'message' && data['data'] != null) {
              yield data['data'];
            }
          }
        } catch (e) {
          // Ignore parsing errors for final buffer
        }
      }
    } on SocketException catch (e) {
      throw Exception('Agent API connection failed: ${e.message}');
    } catch (e) {
      throw Exception('Streaming error: $e');
}
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, compute;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../isolates/text_parsing_isolate.dart' show parseAnswerIsolate, parseAgentResponseIsolate, ParsingInput, ParsedContent;
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Product.dart';
import '../services/AgentService.dart';
import '../widgets/AnswerHeaderRow.dart';
import '../widgets/GoogleMapWidget.dart';
import '../widgets/HotelMapView.dart';
import '../widgets/PerplexityTypingAnimation.dart';
import 'FullScreenMapScreen.dart';
import '../services/GeocodingService.dart';
import 'ProductDetailScreen.dart';
import 'ShoppingGridScreen.dart';
import 'HotelDetailScreen.dart';
import 'HotelResultsScreen.dart';
import 'MovieDetailScreen.dart';

// Extension for capitalizing strings
extension StringCasingExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

// 🔹 Utility to clean markdown and numbered list artifacts
String cleanMarkdown(String text) {
  return text
      .replaceAll(RegExp(r'\*\*'), '')        // remove **bold**
      .replaceAll(RegExp(r'[_~>`#-]'), '')    // remove markdown symbols
      .replaceAll(RegExp(r'[0-9]+\.\s*'), '') // remove list numbers
      .replaceAll(RegExp(r'\s{2,}'), ' ')     // normalize spaces
      .trim();
}

// ✅ Top-level variable for parsing trigger (prevents multiple simultaneous parses)
bool _globalParsingTriggered = false;

class QuerySession {
  final String query;
  final List<Product> products;
  final List<Map<String, dynamic>> hotelResults;
  final String resultType; // "shopping", "hotel", "answer", "image", "restaurants", etc.
  final bool isLoading;
  final String? summary; // AI-generated summary
  final List<Map<String, dynamic>> rawResults; // For image, restaurants, etc.
  final bool isStreaming; // Whether this query is currently streaming
  final List<Map<String, dynamic>> sources; // Sources for answer queries
  final List<String> followUpSuggestions; // AI-generated follow-up suggestions
  final List<Map<String, dynamic>> locationCards; // Location cards for answer queries (Perplexity-style)
  final List<String> destinationImages; // Destination images for initial overview (Perplexity-style)
  // ✅ FIX: Store backend values for conversation history
  final String? intent;
  final String? cardType;
  final List<Map<String, dynamic>> cards;
  // ✅ Perplexity-style: Hotel sections and map
  final List<Map<String, dynamic>>? hotelSections; // [{title: "Luxury hotels", items: [...]}, ...]
  final List<Map<String, dynamic>>? hotelMapPoints; // [{lat, lng, name, rating}, ...]
  // ✅ Caching for performance optimization
  final String? cachedSummary; // Cached generated summary
  final List<Map<String, dynamic>>? cachedParsedLocations; // Cached parsed location segments
  final ParsedContent? cachedParsing; // ✅ PHASE 3: Cached parsed content from isolate
  // ✅ PATCH 4: Flag to prevent duplicate parsing
  final bool? isParsing; // Whether this session is currently being parsed

  QuerySession({
    required this.query,
    required this.products,
    this.hotelResults = const [],
    this.resultType = "shopping",
    this.isLoading = false,
    this.summary,
    this.rawResults = const [],
    this.isStreaming = false,
    this.sources = const [],
    this.followUpSuggestions = const [],
    this.locationCards = const [],
    this.destinationImages = const [],
    this.intent,
    this.cardType,
    this.cards = const [],
    this.hotelSections,
    this.hotelMapPoints,
    this.cachedSummary,
    this.cachedParsedLocations,
    this.cachedParsing,
    this.isParsing,
  });

  QuerySession copyWith({
    String? query,
    List<Product>? products,
    List<Map<String, dynamic>>? hotelResults,
    String? resultType,
    bool? isLoading,
    String? summary,
    List<Map<String, dynamic>>? rawResults,
    bool? isStreaming,
    List<Map<String, dynamic>>? sources,
    List<String>? followUpSuggestions,
    List<Map<String, dynamic>>? locationCards,
    List<String>? destinationImages,
    String? intent,
    String? cardType,
    List<Map<String, dynamic>>? cards,
    List<Map<String, dynamic>>? hotelSections,
    List<Map<String, dynamic>>? hotelMapPoints,
    String? cachedSummary,
    List<Map<String, dynamic>>? cachedParsedLocations,
    ParsedContent? cachedParsing,
    bool? isParsing,
  }) {
    return QuerySession(
      query: query ?? this.query,
      products: products ?? this.products,
      hotelResults: hotelResults ?? this.hotelResults,
      resultType: resultType ?? this.resultType,
      isLoading: isLoading ?? this.isLoading,
      summary: summary ?? this.summary,
      rawResults: rawResults ?? this.rawResults,
      isStreaming: isStreaming ?? this.isStreaming,
      sources: sources ?? this.sources,
      followUpSuggestions: followUpSuggestions ?? this.followUpSuggestions,
      locationCards: locationCards ?? this.locationCards,
      destinationImages: destinationImages ?? this.destinationImages,
      intent: intent ?? this.intent,
      cardType: cardType ?? this.cardType,
      cards: cards ?? this.cards,
      hotelSections: hotelSections ?? this.hotelSections,
      hotelMapPoints: hotelMapPoints ?? this.hotelMapPoints,
      cachedSummary: cachedSummary ?? this.cachedSummary,
      cachedParsedLocations: cachedParsedLocations ?? this.cachedParsedLocations,
      cachedParsing: cachedParsing ?? this.cachedParsing,
      isParsing: isParsing ?? this.isParsing,
    );
  }
}

// ✅ Isolate functions for heavy computations (STEP 1)
String generateSummaryIsolate(Map<String, dynamic> hotelData) {
  // This will be called in an isolate - must be a top-level function
  // We'll move the logic here
  final name = (hotelData['name']?.toString() ?? '');
  final address = (hotelData['address']?.toString() ?? '');
  final location = (hotelData['location']?.toString() ?? '');
  final rating = (hotelData['rating'] is num) ? (hotelData['rating'] as num).toDouble() : 0.0;
  final reviewCount = (hotelData['reviewCount'] is int) ? hotelData['reviewCount'] as int : 0;
  final amenities = hotelData['amenities'] as List<dynamic>? ?? [];
  final description = (hotelData['description']?.toString() ?? '').trim();
  
  // ✅ PRIORITY 1: Use backend-generated description if available (from hotelDescriptionGenerator.ts)
  if (description.isNotEmpty && 
      description != 'No description available' && 
      description.length > 20) {
    return description;
  }
  
  // ✅ FALLBACK: Simplified version for isolate - full logic moved from _generatePerplexityStyleSummary
  if (rating >= 4.5) {
    return 'A ${rating >= 4.5 ? 4 : 3}-star luxury hotel${location.isNotEmpty ? ' in $location' : ''}';
  } else if (rating >= 4.0) {
    return 'A ${rating >= 4.0 ? 3 : 2}-star hotel${location.isNotEmpty ? ' in $location' : ''}';
  } else {
    return 'A modern property${location.isNotEmpty ? ' in $location' : ''}';
  }
}

List<Map<String, dynamic>> parseTextWithLocationsIsolate(Map<String, dynamic> data) {
  final text = data['text'] as String;
  final locationCards = (data['locationCards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  
  // Simplified parsing for isolate
  if (locationCards.isEmpty) {
    return [{'text': text, 'location': null}];
  }
  
  final List<Map<String, dynamic>> segments = [];
  final Set<String> shownCardTitles = {};
  
  // Simple matching - find location names in text
  for (final card in locationCards) {
    final title = (card['title']?.toString() ?? '').toLowerCase();
    if (text.toLowerCase().contains(title) && !shownCardTitles.contains(title)) {
      segments.add({'text': '', 'location': card});
      shownCardTitles.add(title);
    }
  }
  
  // Add remaining text
  if (segments.isEmpty) {
    segments.add({'text': text, 'location': null});
  }
  
  // Add all remaining cards
  for (final card in locationCards) {
    final title = (card['title']?.toString() ?? '').toLowerCase();
    if (!shownCardTitles.contains(title)) {
      segments.add({'text': '', 'location': card});
    }
  }
  
  return segments;
}

class ShoppingResultsScreen extends StatefulWidget {
  final String query;
  final String? imageUrl;

  const ShoppingResultsScreen({
    super.key,
    required this.query,
    this.imageUrl,
  });

  @override
  State<ShoppingResultsScreen> createState() => _ShoppingResultsScreenState();
}

class _ShoppingResultsScreenState extends State<ShoppingResultsScreen> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // ✅ STEP 3: Prevent rebuilds
  
  List<QuerySession> conversationHistory = [];
  // ✅ STEP 2: Cache for hotel summaries
  final Map<String, String> _hotelSummaryCache = {};
  // Map to store product links by product ID
  final Map<int, String> _productLinks = {};
  // Keeps track of expanded summaries per query index
  final Map<int, bool> _expandedSummaries = {};
  // ✅ PATCH B1: Stable animation controller map (prevents restart on scroll)
  final Map<String, bool> _hasAnimated = {};
  // ✅ PATCH C1: Preprocessed result cache (prevents heavy computation in build)
  Map<String, dynamic>? _processedResult;
  // Token queue for smooth streaming display
  Timer? _streamTimer;
  String _displayedText = ''; // What's currently displayed (for animation)
  String _targetText = ''; // What should be displayed (from stream)

  // Safe number extraction helper function
  double safeNumber(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    final str = value.toString().trim();
    if (str.isEmpty) return fallback;
    return double.tryParse(str) ?? fallback;
  }

  // Safe int extraction helper function
  int safeInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    final str = value.toString().trim();
    if (str.isEmpty) return fallback;
    return int.tryParse(str) ?? fallback;
  }

  String safeString(dynamic value, String fallback) {
    if (value == null) return fallback;
    final str = value.toString().trim();
    return str.isEmpty ? fallback : str;
  }

  // Check if movie is currently in theaters using backend flag
  bool _isMovieInTheaters(Map<String, dynamic> movie) {
    // Use the isInTheaters flag from backend (which uses TMDB's now_playing endpoint)
    return movie['isInTheaters'] == true;
  }
  final TextEditingController _followUpController = TextEditingController();
  final FocusNode _followUpFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _queryKeys = [];
  // ✅ PATCH E4: Debounce timer for follow-up input
  Timer? _followUpDebounce;

  // Hotel view mode: 'list' or 'map'
  String _hotelViewMode = 'list';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // register lifecycle listener
    print('ShoppingResultsScreen query: "${widget.query}"');
    // Create initial QuerySession
    final resultType = _detectResultType(widget.query);
    final initialSession = QuerySession(
      query: widget.query,
      products: [],
      hotelResults: [],
      resultType: resultType,
      isLoading: true,
    );
    conversationHistory.add(initialSession);
    _queryKeys.add(GlobalKey());
    _followUpController.addListener(() {
      print('Text changed: "${_followUpController.text}"');
    });
    _loadResultsForSession(0);
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ensure keyboard stays closed when coming back
      _followUpFocusNode.unfocus();
    }
    super.didChangeAppLifecycleState(state);
  }

  String _detectResultType(String query) {
    final lowerQuery = query.toLowerCase();
    final hotelKeywords = ['hotel', 'accommodation', 'stay', 'booking', 'resort', 'lodge', 'inn', 'hostel', 'motel', 'motels'];
    final shoppingKeywords = ['buy', 'shop', 'purchase', 'product', 'clothes', 'shoes', 'electronics', 'fashion'];
    
    // Check for informational/answer queries (obvious cases only)
    final answerPatterns = [
      RegExp(r'^(what|who|when|where|why|how|explain|define|tell)\b', caseSensitive: false),
      RegExp(r'\?$'), // Questions ending with ?
    ];
    
    for (final pattern in answerPatterns) {
      if (pattern.hasMatch(query.trim())) {
        return 'answer';
      }
    }
    
    for (String keyword in hotelKeywords) {
      if (lowerQuery.contains(keyword)) {
        return 'hotel';
      }
    }
    
    for (String keyword in shoppingKeywords) {
      if (lowerQuery.contains(keyword)) {
        return 'shopping';
      }
    }
    
    // For ambiguous queries (like "blue virgin islands"), don't pre-classify
    // Let the backend semantic classifier decide - default to shopping but backend will refine
    // This ensures location queries are correctly identified by the backend
    return 'shopping'; // Backend will refine this via semantic classifier
  }

  // Check if query might be an answer query (for streaming optimization)
  // IMPORTANT: Only detect OBVIOUS cases. Let backend semantic classifier handle ambiguous queries.
  // This is how ChatGPT/Perplexity work - they use AI to understand intent, not keyword matching.
  bool _mightBeAnswerQuery(String query) {
    return false; // ALWAYS let backend decide intent
  }

  // 🌊 Stream answer response for real-time token display (Perplexity-style)
  Future<void> _streamAnswerResponse(int sessionIndex, QuerySession session) async {
    try {
      // Initialize with empty summary to show loading state
      _displayedText = '';
      _targetText = '';
      setState(() {
        conversationHistory[sessionIndex] = session.copyWith(
          resultType: 'answer',
          isLoading: false, // Don't show spinner, show "Thinking..." text instead
          isStreaming: true,
          summary: '', // Start empty
          sources: [],
        );
      });
      
      // ✅ Update summary periodically with full target text
      // Let PerplexityTypingAnimation widget handle the smooth word-by-word animation
      _streamTimer?.cancel();
      _streamTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted || conversationHistory.length <= sessionIndex) {
          timer.cancel();
          return;
        }
        
        final session = conversationHistory[sessionIndex];
        // ✅ FIX: Update summary with FULL target text, let PerplexityTypingAnimation widget handle animation
        // This allows the widget to animate word-by-word smoothly
        if (_targetText.isNotEmpty && session.summary != _targetText) {
          if (mounted) {
            setState(() {
              conversationHistory[sessionIndex] =
                  conversationHistory[sessionIndex].copyWith(
                summary: _targetText, // Pass full text to widget for animation
                isStreaming: true,
                isLoading: false,
              );
            });
          }
        } else if (!session.isStreaming) {
          // Stop timer when streaming is complete
          timer.cancel();
        }
      });

      // Build conversation history for context (previous queries and answers)
      // Similar to ChatGPT/Perplexity: include all previous exchanges for context
      final List<Map<String, dynamic>> history = [];
      for (int i = 0; i < sessionIndex; i++) {
        final prevSession = conversationHistory[i];
        // Only include completed exchanges (both query and answer)
        if (prevSession.query.isNotEmpty && 
            prevSession.summary != null && 
            prevSession.summary!.isNotEmpty) {
          history.add({
            "query": prevSession.query,
            "summary": prevSession.summary ?? "",
            "intent": prevSession.resultType,    // <-- important
            "cardType": prevSession.resultType,  // <-- important
            "cards": prevSession.products.map((p) => {
              "title": p.title,
              "price": p.price,
              "rating": p.rating,
              "images": p.images,
              "source": p.source,
            }).toList(),
            "results": prevSession.rawResults,
          });
        }
      }
      print('📚 Sending ${history.length} previous exchanges for context (streaming)');
      
      final request = http.Request(
        'POST',
        Uri.parse('${AgentService.baseUrl}/api/agent?stream=true'),
      );
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        "query": session.query,
        "conversationHistory": history,
      });

      final response = await request.send();
      final stream = response.stream.transform(utf8.decoder);

      String buffer = '';
      String accumulatedAnswer = '';
      List<Map<String, dynamic>> sources = [];

      await for (final chunk in stream) {
        buffer += chunk;
        final lines = buffer.split(RegExp(r'\r?\n'));
        if (lines.isNotEmpty) {
          buffer = lines.removeLast(); // keep unfinished line
        } else {
          buffer = '';
        }

        for (String line in lines) {
          line = line.trim();
          if (!line.startsWith('data:')) continue;
          final jsonStr = line.substring(5).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

          try {
            final data = jsonDecode(jsonStr);
            final type = data['type'];

            switch (type) {
              case 'message':
                final token = data['data'] ?? '';
                if (token.isNotEmpty) {
                  accumulatedAnswer += token;
                  _targetText = accumulatedAnswer; // Update target for animation
                  debugPrint('📝 Token: "$token" | Total: ${accumulatedAnswer.length} | Displayed: ${_displayedText.length}');
                  // Don't update UI here - let the timer handle character-by-character animation
                }
                break;

              case 'correction':
                // Answer was regenerated to match location cards - replace the entire answer
                final correctedAnswer = data['data'] ?? '';
                if (correctedAnswer.isNotEmpty) {
                  accumulatedAnswer = correctedAnswer;
                  _targetText = correctedAnswer;
                  _displayedText = ''; // Reset displayed text to animate the correction
                  debugPrint('🔄 Answer corrected to match location cards');
                }
                break;

              case 'sources':
                sources = (data['data'] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                setState(() {
                  conversationHistory[sessionIndex] =
                      conversationHistory[sessionIndex].copyWith(sources: sources);
                });
                break;

              case 'products':
                // Handle products for shopping-related follow-ups
                final productsData = (data['data'] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                if (productsData.isNotEmpty) {
                  final List<Product> products = productsData.map<Product>((item) {
                    try {
                      return _mapShoppingResultToProduct(item);
                    } catch (e) {
                      print('Error mapping product from stream: $e');
                      return Product(
                        id: DateTime.now().millisecondsSinceEpoch,
                        title: 'Error loading product',
                        description: 'Unable to load product details',
                        price: 0.0,
                        source: 'Error',
                        rating: 0.0,
                        images: [],
                        variants: [],
                      );
                    }
                  }).toList();
                  
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          products: products,
                        );
                  });
                }
                break;

              case 'hotels':
                // Handle hotels for hotel-related follow-ups
                final hotelsData = (data['data'] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                if (hotelsData.isNotEmpty) {
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          hotelResults: hotelsData,
                        );
                  });
                }
                break;

              case 'flights':
                // Handle flights for flight-related follow-ups
                final flightsData = (data['data'] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                if (flightsData.isNotEmpty) {
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          rawResults: flightsData,
                        );
                  });
                }
                break;

              case 'restaurants':
                // Handle restaurants for restaurant-related follow-ups
                final restaurantsData = (data['data'] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                if (restaurantsData.isNotEmpty) {
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          rawResults: restaurantsData,
                        );
                  });
                }
                break;

              case 'destination_images':
                // Handle destination images for overview section (Perplexity-style)
                // print('🖼️ Received destination images event with ${data['data']?.length ?? 0} images');
                final imagesData = (data['data'] as List)
                    .map((e) => e.toString())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (imagesData.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && sessionIndex < conversationHistory.length) {
                      setState(() {
                        conversationHistory[sessionIndex] =
                            conversationHistory[sessionIndex].copyWith(
                              destinationImages: imagesData,
                            );
                      });
                    }
                  });
                }
                break;

              case 'locations':
                // Handle location cards for location-related answer queries
                print('📍 Received locations event with ${data['data']?.length ?? 0} location cards');
                final locationsData = (data['data'] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                print('📍 Parsed ${locationsData.length} location cards');
                if (locationsData.isNotEmpty) {
                  print('📍 Updating UI with location cards');
                  // Force UI update with WidgetsBinding to ensure rebuild
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && sessionIndex < conversationHistory.length) {
                      setState(() {
                        conversationHistory[sessionIndex] =
                            conversationHistory[sessionIndex].copyWith(
                              locationCards: locationsData,
                            );
                      });
                      print('📍 UI updated. Current locationCards count: ${conversationHistory[sessionIndex].locationCards.length}');
                    }
                  });
                }
                break;

              case 'end':
                // Ensure all text is displayed before stopping
                _targetText = accumulatedAnswer;
                // Check if cards were included in the end event (products, hotels, flights, restaurants, locations, destination_images)
                final endProducts = data['products'] as List?;
                final endHotels = data['hotelResults'] as List?;
                final endFlights = data['flights'] as List?;
                final endRestaurants = data['restaurants'] as List?;
                final endLocations = data['locations'] as List?;
                final endDestinationImages = data['destination_images'] as List?;
                // ✅ FIX: Store backend values from end event
                final endIntent = data['intent'] as String?;
                final endCardType = data['cardType'] as String?;
                final endCards = data['cards'] as List?;
                
                if (endProducts != null && endProducts.isNotEmpty) {
                  final List<Product> products = endProducts.map<Product>((item) {
                    try {
                      return _mapShoppingResultToProduct(Map<String, dynamic>.from(item));
                    } catch (e) {
                      print('Error mapping product from end event: $e');
                      return Product(
                        id: DateTime.now().millisecondsSinceEpoch,
                        title: 'Error loading product',
                        description: 'Unable to load product details',
                        price: 0.0,
                        source: 'Error',
                        rating: 0.0,
                        images: [],
                        variants: [],
                      );
                    }
                  }).toList();
                  
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          products: products,
                          // ✅ FIX: Store backend values
                          intent: endIntent,
                          cardType: endCardType,
                          cards: endCards?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                        );
                  });
                } else {
                  // ✅ FIX: Store backend values even if no products
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          intent: endIntent,
                          cardType: endCardType,
                          cards: endCards?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                        );
                  });
                }
                
                if (endHotels != null && endHotels.isNotEmpty) {
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          hotelResults: endHotels.map((e) => Map<String, dynamic>.from(e)).toList(),
                        );
                  });
                }
                
                if (endFlights != null && endFlights.isNotEmpty) {
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          rawResults: endFlights.map((e) => Map<String, dynamic>.from(e)).toList(),
                        );
                  });
                }
                
                if (endRestaurants != null && endRestaurants.isNotEmpty) {
                  setState(() {
                    conversationHistory[sessionIndex] =
                        conversationHistory[sessionIndex].copyWith(
                          rawResults: endRestaurants.map((e) => Map<String, dynamic>.from(e)).toList(),
                        );
                  });
                }
                
                if (endDestinationImages != null && endDestinationImages.isNotEmpty) {
                  final imagesList = endDestinationImages.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && sessionIndex < conversationHistory.length) {
                      setState(() {
                        conversationHistory[sessionIndex] =
                            conversationHistory[sessionIndex].copyWith(
                              destinationImages: imagesList,
                            );
                      });
                    }
                  });
                }
                
                if (endLocations != null && endLocations.isNotEmpty) {
                  print('📍 Received locations in end event: ${endLocations.length} cards');
                  // Force UI update with WidgetsBinding to ensure rebuild
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && sessionIndex < conversationHistory.length) {
                      setState(() {
                        conversationHistory[sessionIndex] =
                            conversationHistory[sessionIndex].copyWith(
                              locationCards: endLocations.map((e) => Map<String, dynamic>.from(e)).toList(),
                            );
                      });
                      print('📍 UI updated from end event. Current locationCards count: ${conversationHistory[sessionIndex].locationCards.length}');
                    }
                  });
                }
                
                // ✅ Pre-parse when end event arrives with all data
                final finalSummary = accumulatedAnswer.isNotEmpty ? accumulatedAnswer : session.summary ?? '';
                final finalLocations = endLocations?.map((e) => Map<String, dynamic>.from(e)).toList() ?? 
                    conversationHistory[sessionIndex].locationCards;
                final finalImages = endDestinationImages?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? 
                    conversationHistory[sessionIndex].destinationImages;
                
                if (finalSummary.isNotEmpty || finalLocations.isNotEmpty) {
                  final input = ParsingInput(
                    answerText: finalSummary,
                    locationCards: finalLocations,
                    destinationImages: finalImages,
                  );
                  
                  compute(parseAnswerIsolate, input.toMap()).then((parsed) {
                    if (mounted && sessionIndex < conversationHistory.length) {
                      setState(() {
                        conversationHistory[sessionIndex] = conversationHistory[sessionIndex].copyWith(
                          cachedParsing: parsed,
                        );
                      });
                    }
                  });
                }
                
                // Wait for animation to catch up completely
                Future.delayed(const Duration(milliseconds: 200), () {
                  // Keep checking until animation catches up
                  _waitForAnimationToComplete(sessionIndex, accumulatedAnswer, sources);
                });
                return; // ✅ stop listening when done

              case 'error':
                throw Exception(data['error'] ?? 'Unknown stream error');
            }
          } catch (e) {
            debugPrint('Bad SSE line: $line');
          }
        }
      }

      // fallback: if we reach here and didn't get "end"
      _streamTimer?.cancel();
      _displayedText = '';
      _targetText = '';
      setState(() {
        conversationHistory[sessionIndex] =
            conversationHistory[sessionIndex].copyWith(
          summary: accumulatedAnswer.isNotEmpty ? accumulatedAnswer : session.summary ?? '',
          sources: sources,
          isStreaming: false,
          isLoading: false,
        );
      });
      // Generate suggestions even if stream ended without "end" event
      if (accumulatedAnswer.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && sessionIndex < conversationHistory.length) {
            _generateFollowUpSuggestions(sessionIndex, accumulatedAnswer);
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Streaming error: $e');
      _streamTimer?.cancel();
      _displayedText = '';
      _targetText = '';
      
      // If streaming fails, try non-streaming API call as fallback
      debugPrint('🔄 Falling back to non-streaming API call...');
      try {
        final List<Map<String, dynamic>> history = [];
        for (int i = 0; i < sessionIndex; i++) {
          final prevSession = conversationHistory[i];
          if (prevSession.query.isNotEmpty && 
              prevSession.summary != null && 
              prevSession.summary!.isNotEmpty) {
            history.add({
              "query": prevSession.query,
              "summary": prevSession.summary ?? "",
              "intent": prevSession.resultType,    // <-- important
              "cardType": prevSession.resultType,  // <-- important
              "cards": prevSession.products.map((p) => {
                "title": p.title,
                "price": p.price,
                "rating": p.rating,
                "images": p.images,
                "source": p.source,
              }).toList(),
              "results": prevSession.rawResults,
            });
          }
        }
        
        final responseData = await AgentService.askAgent(
          session.query, 
          conversationHistory: history,
          imageUrl: widget.imageUrl, // ✅ Pass imageUrl for image search
        );
        final resultType = (responseData['intent'] ?? 'answer').toString().toLowerCase();
        
        if (resultType == 'answer' || resultType == 'general') {
          final sources = (responseData['sources'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ?? [];
          final locationCards = (responseData['locations'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ?? [];
          final destinationImages = (responseData['destination_images'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ?? [];
          
          // ✅ PART 4: Add missing summary fallback
          final cleanSummaryFallback = cleanMarkdown(
            responseData['summary'] ??
            responseData['answer'] ??
            "Here are the details you're looking for:"
          );
          
          // ✅ MOST IMPORTANT: Pre-parse in isolate when data arrives
          final input = ParsingInput(
            answerText: cleanSummaryFallback,
            locationCards: locationCards,
            destinationImages: destinationImages,
          );
          
          // Parse in background isolate
          compute(parseAnswerIsolate, input.toMap()).then((parsed) {
            if (mounted && sessionIndex < conversationHistory.length) {
              setState(() {
                conversationHistory[sessionIndex] = conversationHistory[sessionIndex].copyWith(
                  cachedParsing: parsed,
                );
              });
            }
          });
          
          // ✅ C5: MUST set isLoading to false after backend returns
          setState(() {
            conversationHistory[sessionIndex] = session.copyWith(
              resultType: 'answer',
              isLoading: false, // ✅ C5: Clear loading state
              summary: cleanSummaryFallback,
              sources: sources,
              locationCards: locationCards,
              destinationImages: destinationImages,
              isStreaming: false,
              // ✅ FIX: Store backend values
              intent: responseData['intent']?.toString(),
              cardType: responseData['cardType']?.toString(),
              cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
            );
          });
          
          // Generate follow-up suggestions
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && sessionIndex < conversationHistory.length) {
              final summary = responseData['summary']?.toString() ?? responseData['answer']?.toString() ?? '';
              _generateFollowUpSuggestions(sessionIndex, summary);
            }
          });
        } else {
          // Not an answer query, let _loadResultsForSession handle it
          _loadResultsForSession(sessionIndex);
        }
      } catch (fallbackError) {
        debugPrint('❌ Fallback also failed: $fallbackError');
        setState(() {
          conversationHistory[sessionIndex] = session.copyWith(
            summary: '⚠️ Error loading answer. Please try again.',
            isStreaming: false,
            isLoading: false,
          );
        });
      }
    }
  }


  // Wait for character animation to complete before marking as done
  void _waitForAnimationToComplete(int sessionIndex, String finalText, List<Map<String, dynamic>> sources, {int retryCount = 0}) {
    if (!mounted) return;
    
    // Safety: Don't wait forever - max 10 seconds (200 retries * 50ms)
    if (retryCount > 200) {
      debugPrint('⚠️ Animation timeout - forcing completion');
      _streamTimer?.cancel();
      setState(() {
        conversationHistory[sessionIndex] =
            conversationHistory[sessionIndex].copyWith(
          summary: finalText,
          sources: sources,
          isStreaming: false,
          isLoading: false,
        );
      });
      _displayedText = '';
      _targetText = '';
      // Generate suggestions even if animation timed out
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && sessionIndex < conversationHistory.length) {
          _generateFollowUpSuggestions(sessionIndex, finalText);
        }
      });
      return;
    }
    
    // Check if animation has caught up
    if (_displayedText.length >= _targetText.length) {
      // Animation complete
      _streamTimer?.cancel();
      setState(() {
        conversationHistory[sessionIndex] =
            conversationHistory[sessionIndex].copyWith(
          summary: finalText,
          sources: sources,
          isStreaming: false,
          isLoading: false,
        );
      });
      _displayedText = '';
      _targetText = '';
      
      debugPrint('✅ Animation complete, generating suggestions...');
      // Generate follow-up suggestions after answer is complete
      // Add a small delay to ensure state update is complete
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && sessionIndex < conversationHistory.length) {
          _generateFollowUpSuggestions(sessionIndex, finalText);
        }
      });
    } else {
      // Still animating, check again in 50ms
      Future.delayed(const Duration(milliseconds: 50), () {
        _waitForAnimationToComplete(sessionIndex, finalText, sources, retryCount: retryCount + 1);
      });
    }
  }

  // Generate AI-powered follow-up suggestions
  Future<void> _generateFollowUpSuggestions(int sessionIndex, String answer) async {
    if (!mounted) return;
    
    debugPrint('🎯 Generating follow-up suggestions for session $sessionIndex');
    debugPrint('Query: ${conversationHistory[sessionIndex].query}');
    debugPrint('Answer length: ${answer.length}');
    
    try {
      final session = conversationHistory[sessionIndex];
      final query = session.query;
      
      // Call OpenAI to generate 3 relevant follow-up suggestions
      final request = http.Request(
        'POST',
        Uri.parse('${AgentService.baseUrl}/api/agent/generate-suggestions'),
      );
      request.headers['Content-Type'] = 'application/json';
      // Build conversation history for better context
      final List<Map<String, dynamic>> history = [];
      for (int i = 0; i < sessionIndex; i++) {
        final prevSession = conversationHistory[i];
        if (prevSession.query.isNotEmpty && 
            prevSession.summary != null && 
            prevSession.summary!.isNotEmpty) {
          history.add({
            "query": prevSession.query,
            "summary": prevSession.summary,
            "intent": prevSession.resultType,
          });
        }
      }
      
      request.body = jsonEncode({
        "query": query,
        "answer": answer,
        "conversationHistory": history, // Include conversation history for better predictions
      });

      debugPrint('📡 Calling API: ${AgentService.baseUrl}/api/agent/generate-suggestions');
      final response = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final responseBody = await response.stream.bytesToString();
      
      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: $responseBody');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final suggestions = (data['suggestions'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .take(3)
            .toList() ?? [];
        
        debugPrint('✅ Parsed suggestions: $suggestions');
        
        if (mounted && suggestions.isNotEmpty) {
          // ✅ PART 3: Fix follow-up generation duplication
          final prev = conversationHistory[sessionIndex].query.toLowerCase();
          final cleaned = suggestions
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && !s.toLowerCase().contains(prev))
              .toList();
          
          setState(() {
            conversationHistory[sessionIndex] =
                conversationHistory[sessionIndex].copyWith(
              followUpSuggestions: cleaned.take(3).toList(),
            );
          });
          debugPrint('✅ Suggestions set in state: ${conversationHistory[sessionIndex].followUpSuggestions}');
        } else {
          debugPrint('⚠️ No suggestions or empty list, using fallback');
          _generateFallbackSuggestions(sessionIndex);
        }
      } else {
        debugPrint('❌ API error: ${response.statusCode}, using fallback');
        _generateFallbackSuggestions(sessionIndex);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to generate follow-up suggestions: $e');
      debugPrint('Stack trace: $stackTrace');
      // Fallback: Generate simple suggestions based on query
      _generateFallbackSuggestions(sessionIndex);
    }
  }

  // Fallback: Generate simple suggestions if API fails
  void _generateFallbackSuggestions(int sessionIndex) {
    if (!mounted) return;
    
    debugPrint('🔄 Generating fallback suggestions for session $sessionIndex');
    final session = conversationHistory[sessionIndex];
    final query = session.query.toLowerCase();
    final answer = session.summary?.toLowerCase() ?? '';
    final suggestions = <String>[];
    
    // Generate context-aware suggestions based on query AND answer content
    // Check for location/travel keywords first
    if (query.contains('hawaii') || query.contains('island') || query.contains('beach') || 
        query.contains('travel') || query.contains('visit') || query.contains('attraction') ||
        answer.contains('hawaii') || answer.contains('island') || answer.contains('travel')) {
      if (query.contains('cultural') || query.contains('culture') || answer.contains('cultural')) {
        suggestions.add('Best time to visit?');
        suggestions.add('Traditional foods?');
        suggestions.add('Festivals and events?');
      } else if (query.contains('attraction') || query.contains('see') || query.contains('do')) {
        suggestions.add('Best time to visit?');
        suggestions.add('How to get there?');
        suggestions.add('Entry fees?');
      } else {
        suggestions.add('Best time to visit?');
        suggestions.add('How to get there?');
        suggestions.add('What to see?');
      }
    } else if (query.contains('shoes') || query.contains('shoe')) {
      if (query.contains('under') || query.contains('\$')) {
        suggestions.add('Running shoes under \$200?');
        suggestions.add('Filter by size?');
        suggestions.add('Compare durability?');
      } else {
        suggestions.add('Running shoes under \$100?');
        suggestions.add('Best for running?');
        suggestions.add('Compare models?');
      }
    } else if (query.contains('restaurant') || query.contains('eat') || query.contains('dining') || 
               query.contains('food') || query.contains('cuisine') || query.contains('menu') ||
               answer.contains('restaurant') || answer.contains('dining') || answer.contains('cuisine')) {
      // Restaurant-specific suggestions
      suggestions.add('View menu?');
      suggestions.add('Price range?');
      suggestions.add('Make reservation?');
    } else if (query.contains('hotel') || query.contains('motel')) {
      suggestions.add('Free breakfast?');
      suggestions.add('Price range?');
      suggestions.add('Near downtown?');
    } else if (query.contains('machine learning') || query.contains('ml') || query.contains('ai') || query.contains('artificial intelligence')) {
      suggestions.add('Applications?');
      suggestions.add('ML vs deep learning?');
      suggestions.add('Best languages?');
    } else if (query.startsWith('what is') || query.startsWith('what are')) {
      // Extract topic from query
      final topic = query.replaceAll('what is', '').replaceAll('what are', '').trim();
      if (topic.isNotEmpty && topic.length < 20) {
        suggestions.add('How does $topic work?');
        suggestions.add('Benefits?');
        suggestions.add('Alternatives?');
      } else {
        // Use answer content to generate better suggestions
        if (answer.contains('location') || answer.contains('place') || answer.contains('island')) {
          suggestions.add('Best time to visit?');
          suggestions.add('How to get there?');
          suggestions.add('What to see?');
        } else {
          suggestions.add('Tell me more');
          suggestions.add('Key features?');
          suggestions.add('Learn more');
        }
      }
    } else if (query.startsWith('how') || query.startsWith('why')) {
      suggestions.add('Steps?');
      suggestions.add('Benefits?');
      suggestions.add('Alternatives?');
    } else {
      // Generic fallback - try to extract context from answer
      if (answer.contains('location') || answer.contains('place') || answer.contains('travel')) {
        suggestions.add('Best time to visit?');
        suggestions.add('How to get there?');
        suggestions.add('What to see?');
      } else {
        suggestions.add('Tell me more');
        suggestions.add('Best options?');
        suggestions.add('Compare?');
      }
    }
    
    debugPrint('🔄 Fallback suggestions generated: $suggestions');
    
    if (mounted && suggestions.isNotEmpty) {
      // ✅ PART 3: Fix follow-up generation duplication
      final prev = conversationHistory[sessionIndex].query.toLowerCase();
      final cleaned = suggestions
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.toLowerCase().contains(prev))
          .toList();
      
      setState(() {
        conversationHistory[sessionIndex] =
            conversationHistory[sessionIndex].copyWith(
          followUpSuggestions: cleaned.take(3).toList(),
        );
      });
      debugPrint('✅ Fallback suggestions set in state: ${conversationHistory[sessionIndex].followUpSuggestions}');
    }
  }

  void _navigateToHotelDetail(Map<String, dynamic> hotel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HotelDetailScreen(hotel: hotel),
      ),
    );
  }

  // Helper method to launch URLs
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  // Helper method to make phone calls
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not make call to $phoneNumber')),
        );
      }
    }
  }

  // Helper method to open directions
  Future<void> _openDirections(String address) async {
    final Uri mapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    if (await canLaunchUrl(mapsUri)) {
      await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open directions to $address')),
        );
      }
    }
  }

  // Open directions to a specific hotel with full address or coordinates
  Future<void> _openHotelDirections(Map<String, dynamic> hotel) async {
    print('🧭 Opening directions for hotel: ${hotel['name'] ?? hotel['title']}');
    print('🧭 Hotel data keys: ${hotel.keys.toList()}');
    print('🧭 GPS coordinates: ${hotel['gps_coordinates']}');
    print('🧭 Geo: ${hotel['geo']}');
    print('🧭 Latitude: ${hotel['latitude']}, Longitude: ${hotel['longitude']}');
    
    // Priority 1: Use coordinates if available (most accurate)
    final coords = GeocodingService.extractCoordinates(hotel);
    print('🧭 Extracted coordinates: $coords');
    
    if (coords != null && coords['latitude'] != null && coords['longitude'] != null) {
      final lat = coords['latitude']!;
      final lng = coords['longitude']!;
      
      // Validate coordinates (not 0,0)
      if (lat != 0.0 && lng != 0.0) {
        print('🧭 Using coordinates: $lat, $lng');
        // Use /dir/ endpoint for turn-by-turn directions
        final Uri mapsUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
        if (await canLaunchUrl(mapsUri)) {
          await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
          print('✅ Opened Google Maps with coordinates');
          return;
        } else {
          print('❌ Cannot launch URL: $mapsUri');
        }
      } else {
        // print('⚠️ Coordinates are 0,0 - invalid, falling back to address');
      }
    } else {
      // print('⚠️ No coordinates found, falling back to address');
    }
    
    // Priority 2: Build full address from hotel data
    final hotelName = hotel['name']?.toString() ?? hotel['title']?.toString() ?? '';
    final addressField = hotel['address']?.toString() ?? '';
    final locationField = hotel['location']?.toString() ?? '';
    
    String? destination;
    
    // If we have a specific address field (not just city), use it
    if (addressField.isNotEmpty && addressField != locationField) {
      // Check if address looks like a full address (contains street number or street name)
      final hasStreetInfo = addressField.contains(RegExp(r'\d')) || 
                            addressField.split(',').length > 2;
      
      if (hasStreetInfo) {
        // Full address available - use hotel name + address for better search
        destination = hotelName.isNotEmpty 
            ? '$hotelName, $addressField'
            : addressField;
      } else {
        // Address field exists but might just be city - combine with hotel name
        destination = hotelName.isNotEmpty 
            ? '$hotelName, $addressField'
            : addressField;
      }
    } 
    // If no address field or it's the same as location, use location with hotel name
    else if (locationField.isNotEmpty) {
      // Check if location is just a city name (no numbers, simple format)
      final isJustCity = !locationField.contains(RegExp(r'\d')) && 
                         locationField.split(',').length <= 2;
      
      if (isJustCity && hotelName.isNotEmpty) {
        // Combine hotel name with location for better Google Maps search
        destination = '$hotelName, $locationField';
      } else {
        destination = locationField;
      }
    }
    
    // Priority 3: Fallback to hotel name only
    if (destination == null || destination.isEmpty) {
      destination = hotelName.isNotEmpty ? hotelName : 'Unknown Location';
    }
    
    // Open directions using /dir/ endpoint for turn-by-turn navigation
    final Uri mapsUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}');
    if (await canLaunchUrl(mapsUri)) {
      await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps')),
        );
      }
    }
  }

  // Build view toggle button for hotel view mode
  Widget _buildViewToggleButton(String mode, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () {
        print('🗺️ Switching hotel view to: $mode');
        setState(() {
          _hotelViewMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this); // clean up
    _followUpController.dispose();
    _followUpFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ✅ STEP 9: Accept previousContext to pass to backend
  // ✅ FOLLOW-UP PATCH: Accept lastFollowUp and parentQuery
  void _onFollowUpSubmitted({
    QuerySession? previousContext,
    String? lastFollowUp,
    String? parentQuery,
  }) {
    final query = _followUpController.text.trim();
    print('ShoppingResultsScreen follow-up query: "$query"');
    
    if (query.isNotEmpty) {
      // Clear the field first
      _followUpController.clear();
      
      // ✅ STEP 9: Extract context from previous session (or use provided)
      final previousSession = previousContext ?? 
          (conversationHistory.isNotEmpty ? conversationHistory.last : null);
      
      // Build context object for backend
      Map<String, dynamic>? contextToSend;
      if (previousSession != null) {
        contextToSend = {
          'intent': previousSession.intent ?? previousSession.resultType,
          'cardType': previousSession.cardType ?? previousSession.resultType,
          'sessionId': 'global', // Use global session for now
        };
        
        // Extract slots from backend response if available
        // (We'll store this in QuerySession later)
        print('📦 Sending follow-up context: intent=${contextToSend['intent']}, cardType=${contextToSend['cardType']}');
      }
      
      // Inherit the previous intent unless backend overrides
      final resultType = previousSession?.resultType ?? 'shopping'; // Default fallback
      final newQueryIndex = conversationHistory.length; // Get index BEFORE adding
      
      // ✅ C5: Clear state before new request
      setState(() {
        // Add new QuerySession with loading state
        final newSession = QuerySession(
          query: query,
          products: [],
          hotelResults: [],
          resultType: resultType,
          isLoading: true,
        );
        conversationHistory.add(newSession);
        _queryKeys.add(GlobalKey());
      });
      
      // ⚡ IMMEDIATE SCROLL: Scroll to new query at TOP immediately
      // Strategy: Wait for ListView to rebuild, then scroll to max extent, then use ensureVisible to position at top
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Step 1: Wait for ListView to rebuild with new item
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted || !_scrollController.hasClients) return;
          
          // Step 2: First, scroll to maximum extent (this shows the last item = new query)
          final maxScroll = _scrollController.position.maxScrollExtent;
          if (maxScroll > 0) {
            // Jump to max extent immediately (shows new query, but at bottom of viewport)
            _scrollController.jumpTo(maxScroll);
            print('📍 Jumped to max extent: $maxScroll for new query (index: $newQueryIndex)');
            
            // Step 3: Immediately after, use ensureVisible to position it at TOP
            Future.delayed(const Duration(milliseconds: 50), () {
              if (!mounted || !_scrollController.hasClients) return;
              
              // Try GlobalKey to position query at TOP of viewport
              if (newQueryIndex < _queryKeys.length) {
                final key = _queryKeys[newQueryIndex];
                final context = key.currentContext;
                
                if (context != null) {
                  // Position query at TOP of viewport (alignment: 0.0 = top)
                  Scrollable.ensureVisible(
                    context,
                    duration: const Duration(milliseconds: 0), // Instant!
                    alignment: 0.0, // 0.0 = top of viewport
                    curve: Curves.linear,
                  );
                  print('✅ Positioned new query at TOP (index: $newQueryIndex)');
                  return;
                }
              }
              
              // If GlobalKey not ready, try again after a bit more delay
              Future.delayed(const Duration(milliseconds: 100), () {
                if (!mounted || !_scrollController.hasClients) return;
                
                if (newQueryIndex < _queryKeys.length) {
                  final key = _queryKeys[newQueryIndex];
                  final context = key.currentContext;
                  
                  if (context != null) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 0),
                      alignment: 0.0,
                      curve: Curves.linear,
                    );
                    print('✅ Final attempt - positioned new query at TOP');
                  }
                }
              });
            });
          } else {
            // If maxScroll is 0, ListView might not have rebuilt yet, try again
            Future.delayed(const Duration(milliseconds: 150), () {
              if (!mounted || !_scrollController.hasClients) return;
              
              final maxScroll2 = _scrollController.position.maxScrollExtent;
              if (maxScroll2 > 0) {
                _scrollController.jumpTo(maxScroll2);
                
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted && _scrollController.hasClients && newQueryIndex < _queryKeys.length) {
                    final key = _queryKeys[newQueryIndex];
                    final context = key.currentContext;
                    if (context != null) {
                      Scrollable.ensureVisible(
                        context,
                        duration: const Duration(milliseconds: 0),
                        alignment: 0.0,
                        curve: Curves.linear,
                      );
                      print('✅ Retry - positioned new query at TOP');
                    }
                  }
                });
              }
            });
          }
        });
      });
      
      // ✅ STEP 9: Load results with context
      // ✅ FOLLOW-UP PATCH: Pass lastFollowUp and parentQuery
      _loadResultsForSession(
        newQueryIndex, 
        previousContext: contextToSend,
        lastFollowUp: lastFollowUp,
        parentQuery: parentQuery,
      );
      
      // Dismiss keyboard after a short delay to allow the UI to update
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      });
    } else {
      // If empty, just focus back to the field
      print('Empty query - refocusing field');
      _showKeyboard();
    }
  }

  void _showKeyboard() {
    _followUpFocusNode.requestFocus();
  }

  // Simple scroll to new query - positions it at TOP of screen
  void _scrollToNewQuery(int queryIndex) {
    if (!mounted || !_scrollController.hasClients) return;
    
    // Try GlobalKey first (most accurate - positions query title at top)
    if (queryIndex >= 0 && queryIndex < _queryKeys.length) {
      final key = _queryKeys[queryIndex];
      final context = key.currentContext;
      
      if (context != null) {
        // Use Scrollable.ensureVisible to position query title at TOP
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200), // Faster for better UX
          alignment: 0.0, // 0.0 = top of viewport
          curve: Curves.easeOut,
        );
        return; // Success!
      }
    }
    
    // Fallback: If GlobalKey not ready, jump to estimated position (instant)
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      // Estimate: each query is ~800px, scroll to show last query at top
      final estimatedPosition = queryIndex * 800.0;
      final targetPosition = estimatedPosition.clamp(0.0, maxScroll > 0 ? maxScroll : double.infinity);
      
      // Use jumpTo for instant scroll (no animation delay)
      _scrollController.jumpTo(targetPosition);
    }
  }

  // Original scroll method (for delayed scrolling after results load)
  void _scrollToQuery(int queryIndex) {
    print('🎯 _scrollToQuery called with index: $queryIndex');
    print('   _queryKeys.length: ${_queryKeys.length}');
    print('   conversationHistory.length: ${conversationHistory.length}');
    
    // Wait a bit for the widget to be fully built
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) {
        print('   ⚠️ Widget not mounted, skipping scroll');
        return;
      }
      
      print('   Checking scroll conditions...');
      print('   queryIndex >= 0: ${queryIndex >= 0}');
      print('   queryIndex < _queryKeys.length: ${queryIndex < _queryKeys.length}');
      
      if (queryIndex >= 0 && queryIndex < _queryKeys.length) {
        final key = _queryKeys[queryIndex];
        final hasContext = key.currentContext != null;
        print('   Key has context: $hasContext');
        
        if (hasContext) {
          print('   ✅ Scrolling to query at index: $queryIndex');
      try {
        Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 400),
              alignment: 0.0, // 0.0 = top of viewport
              curve: Curves.easeInOut,
            );
            print('   ✅ Scroll command executed successfully');
            return;
      } catch (e) {
            print('   ❌ Scrollable.ensureVisible failed: $e');
        }
        } else {
          print('   ⚠️ Key context is null, will try fallback');
      }
    } else {
        print('   ❌ Index out of bounds');
      }
      
      // Fallback: calculate approximate scroll position
      if (_scrollController.hasClients) {
        print('   🔄 Using fallback scroll estimation');
        // Estimate position: each query session is roughly 600-800px tall
        final estimatedPosition = queryIndex * 700.0;
        final clampedPosition = estimatedPosition.clamp(0.0, _scrollController.position.maxScrollExtent);
        print('   📍 Estimated position: $estimatedPosition, clamped: $clampedPosition');
        _scrollController.animateTo(
          clampedPosition,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      } else {
        print('   ❌ ScrollController not available');
      }
    });
  }

  // ✅ PATCH 1: Optimized _handleAgentResponse
  Future<void> _handleAgentResponse(Map<String, dynamic> agentJson, int sessionIndex) async {
    debugPrint("🟦 Agent Response received");

    // Filter out empty or null responses
    if (agentJson.isEmpty) return;

    // Extract needed fields
    final rawResults = agentJson["results"] ?? <String, dynamic>{};
    final rawAnswer = agentJson["answer"] ?? <String, dynamic>{};
    final sections = agentJson["sections"] ?? [];
    final intent = agentJson["finalIntent"] ?? "unknown";
    final cardType = agentJson["finalCardType"] ?? "unknown";

    // 🔥 Do NOT setState() yet — wait for parsing to finish
    if (sessionIndex < conversationHistory.length) {
      setState(() {
        conversationHistory[sessionIndex] = conversationHistory[sessionIndex].copyWith(
          isParsing: true,
        );
      });
    }

    // 🔥 Send everything to isolate FIRST
    final isolateInput = {
      "rawAnswer": rawAnswer,
      "rawResults": rawResults,
      "rawSections": sections,
      "intent": intent,
      "cardType": cardType,
    };

    debugPrint("🚀 Sending data to isolate...");

    final parsed = await compute(parseAgentResponseIsolate, isolateInput);

    debugPrint("✅ Isolate parsing done.");

    // Now that heavy work is done, update UI
    if (!mounted || sessionIndex >= conversationHistory.length) return;

    setState(() {
      final session = conversationHistory[sessionIndex];
      conversationHistory[sessionIndex] = session.copyWith(
        summary: parsed["summary"] ?? session.summary,
        rawResults: rawResults,
        intent: intent,
        cardType: cardType,
        isParsing: false,
        isLoading: false,
      );
    });

    debugPrint("🎉 UI updated with parsed data.");
  }

  // ✅ PATCH C1: Preprocess response data (moves heavy logic out of build methods)
  Map<String, dynamic>? _preprocessResponse(Map<String, dynamic> response) {
    try {
      final sections = response["sections"] ?? [];
      final locations = response["locations"] ?? [];
      final mapPoints = response["map"] ?? [];
      final answer = response["answer"]?.toString() ?? "";
      final summary = response["summary"]?.toString() ?? "";
      final followUps = response["followUps"] ?? response["followUpSuggestions"] ?? [];
      
      // Preprocess locations (move heavy logic from _buildLocationCard)
      final preprocessedLocations = (locations as List).map((location) {
        final title = location['title']?.toString() ?? location['name']?.toString() ?? 'Unknown Location';
        final rating = safeNumber(location['rating'], 0.0);
        final reviews = location['reviews']?.toString() ?? '';
        final address = location['address']?.toString() ?? '';
        final thumbnail = location['thumbnail']?.toString() ?? '';
        final link = location['link']?.toString() ?? '';
        final phone = location['phone']?.toString() ?? '';
        final gpsCoordinates = location['gps_coordinates'];
        final images = (location['images'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
        final description = location['description']?.toString() ?? location['snippet']?.toString() ?? '';
        
        // Build map URL from GPS coordinates or address
        String? mapUrl;
        if (gpsCoordinates != null && gpsCoordinates is Map) {
          final lat = gpsCoordinates['latitude'];
          final lng = gpsCoordinates['longitude'];
          if (lat != null && lng != null) {
            mapUrl = 'https://www.google.com/maps?q=$lat,$lng';
          }
        }
        if (mapUrl == null && address.isNotEmpty) {
          mapUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}';
        }
        
        // Use thumbnail or first image from images array
        final mainImage = thumbnail.isNotEmpty ? thumbnail : (images.isNotEmpty ? images[0] : null);
        
        return {
          'title': title,
          'rating': rating,
          'reviews': reviews,
          'address': address,
          'thumbnail': thumbnail,
          'link': link,
          'phone': phone,
          'images': images,
          'description': description,
          'mapUrl': mapUrl,
          'mainImage': mainImage,
        };
      }).toList();
      
      // Preprocess places (move heavy logic from _buildPlaceCard)
      // Process all results that look like places (have geo, location, or are in places array)
      final placesArray = response["places"] ?? response["results"] ?? [];
      final preprocessedPlaces = (placesArray as List).map((place) {
        final name = place['name']?.toString() ?? place['title']?.toString() ?? 'Unknown Place';
        final description = place['description']?.toString() ?? '';
        final rating = place['rating']?.toString() ?? '';
        final reviews = place['reviews']?.toString() ?? '';
        final location = place['location']?.toString() ?? place['address']?.toString() ?? '';
        final website = place['website']?.toString() ?? place['link']?.toString() ?? '';
        final phone = place['phone']?.toString() ?? '';
        final geo = place['geo'];
        
        // Collect all available images
        List<String> allImages = [];
        if (place['images'] != null && place['images'] is List) {
          for (var img in place['images']) {
            final imgStr = img?.toString() ?? '';
            if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
              allImages.add(imgStr);
            }
          }
        }
        if (place['photos'] != null && place['photos'] is List) {
          for (var photo in place['photos']) {
            final photoStr = photo?.toString() ?? '';
            if (photoStr.isNotEmpty && photoStr.startsWith('http') && !allImages.contains(photoStr)) {
              allImages.add(photoStr);
            }
          }
        }
        final imageUrl = place['image_url']?.toString() ?? place['image']?.toString() ?? place['thumbnail']?.toString() ?? '';
        if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
          if (!allImages.contains(imageUrl)) {
            allImages.insert(0, imageUrl);
          }
        }
        if (allImages.isEmpty) {
          allImages.add(''); // Placeholder
        }
        
        // Build map URL
        String? mapUrl;
        if (geo != null && geo is Map) {
          final lat = geo['latitude'] ?? geo['lat'];
          final lng = geo['longitude'] ?? geo['lng'];
          if (lat != null && lng != null) {
            mapUrl = 'https://www.google.com/maps?q=$lat,$lng';
          }
        }
        if (mapUrl == null && location.isNotEmpty) {
          mapUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location)}';
        }
        
        // Parse rating
        double? ratingNum;
        if (rating.isNotEmpty) {
          ratingNum = double.tryParse(rating.replaceAll(RegExp(r'[^\d.]'), ''));
        }
        
        return {
          'name': name,
          'description': description,
          'rating': rating,
          'ratingNum': ratingNum,
          'reviews': reviews,
          'location': location,
          'website': website,
          'phone': phone,
          'allImages': allImages,
          'mapUrl': mapUrl,
        };
      }).toList();
      
      return {
        "results": sections,
        "locations": preprocessedLocations,
        "mapPoints": mapPoints,
        "answer": answer,
        "summary": summary,
        "followUps": followUps,
        "preprocessedPlaces": preprocessedPlaces,
      };
    } catch (e) {
      debugPrint("❌ Preprocess error: $e");
      return null;
    }
  }

  // ✅ STEP 9: Accept previousContext parameter
  // ✅ FOLLOW-UP PATCH: Accept lastFollowUp and parentQuery
  Future<void> _loadResultsForSession(
    int sessionIndex, {
    Map<String, dynamic>? previousContext,
    String? lastFollowUp,
    String? parentQuery,
  }) async {
    if (sessionIndex >= conversationHistory.length) {
      // print('⚠️  Session index $sessionIndex >= conversationHistory.length ${conversationHistory.length}');
      return;
    }
    
    try {
      final session = conversationHistory[sessionIndex];
      print("🔍 Loading results for query: ${session.query}");
      
      // 🚫 REMOVE early streaming check
      // ALWAYS call the backend first
      
      // Build conversation history for context (previous queries and answers)
      // Similar to ChatGPT/Perplexity: include all previous exchanges for context
      // ✅ FIX: If a new image is uploaded, don't include previous image-based queries in history
      final List<Map<String, dynamic>> history = [];
      final bool hasNewImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
      
      for (int i = 0; i < sessionIndex; i++) {
        final prevSession = conversationHistory[i];
        // Only include completed exchanges (both query and answer)
        // ✅ FIX: Skip previous queries if a new image is being used (prevents old image results)
        if (prevSession.query.isNotEmpty && 
            prevSession.summary != null && 
            prevSession.summary!.isNotEmpty) {
          // If this is a new image search, don't include previous image-based queries
          if (hasNewImage) {
            // Skip if previous query was likely an image search (contains image-related keywords)
            final prevQuery = prevSession.query.toLowerCase();
            if (prevQuery.contains('similar') || 
                prevQuery.contains('find') || 
                prevQuery.contains('image') ||
                prevQuery.contains('photo') ||
                prevQuery.contains('picture')) {
              print('⏭️ Skipping previous image-based query from history: ${prevSession.query}');
              continue; // Skip this previous query
            }
          }
          
          history.add({
            "query": prevSession.query,
            "summary": prevSession.summary ?? "",
            "intent": prevSession.resultType,    // <-- important
            "cardType": prevSession.resultType,  // <-- important
            "cards": prevSession.products.map((p) => {
              "title": p.title,
              "price": p.price,
              "rating": p.rating,
              "images": p.images,
              "source": p.source,
            }).toList(),
            "results": prevSession.rawResults,
          });
        }
      }
      print('📚 Sending ${history.length} previous exchanges for context${hasNewImage ? " (new image search - skipped image-based queries)" : ""}');
      
      Map<String, dynamic> responseData;
      try {
        print('Making API call to AgentService...');
        print('Query: ${session.query}');
        print('Conversation history length: ${history.length}');
        
        // ✅ STEP 9: Pass previousContext to AgentService
        // ✅ FOLLOW-UP PATCH: Pass lastFollowUp and parentQuery
        // ✅ Add timeout wrapper to prevent UI blocking
        responseData = await AgentService.askAgent(
          session.query, 
          conversationHistory: history,
          previousContext: previousContext,
          lastFollowUp: lastFollowUp,
          parentQuery: parentQuery,
          imageUrl: widget.imageUrl, // ✅ Pass imageUrl for image search
        ).timeout(
          const Duration(seconds: 90), // 90 second timeout (longer than backend timeout)
          onTimeout: () {
            print('⏱️ Frontend timeout after 90 seconds');
            return {
              'success': false,
              'error': 'Request timeout',
              'summary': 'The request took too long. Please try again.',
              'intent': 'answer',
              'results': [],
              'sources': [],
            };
          },
        );
        print('Agent Response: $responseData');
        print('=== AGENT RESPONSE DEBUG ===');
        print('Response intent: ${responseData['intent']}');
        print('Results count: ${responseData['results']?.length ?? 0}');
        final summaryPreview = responseData['summary']?.toString() ?? '';
        print('Summary: ${summaryPreview.length > 100 ? summaryPreview.substring(0, 100) + '...' : summaryPreview}');
        if (responseData['results'] != null && responseData['results'].isNotEmpty) {
          print('First result keys: ${responseData['results'][0].keys.toList()}');
          if (responseData['results'][0]['thumbnail'] != null) {
            print('First result thumbnail: ${responseData['results'][0]['thumbnail']}');
        }
        }
      } on TimeoutException catch (e) {
        print('⏱️ Frontend timeout: $e');
        // Show timeout message
        if (mounted) {
          setState(() {
            conversationHistory[sessionIndex] = session.copyWith(
              isLoading: false,
            );
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request timed out. Please try again.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      } catch (e) {
        print('Agent API call failed: $e');
        print('Error type: ${e.runtimeType}');
        // Show error message instead of mock data
        if (mounted) {
          setState(() {
            conversationHistory[sessionIndex] = session.copyWith(
              isLoading: false,
            );
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Request failed: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // ✅ PART 1: Extract and map intent correctly
      final raw = responseData['intent']?.toString().toLowerCase() ?? "general";
      
      String resultType;
      if (raw.contains("answer") || raw == "general") resultType = "answer";  // ✅ Fix: Handle "answer" intent properly
      else if (raw.contains("shop")) resultType = "shopping";
      else if (raw.contains("hotel")) resultType = "hotel";
      else if (raw.contains("flight")) resultType = "flights";
      else if (raw.contains("restaurant") || raw.contains("food")) resultType = "restaurants";
      else if (raw.contains("places")) resultType = "places";  // 🎯 Places intent
      else if (raw.contains("location") || raw.contains("place") || raw.contains("attraction")) resultType = "location";
      else if (raw.contains("movie") || raw.contains("film")) resultType = "movies";  // ✅ Add movies intent
      else resultType = "answer";  // ✅ Fix: Default to "answer" instead of "general"
      
      // ✅ Read cards from multiple possible fields (results, cards, products)
      final dynamic rawResults = responseData['results'] ?? 
                                  responseData['cards'] ?? 
                                  responseData['products'] ?? 
                                  [];
      final List<dynamic> results = rawResults is List ? rawResults : [];
      print('🔍 BACKEND RESPONSE DEBUG:');
      print('  - Raw intent: "$raw"');
      print('  - Mapped resultType: "$resultType"');
      print('  - Results count: ${results.length}');
      final summaryText = responseData['summary']?.toString() ?? '';
      print('  - Summary: ${summaryText.length > 100 ? summaryText.substring(0, 100) + '...' : summaryText}');
      print('  - Full response keys: ${responseData.keys.toList()}');
      
      // ✅ PART 2: Unified renderer for all card types
      // Extract follow-ups from backend
      final followUps = responseData['followUps'] ?? responseData['followUpSuggestions'] ?? [];
      final followUpList = followUps is List 
          ? followUps.map((e) => e.toString()).toList()
          : <String>[];
      
      // ✅ PART 3: Fix follow-up generation duplication
      final prev = conversationHistory[sessionIndex].query.toLowerCase();
      final cleaned = followUpList
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.toLowerCase().contains(prev))
          .toList();
      final finalFollowUps = cleaned.take(3).toList();
      
      // ✅ PART 4: Add missing summary fallback
      final cleanSummary = cleanMarkdown(
        responseData['summary'] ??
        responseData['answer'] ??
        "Here are the details you're looking for:"
      );
      
      // Handle each intent type with unified renderer
      if (resultType == "shopping") {
        final products = results.map<Product>((item) {
          try {
            return _mapShoppingResultToProduct(item);
          } catch (e) {
            print('Error mapping product: $e, Item: $item');
            return Product(
              id: DateTime.now().millisecondsSinceEpoch,
              title: 'Error loading product',
              description: 'Unable to load product details',
              price: 0.0,
              source: 'Error',
              rating: 0.0,
              images: [],
              variants: [],
            );
          }
        }).toList();
        
        // ✅ PATCH E3: Throttle setState calls (prevents rebuilding during frame rendering)
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              conversationHistory[sessionIndex] = session.copyWith(
                products: products,
                resultType: resultType,
                isLoading: false,
                summary: cleanSummary,
                intent: responseData['intent']?.toString(),
                cardType: responseData['cardType']?.toString(),
                cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
                rawResults: (responseData['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
                followUpSuggestions: finalFollowUps.isNotEmpty ? finalFollowUps : session.followUpSuggestions,
              );
            });
          }
        });
      } else if (resultType == "hotel") {
        // ✅ Perplexity-style: Check if backend returned sections + map structure
        final sections = responseData['sections'] as List?;
        final mapPoints = responseData['map'] as List?;
        
        // Extract all hotels from sections for backward compatibility
        final List<Map<String, dynamic>> hotelResults = [];
        if (sections != null && sections.isNotEmpty) {
          // New grouped structure
          for (final section in sections) {
            if (section is Map && section['items'] != null) {
              final items = section['items'] as List?;
              if (items != null) {
                hotelResults.addAll(items.map((e) => Map<String, dynamic>.from(e as Map)));
              }
            }
          }
        } else {
          // Fallback: old flat structure
          hotelResults.addAll(results.map((e) => Map<String, dynamic>.from(e as Map)));
        }
        
        // Parse sections and map points
        final List<Map<String, dynamic>> parsedSections = [];
        if (sections != null) {
          for (final section in sections) {
            if (section is Map) {
              parsedSections.add(Map<String, dynamic>.from(section));
            }
          }
        }
        
        final List<Map<String, dynamic>> parsedMapPoints = [];
        if (mapPoints != null) {
          print('🗺️ Parsing ${mapPoints.length} map points from backend');
          for (final point in mapPoints) {
            if (point is Map) {
              final parsedPoint = Map<String, dynamic>.from(point);
              parsedMapPoints.add(parsedPoint);
              print('  - Map point: ${parsedPoint['name']} - lat: ${parsedPoint['lat'] ?? parsedPoint['latitude']}, lng: ${parsedPoint['lng'] ?? parsedPoint['longitude']}');
            }
          }
          print('✅ Successfully parsed ${parsedMapPoints.length} map points');
        } else {
          // print('⚠️ No map points in response (mapPoints is null)');
        }
        
        print('🏨 Hotel response: ${parsedSections.length} sections, ${hotelResults.length} total hotels, ${parsedMapPoints.length} map points');
        
        // ✅ PATCH C2: Preprocess response ONCE after API returns
        final processed = _preprocessResponse(responseData);
        
        setState(() {
          _processedResult = processed;
          conversationHistory[sessionIndex] = session.copyWith(
            hotelResults: hotelResults,
            resultType: resultType,
            isLoading: false,
            summary: cleanSummary,
            intent: responseData['intent']?.toString(),
            cardType: responseData['cardType']?.toString(),
            cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
            rawResults: hotelResults,
            followUpSuggestions: finalFollowUps.isNotEmpty ? finalFollowUps : session.followUpSuggestions,
            hotelSections: parsedSections.isNotEmpty ? parsedSections : null,
            hotelMapPoints: parsedMapPoints.isNotEmpty ? parsedMapPoints : null,
          );
        });
      } else if (resultType == "restaurants" || resultType == "flights" || resultType == "movies") {
        final List<Map<String, dynamic>> typedResults = results
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        
        // ✅ PATCH E3: Throttle setState calls (prevents rebuilding during frame rendering)
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              conversationHistory[sessionIndex] = session.copyWith(
                rawResults: typedResults,
                resultType: resultType,
                isLoading: false,
                summary: cleanSummary,
                products: [],
                hotelResults: [],
                intent: responseData['intent']?.toString(),
                cardType: responseData['cardType']?.toString(),
                cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                followUpSuggestions: finalFollowUps.isNotEmpty ? finalFollowUps : session.followUpSuggestions,
              );
            });
          }
        });
      } else if (resultType == "location") {
        final List<Map<String, dynamic>> locationResults = results
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        
        // ✅ PATCH C2: Preprocess response ONCE after API returns
        final processed = _preprocessResponse(responseData);
        
        setState(() {
          _processedResult = processed;
          conversationHistory[sessionIndex] = session.copyWith(
            locationCards: locationResults,
            resultType: resultType,
            isLoading: false,
            summary: cleanSummary,
            products: [],
            hotelResults: [],
            intent: responseData['intent']?.toString(),
            cardType: responseData['cardType']?.toString(),
            cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
            followUpSuggestions: finalFollowUps.isNotEmpty ? finalFollowUps : session.followUpSuggestions,
          );
        });
      } else if (resultType == "places") {
        // 🎯 Places results handling
        final List<Map<String, dynamic>> placesResults = results
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        
        // ✅ PATCH C2: Preprocess response ONCE after API returns
        final processed = _preprocessResponse(responseData);
        
        // ✅ PATCH E3: Throttle setState calls (prevents rebuilding during frame rendering)
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _processedResult = processed;
              conversationHistory[sessionIndex] = session.copyWith(
                locationCards: placesResults, // Reuse locationCards for places
                rawResults: placesResults, // Also store in rawResults
                resultType: resultType,
                isLoading: false,
                summary: cleanSummary,
                products: [],
                hotelResults: [],
                intent: responseData['intent']?.toString(),
                cardType: responseData['cardType']?.toString(),
                cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                followUpSuggestions: finalFollowUps.isNotEmpty ? finalFollowUps : session.followUpSuggestions,
              );
            });
          }
        });
      } else {
        // ✅ Fix: Handle "answer" intent - display answer directly (not streaming)
        // The backend already generated the answer, so we just need to display it
        setState(() {
          conversationHistory[sessionIndex] = session.copyWith(
            resultType: resultType, // Should be "answer"
            isLoading: false,
            summary: cleanSummary, // ✅ Use the answer from backend
            products: [],
            hotelResults: [],
            intent: responseData['intent']?.toString(),
            cardType: responseData['cardType']?.toString(),
            cards: (responseData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
            rawResults: [],
            followUpSuggestions: finalFollowUps.isNotEmpty ? finalFollowUps : session.followUpSuggestions,
            sources: (responseData['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
            locationCards: (responseData['locations'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
            destinationImages: (responseData['destination_images'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [],
          );
        });
      }
      
      // ✅ PART 2: Only scroll to top for FIRST query (index 0)
      // For follow-up queries, we already scrolled to the new query when it was submitted
      // DO NOT scroll to top for follow-up queries - this would reset the scroll position!
      if (sessionIndex == 0) {
        // First query only - scroll to top
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else {
        // Follow-up query - ensure we're still scrolled to show the new query at top
        // Don't reset scroll position - keep the new query visible at top
      WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients && sessionIndex < _queryKeys.length) {
            final key = _queryKeys[sessionIndex];
            final context = key.currentContext;
            if (context != null) {
              // Re-position the new query at TOP after results load
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 0),
                alignment: 0.0, // Top of viewport
                curve: Curves.linear,
              );
              print('✅ Re-positioned follow-up query at TOP after results loaded (index: $sessionIndex)');
            }
          }
        });
      }
      
      // Only generate follow-ups if backend didn't provide them
      if (finalFollowUps.isEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && sessionIndex < conversationHistory.length) {
            _generateFollowUpSuggestions(sessionIndex, cleanSummary);
          }
        });
      }
    } catch (e) {
      print('Error loading results: $e');
      // Show error in the UI
      setState(() {
        conversationHistory[sessionIndex] = conversationHistory[sessionIndex].copyWith(
          isLoading: false,
          // Add error state - you might want to add an error field to QuerySession
        );
      });
      
      // Show error dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(sessionIndex);
        _showErrorDialog('Failed to load results: $e');
      });
    }
  }

  // Map backend shopping results to Product objects
  Product _mapShoppingResultToProduct(Map<String, dynamic> item) {
    // Parse price from string (e.g., "$29.99" -> 29.99)
    double parsePrice(dynamic priceValue) {
      if (priceValue == null) return 0.0;
      final priceStr = priceValue.toString().trim();
      if (priceStr.isEmpty || priceStr == '') return 0.0;
      final cleanPrice = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleanPrice) ?? 0.0;
    }

    // Parse rating from string (e.g., "4.5" -> 4.5)
    double parseRating(dynamic ratingValue) {
      if (ratingValue == null) return 0.0;
      final ratingStr = ratingValue.toString().trim();
      if (ratingStr.isEmpty || ratingStr == '') return 0.0;
      return double.tryParse(ratingStr) ?? 0.0;
    }

    // Safe string extraction
    String safeString(dynamic value, String fallback) {
      if (value == null) return fallback;
      final str = value.toString().trim();
      return str.isEmpty ? fallback : str;
    }

    final price = parsePrice(item['price'] ?? item['extracted_price']);
    final oldPrice = parsePrice(item['old_price']);
    final thumbnail = item['thumbnail'];
    
    print('=== PRODUCT PARSING DEBUG ===');
    print('Title: ${item['title']}');
    print('Thumbnail: $thumbnail');
    print('Thumbnail type: ${thumbnail.runtimeType}');
    print('All item keys: ${item.keys.toList()}');
    
    final productId = DateTime.now().millisecondsSinceEpoch + (item['title']?.toString().hashCode ?? 0);
    final link = safeString(item['link'], '');
    
    // Store link in map for later retrieval
    if (link.isNotEmpty) {
      _productLinks[productId] = link;
    }
    
    // Handle images with fallback to thumbnail
    final List<String> imageList = (item['images'] != null && item['images'] is List && (item['images'] as List).isNotEmpty)
        ? List<String>.from((item['images'] as List).where((img) => img != null && img.toString().isNotEmpty).map((img) => img.toString()))
        : (thumbnail != null && thumbnail.toString().isNotEmpty)
            ? [thumbnail.toString()]
            : [];
    
    return Product(
      id: productId,
      title: safeString(item['title'], 'Unknown Product'),
      description: safeString(
        item['snippet'] ?? 
        item['description'] ?? 
        (item['extensions'] != null && (item['extensions'] as List).isNotEmpty 
          ? (item['extensions'] as List).join(', ') 
          : null) ??
        item['tag'] ?? 
        item['delivery'], 
        'No description available'
      ),
      price: price,
      discountPrice: oldPrice > price ? oldPrice : null,
      source: safeString(item['source'], 'Unknown Source'),
      rating: parseRating(item['rating']),
      images: imageList,
      variants: [],
    );
  }

  // Safe hotel data extraction
  Map<String, dynamic> _extractHotelData(Map<String, dynamic> hotel) {
    // Safe string extraction
    String safeString(dynamic value, String fallback) {
      if (value == null) return fallback;
      final str = value.toString().trim();
      return str.isEmpty ? fallback : str;
    }


    // Safe int extraction
    int safeInt(dynamic value, int fallback) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is double) return value.toInt();
      final str = value.toString().trim();
      if (str.isEmpty) return fallback;
      return int.tryParse(str) ?? fallback;
    }

    // Safe amenities extraction
    List<String> safeAmenities(dynamic value) {
      if (value == null) return <String>[];
      if (value is List) {
        return value.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
      }
      return <String>[];
    }

    // Handle images - properly extract from images array with exterior image first
    List<String> getImages() {
      final List<String> imageUrls = [];
      
      // Get all images from the images array first
      final images = hotel['images'];
      if (images != null && images is List && images.isNotEmpty) {
        for (final img in images) {
          if (img is String && img.isNotEmpty) {
            imageUrls.add(img);
          } else if (img is Map && img['thumbnail'] != null) {
            final thumbnailUrl = img['thumbnail'].toString();
            if (thumbnailUrl.isNotEmpty) {
              imageUrls.add(thumbnailUrl);
            }
          }
        }
      }
      
      // If no images from images array, fallback to thumbnail
      if (imageUrls.isEmpty) {
        final thumbnail = hotel['thumbnail'];
        if (thumbnail != null && thumbnail.toString().isNotEmpty) {
          imageUrls.add(thumbnail.toString());
        }
      }
      
    return imageUrls;
  }

  // Extract description from multiple possible fields
  String _extractDescription(Map<String, dynamic> hotel) {
    // Try multiple description fields
    final description = safeString(hotel['description'], '');
    if (description.isNotEmpty && description != 'No description available') {
      return description;
    }
    
    final summary = safeString(hotel['summary'], '');
    if (summary.isNotEmpty) {
      return summary;
    }
    
    final overview = safeString(hotel['overview'], '');
    if (overview.isNotEmpty) {
      return overview;
    }
    
    final about = safeString(hotel['about'], '');
    if (about.isNotEmpty) {
      return about;
    }
    
    final details = safeString(hotel['details'], '');
    if (details.isNotEmpty) {
      return details;
    }
    
    // If no description, return empty string (don't show features)
    return '';
  }

  // Extract location from multiple possible fields
    String location = '';
    
    // Try address first
    location = safeString(hotel['address'], '');
    
    // If no address, try location field
    if (location.isEmpty) {
      location = safeString(hotel['location'], '');
    }
    
    // If still no location, try building from city, state, country
    if (location.isEmpty) {
      final city = safeString(hotel['city'], '');
      final state = safeString(hotel['state'], '');
      final country = safeString(hotel['country'], '');
      if (city.isNotEmpty || state.isNotEmpty || country.isNotEmpty) {
        location = [city, state, country].where((s) => s.isNotEmpty).join(', ');
      }
    }
    
    // If still no location, try other possible fields
    if (location.isEmpty) {
      location = safeString(hotel['place'], '');
    }
    if (location.isEmpty) {
      location = safeString(hotel['destination'], '');
    }
    
    // If still no location, try to extract from hotel name
    if (location.isEmpty) {
      final hotelName = safeString(hotel['name'], '');
      // Common patterns: "Hotel Name City", "Hotel Name in City", "Hotel Name at City"
      final nameParts = hotelName.split(' ');
      if (nameParts.length >= 3) {
        // Try to extract city from the end of the name
        final possibleCity = nameParts.last;
        if (possibleCity.length > 2 && !possibleCity.toLowerCase().contains('hotel')) {
          location = possibleCity;
        }
      }
    }
    
    // Only show "Location not specified" if truly no location data
    if (location.isEmpty) {
      location = 'Location not specified';
    }

    // Extract price from multiple possible fields
    double price = safeNumber(hotel['price'], 0.0);
    if (price == 0.0) {
      // Try to extract from rate_per_night
      final ratePerNight = hotel['rate_per_night'];
      if (ratePerNight != null && ratePerNight is Map) {
        final lowest = ratePerNight['lowest'];
        if (lowest != null) {
          price = safeNumber(lowest, 0.0);
        }
      }
    }

    return {
      'name': safeString(hotel['title'] ?? hotel['name'], 'Unknown Hotel'), // Backend sends 'title'
      'location': location,
      'address': safeString(hotel['address'], ''), // Preserve original address field
      'rating': safeNumber(hotel['rating'], 0.0),
      'reviewCount': safeInt(hotel['reviews'], 0),
      'price': price,
      'originalPrice': safeNumber(hotel['originalPrice'], 0.0),
      'description': _extractDescription(hotel),
      'thumbnail': safeString(hotel['thumbnail'], ''),
      'link': safeString(hotel['link'], ''),
      'amenities': safeAmenities(hotel['amenities']),
      'images': getImages(), // Extract images using getImages() method
      // Preserve coordinate data for directions
      'gps_coordinates': hotel['gps_coordinates'],
      'geo': hotel['geo'],
      'latitude': hotel['latitude'],
      'longitude': hotel['longitude'],
    };
  }


  // Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Mock hotel data method - now replaced with real API calls
  // Future<List<Map<String, dynamic>>> _loadHotelResults(String query) async {
  //   // This method is no longer used - replaced with ApiService.search()
  //   return [];
  // }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ STEP 3: Required for AutomaticKeepAliveClientMixin
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Dismiss keyboard before navigation
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent, // Changed from opaque to allow scrolling
        onTap: () {
          FocusScope.of(context).unfocus(); // dismiss keyboard on any tap
        },
        child: Column(
        children: [
          // Conversation history
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: conversationHistory.length,
              itemBuilder: (context, index) {
                final session = conversationHistory[index];
                return _buildQuerySession(session, index);
              },
            ),
          ),
          
          // Follow-up input bar
          _buildFollowUpBar(),
        ],
        ),
      ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () {
          // Dismiss keyboard immediately
          FocusScope.of(context).unfocus();
          // Small delay to ensure keyboard dismissal
          Future.delayed(const Duration(milliseconds: 100), () {
            Navigator.pop(context);
          });
        },
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.bookmark_border),
          onPressed: () {
            // TODO: Implement bookmark functionality
          },
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: () {
            // TODO: Implement share functionality
          },
        ),
      ],
    );
  }

  Widget _buildQuerySession(QuerySession session, int index) {
    // Always show the query title and structure, even when loading
    return Padding(
      key: ValueKey('session-$index'), // ✅ FIX: Remove isLoading from key to prevent reloading on scroll
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8), // Reduced horizontal padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Important: Allow ListView to scroll
        children: [
          // 🟩 Query Title (with GlobalKey attached for scrolling)
          Padding(
            key: (index < _queryKeys.length) ? _queryKeys[index] : GlobalKey(),
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              session.query,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          
          // Show loading state if query is loading
          if (session.isLoading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            // Show content when loaded
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Important: Allow ListView to scroll
              children: [

                  // ✅ TAGS (Clonar, Dynamic Intent Tag, Images, Sources)
                  // Use AnswerHeaderRow for answer queries without products, regular tags for others
                  // If products exist, show "Shopping" tag even if resultType is "answer"
                  if (session.resultType == 'answer' && session.products.isEmpty)
                    AnswerHeaderRow(
                      baseTags: const ['Clonar', 'Answer'],
                      sources: session.sources != null 
                          ? (session.sources as List).map((s) {
                              if (s is Map<String, dynamic>) return s;
                              if (s is Map) return Map<String, dynamic>.from(s);
                              // If it's a string, convert to map format
                              if (s is String) return {'title': s, 'link': s};
                              return {'title': s.toString(), 'link': ''};
                            }).toList().cast<Map<String, dynamic>>()
                          : [],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Clonar tag with better styling
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
                            color: AppColors.surfaceVariant, // Dark theme background
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Clonar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Dynamic tag based on intent (enhanced)
                        // If products exist, show "Shopping" tag even if resultType is "answer"
                        _buildIntentTag(
                          session.products.isNotEmpty ? 'shopping' : session.resultType, 
                          session
                        ),
                        // ✅ Bookable experiences button for places queries
                        if ((session.resultType == 'places' || session.resultType == 'location') && session.cards.isNotEmpty)
                          _buildBookableExperiencesButton(session),
                        // ✅ Movie-specific tags: In Cinemas/Out of Cinemas, Showtimes (only if in theaters), Cast & Crew, Trailers & Clips, Reviews
                        if (session.resultType == 'movies' && session.cards.isNotEmpty) ...[
                              // In Cinemas / Out of Cinemas tag
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _isMovieInTheaters(session.cards[0])
                                      ? Colors.green.withOpacity(0.2)
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _isMovieInTheaters(session.cards[0])
                                        ? Colors.green
                                        : AppColors.border,
                                    width: 1,
        ),
      ),
      child: Row(
                                  mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
                                      _isMovieInTheaters(session.cards[0])
                                          ? Icons.movie
                                          : Icons.movie_outlined,
                                      size: 14,
                                      color: _isMovieInTheaters(session.cards[0])
                                          ? Colors.green
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isMovieInTheaters(session.cards[0])
                                          ? 'In Cinemas'
                                          : 'Out of Cinemas',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _isMovieInTheaters(session.cards[0])
                                            ? Colors.green
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Showtimes tag - only show if movie is currently in theaters
                              if (_isMovieInTheaters(session.cards[0]))
                                GestureDetector(
                                  onTap: () {
                                    final firstMovie = session.cards[0];
                                    final movieId = firstMovie['id'] as int? ?? 0;
                                    if (movieId > 0) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => MovieDetailScreen(
                                            movieId: movieId,
                                            movieTitle: firstMovie['title']?.toString(),
                                            initialTabIndex: 2, // Showtimes tab
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceVariant,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.schedule, size: 14, color: AppColors.textPrimary),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Showtimes',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // Cast & Crew tag
                              GestureDetector(
                                onTap: () {
                                  final firstMovie = session.cards[0];
                                  final movieId = firstMovie['id'] as int? ?? 0;
                                  if (movieId > 0) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MovieDetailScreen(
                                          movieId: movieId,
                                          movieTitle: firstMovie['title']?.toString(),
                                          initialTabIndex: 1, // Cast tab
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.people, size: 14, color: AppColors.textPrimary),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Cast & Crew',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Trailers & Clips tag
                              GestureDetector(
                                onTap: () {
                                  final firstMovie = session.cards[0];
                                  final movieId = firstMovie['id'] as int? ?? 0;
                                  if (movieId > 0) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MovieDetailScreen(
                                          movieId: movieId,
                                          movieTitle: firstMovie['title']?.toString(),
                                          initialTabIndex: 3, // Trailers tab
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_circle_outline, size: 14, color: AppColors.textPrimary),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Trailers & Clips',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Reviews tag
                              GestureDetector(
                                onTap: () {
                                  final firstMovie = session.cards[0];
                                  final movieId = firstMovie['id'] as int? ?? 0;
                                  if (movieId > 0) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MovieDetailScreen(
                                          movieId: movieId,
                                          movieTitle: firstMovie['title']?.toString(),
                                          initialTabIndex: 4, // Reviews tab
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star_outline, size: 14, color: AppColors.textPrimary),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Reviews',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                      ],
                    ),
                  const SizedBox(height: 12),

                  // ✅ SUMMARY (skip for answer queries, places queries, hotels, and movies - shown in intent content)
                  if (session.resultType != 'answer' && session.resultType != 'places' && session.resultType != 'location' && session.resultType != 'movies' && session.resultType != 'hotel')
                    _buildSummarySection(session, index),

                  if (session.resultType != 'answer' && session.resultType != 'places' && session.resultType != 'location' && session.resultType != 'movies' && session.resultType != 'hotel')
                    const SizedBox(height: 12),

                  // ✅ SHOW RESULTS BASED ON INTENT TYPE
                  _buildIntentBasedContent(session),

                  const SizedBox(height: 40),
              ],
            ),
        ],
      ),
    );
  }

  // 🎯 Intent-based content rendering
  Widget _buildIntentBasedContent(QuerySession session) {
    final intent = session.resultType;
    
    // 🧾 Informational/OpenAI Answers (with streaming support) - No box, clean text
    if (intent == 'answer') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show streaming indicator if still streaming
          if (session.isStreaming)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                '⌛ Thinking...',
                style: TextStyle(
                  fontSize: 14,
                color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
              ),
            ),
          ),
          // Display answer text with inline location cards (Perplexity-style)
          _buildAnswerWithInlineLocationCards(session),
          // Show products if available (for product queries that were classified as "answer")
          if (session.products.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              "Popular Models",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // ✅ PATCH D1: Give every list item a stable key (prevents unnecessary rebuilds)
            ...session.products.map((p) {
              final id = p.id.toString();
              return KeyedSubtree(
                key: ValueKey(id),
                child: _buildProductCard(p),
              );
            }).toList(),
          ],
          // Show follow-up suggestions after answer is complete (Perplexity-style, no heading)
          Builder(
            builder: (context) {
              debugPrint('🔍 Rendering answer content - isStreaming: ${session.isStreaming}, suggestions count: ${session.followUpSuggestions.length}');
              if (!session.isStreaming && session.followUpSuggestions.isNotEmpty) {
                debugPrint('✅ Displaying ${session.followUpSuggestions.length} follow-up suggestions');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    ...session.followUpSuggestions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final suggestion = entry.value;
                      return _buildFollowUpSuggestionItem(suggestion, index, session: session);
                    }),
                  ],
                );
              } else {
                debugPrint('⚠️ Not showing suggestions - isStreaming: ${session.isStreaming}, suggestions: ${session.followUpSuggestions.length}');
                return const SizedBox.shrink();
              }
            },
          ),
        ],
      );
    }
    
    // 🛍️ Shopping Layout
    if (intent == 'shopping') {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          const Text(
            "Popular Models",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (session.products.isNotEmpty)
            ...session.products.map((p) => _buildProductCard(p)).toList()
          else
            _buildEmptyProductsState(),
          // Show follow-up suggestions (Perplexity-style, no heading)
          if (session.followUpSuggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...session.followUpSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return _buildFollowUpSuggestionItem(suggestion, index);
            }),
          ],
        ],
      );
    }
    
    // 🏨 Hotel Layout (Perplexity-style - EXACT MATCH)
    if (intent == 'hotel' || intent == 'hotels') {
      // Check if we have the new grouped structure
      final hasSections = session.hotelSections != null && session.hotelSections!.isNotEmpty;
      final hasMapPoints = session.hotelMapPoints != null && session.hotelMapPoints!.isNotEmpty;
      
      // Debug logging
      print('🗺️ Hotel layout check:');
      print('  - intent: $intent');
      print('  - hasSections: $hasSections');
      print('  - hasMapPoints: $hasMapPoints');
      print('  - hotelMapPoints: ${session.hotelMapPoints?.length ?? 0}');
      if (session.hotelMapPoints != null && session.hotelMapPoints!.isNotEmpty) {
        print('  - First map point: ${session.hotelMapPoints![0]}');
      }
      
      return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Important: Allow ListView to scroll
            children: [
          // ✅ STEP 1: Map FIRST (immediately after tags) - Real Google Maps implementation
          if (hasMapPoints && session.hotelMapPoints != null) ...[
              Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16), // Left and right padding
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapScreen(
                        points: session.hotelMapPoints!,
                        title: widget.query,
                      ),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    HotelMapView(
                      points: session.hotelMapPoints!,
                      height: MediaQuery.of(context).size.height * 0.65, // Increased map size
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => FullScreenMapScreen(
                              points: session.hotelMapPoints!,
                              title: widget.query,
                            ),
                          ),
                        );
                      },
                    ),
                    // Visual indicator at bottom
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen, color: AppColors.textPrimary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Tap to view full screen',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // ✅ STEP 2: Description text (after map) - Perplexity style with animation
          if (session.summary != null && session.summary!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0), // Keep some padding for text readability
              child: Builder(
                builder: (context) {
                  final animKey = 'answer-${session.query.hashCode}';
                  final shouldAnimate = !_hasAnimated.containsKey(animKey);
                  return PerplexityTypingAnimation(
                    text: session.summary!,
                    isStreaming: session.isStreaming,
                    animate: shouldAnimate,
                    onAnimationComplete: () {
                      _hasAnimated[animKey] = true;
                    },
                    textStyle: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                    animationDuration: const Duration(milliseconds: 30),
                    wordsPerTick: 1,
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          // ✅ STEP 3: Hotel sections (after description) - Perplexity style
          // Hotels displayed VERTICALLY (one after another), with section headings
          Builder(
            builder: (context) {
              print('🏨 Rendering hotel sections: hasSections=$hasSections, sections count=${session.hotelSections?.length ?? 0}');
              if (hasSections) {
                return Column(
                  children: session.hotelSections!.map((section) {
                    final title = section['title']?.toString() ?? 'Hotels';
                    final items = (section['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
                    
                    print('🏨 Section "$title" has ${items.length} items');
                    if (items.isEmpty) {
                      // print('⚠️ Section "$title" is empty, skipping');
                      return const SizedBox.shrink(); // Hide empty sections
                    }
              
                    // Limit initial rendering to prevent blocking (show first 5, rest load on scroll)
                    final itemsToShow = items.length > 5 ? items.take(5).toList() : items;
              
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, // Important: Allow parent ListView to scroll
                      children: [
                        // Section header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Vertical list of hotels (one after another) - Limited to prevent blocking
                        ...itemsToShow.asMap().entries.map((entry) {
                          final index = entry.key;
                          final hotel = entry.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0), // No horizontal padding - full width
                            child: Column(
                              children: [
                                // ✅ PATCH D1: Give every list item a stable key
                                KeyedSubtree(
                                  key: ValueKey(hotel['id']?.toString() ?? hotel['name']?.toString() ?? 'hotel-$index'),
                                  child: _buildHotelCard(hotel, isHorizontal: false), // Vertical card layout
                                ),
                                if (index < itemsToShow.length - 1) const SizedBox(height: 20), // Spacing between hotels
                              ],
                            ),
                          );
                        }).toList(),
                        // Show "Load more" if there are more items
                        if (items.length > 5) ...[
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '${items.length - 5} more hotels available',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24), // More spacing between sections
                      ],
                    );
                  }).toList(),
                );
              } else if (session.hotelResults.isNotEmpty) {
                // Fallback: Old flat list view
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0), // No horizontal padding - full width
                  child: Column(
                    children: session.hotelResults.asMap().entries.map((entry) {
                      final index = entry.key;
                      final hotel = entry.value;
                      return Column(
                        children: [
                          // ✅ PATCH D1: Give every list item a stable key
                          KeyedSubtree(
                            key: ValueKey(hotel['id']?.toString() ?? hotel['name']?.toString() ?? 'hotel-$index'),
                            child: _buildHotelCard(hotel),
                          ),
                          if (index < session.hotelResults.length - 1) const SizedBox(height: 20),
                        ],
                      );
                    }).toList(),
                  ),
                );
              } else {
                return _buildEmptyHotelsState();
              }
            },
          ),
          
          // Show follow-up suggestions (Perplexity-style, no heading)
          if (session.followUpSuggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...session.followUpSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return _buildFollowUpSuggestionItem(suggestion, index);
            }),
          ],
        ],
      );
    }
    
    // 🖼️ Image Search Layout
    if (intent == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image, color: Colors.blueGrey, size: 20),
              const SizedBox(width: 6),
              const Text(
                "Image Results",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (session.rawResults.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: session.rawResults.length,
              itemBuilder: (context, index) {
                final image = session.rawResults[index];
                final thumbnail = image['thumbnail']?.toString() ?? '';
                return GestureDetector(
                  onTap: () async {
                    if (image['link'] != null) {
                      final url = Uri.parse(image['link']);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: thumbnail.isNotEmpty
                        ? Image.network(
                            thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.surfaceVariant,
                                child: Icon(Icons.image_not_supported, color: AppColors.textSecondary),
                              );
                            },
                          )
                        : Container(
                            color: AppColors.surfaceVariant,
                            child: Icon(Icons.image_not_supported, color: AppColors.textSecondary),
                          ),
                  ),
                );
              },
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "No images found",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          // Show follow-up suggestions (Perplexity-style, no heading)
          if (session.followUpSuggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...session.followUpSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return _buildFollowUpSuggestionItem(suggestion, index);
            }),
          ],
        ],
      );
    }
    
    // 🍽️ Restaurants/Local Layout
    if (intent == 'restaurants' || intent == 'local') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant, color: Colors.blueGrey, size: 20),
              const SizedBox(width: 6),
              Text(
                intent == 'restaurants' ? "Restaurants" : "Local Results",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
        ),
        const SizedBox(height: 8),
          if (session.rawResults.isNotEmpty)
            ...session.rawResults.map((place) => _buildLocalCard(place)).toList()
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "No results found",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          // Show follow-up suggestions (Perplexity-style, no heading)
          if (session.followUpSuggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...session.followUpSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return _buildFollowUpSuggestionItem(suggestion, index);
            }),
          ],
        ],
      );
    }
    
    // 🎯 Places Layout (Perplexity-style: intro paragraph + section grouping + cards)
    if (intent == 'places' || intent == 'location') {
      // ✅ Read cards from multiple possible fields
      final dynamic finalCards = session.cards.isNotEmpty 
          ? session.cards 
          : (session.locationCards.isNotEmpty 
              ? session.locationCards 
              : (session.rawResults.isNotEmpty 
                  ? session.rawResults 
                  : []));
      
      // Group places by section (Perplexity-style)
      final Map<String, List<dynamic>> groupedPlaces = {};
      if (finalCards is List && finalCards.isNotEmpty) {
        for (final place in finalCards) {
          final section = place['section']?.toString() ?? 'Top Sights';
          if (!groupedPlaces.containsKey(section)) {
            groupedPlaces[section] = [];
          }
          groupedPlaces[section]!.add(place);
        }
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Perplexity-style: Intro paragraph from summary with animation
          if (session.summary != null && session.summary!.isNotEmpty) ...[
            Builder(
              builder: (context) {
                final animKey = 'answer-${session.query.hashCode}';
                final shouldAnimate = !_hasAnimated.containsKey(animKey);
                return PerplexityTypingAnimation(
                  text: session.summary!,
                  isStreaming: session.isStreaming,
                  animate: shouldAnimate,
                  onAnimationComplete: () {
                    _hasAnimated[animKey] = true;
                  },
                  textStyle: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    height: 1.6,
                  ),
                  animationDuration: const Duration(milliseconds: 30),
                  wordsPerTick: 1,
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          
          // Render grouped places by section
          if (groupedPlaces.isNotEmpty) ...[
            ...groupedPlaces.entries.map((entry) {
              final sectionName = entry.key;
              final places = entry.value;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section heading (only if multiple sections or section is not "Top Sights")
                  if (groupedPlaces.length > 1 || sectionName != 'Top Sights') ...[
                    Text(
                      sectionName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Places in this section
                  // ✅ PATCH D1: Give every list item a stable key
                  ...places.map((place) {
                    final id = place['name']?.toString() ?? place['title']?.toString() ?? UniqueKey().toString();
                    return KeyedSubtree(
                      key: ValueKey(id),
                      child: _buildPlaceCard(place),
                    );
                  }).toList(),
                ],
              );
            }),
          ] else if (finalCards is List && finalCards.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "No places found",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
          
          // Show follow-up suggestions (Perplexity-style, no heading)
          if (session.followUpSuggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...session.followUpSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return _buildFollowUpSuggestionItem(suggestion, index);
            }),
          ],
        ],
      );
    }
    
    // 🎬 Movies Layout
    if (intent == 'movies') {
      final movieCards = session.cards.isNotEmpty 
          ? session.cards 
          : (session.rawResults.isNotEmpty ? session.rawResults : []);
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Use renderCards to display movie cards
          if (movieCards.isNotEmpty)
            renderCards('movies', movieCards)
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "No movies found",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          // Show follow-up suggestions (Perplexity-style, no heading)
          if (session.followUpSuggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...session.followUpSuggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return _buildFollowUpSuggestionItem(suggestion, index);
            }),
          ],
        ],
      );
    }
    
    // 🌐 Fallback if no results
    return Container(
      padding: const EdgeInsets.all(16),
      child: Text(
        "No results found for this query.",
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  // 🏷️ Build intent tag with icon
  Widget _buildIntentTag(String intent, QuerySession session) {
    IconData icon;
    String label;
    
    switch (intent) {
      case 'shopping':
        icon = Icons.shopping_bag;
        label = 'Shopping';
        break;
      case 'hotel':
        icon = Icons.hotel;
        label = 'Hotels';
        break;
      case 'image':
        icon = Icons.image;
        label = 'Images';
        break;
      case 'answer':
        icon = Icons.info_outline;
        label = 'Answer';
        break;
      case 'restaurants':
      case 'local':
        icon = Icons.restaurant;
        label = 'Restaurants';
        break;
      case 'places':
        icon = Icons.place;
        label = 'Places';
        break;
      default:
        icon = Icons.search;
        label = intent.capitalize();
    }
    
    return GestureDetector(
      onTap: () {
        if (intent == 'hotel' || intent == 'hotels') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: session.query),
            ),
          );
        } else if (intent == 'shopping') {
          final allProducts = <Product>[];
          for (final s in conversationHistory) {
            allProducts.addAll(s.products);
          }
          if (allProducts.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: allProducts),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No products available to display'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant, // Dark theme background
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary), // White icon for visibility
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary, // White text for visibility
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🍽️ Build local/restaurant card
  Widget _buildLocalCard(Map<String, dynamic> place) {
    final title = place['title']?.toString() ?? 'Unknown';
    final rating = safeNumber(place['rating'], 0.0);
    final address = place['address']?.toString() ?? '';
    final thumbnail = place['thumbnail']?.toString() ?? '';
    final reviews = place['reviews']?.toString() ?? '';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: thumbnail.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbnail,
                  width: 60,
                  height: 60,
                  gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      color: AppColors.surfaceVariant,
                      child: Icon(Icons.restaurant, color: AppColors.textSecondary),
                    );
                  },
                ),
              )
            : Container(
                width: 60,
                height: 60,
                color: AppColors.surfaceVariant,
                child: Icon(Icons.restaurant, color: AppColors.textSecondary),
              ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rating > 0)
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1)),
                  if (reviews.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '($reviews reviews)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ],
              ),
            if (address.isNotEmpty)
              Text(
                address,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        onTap: () async {
          if (place['link'] != null) {
            final url = Uri.parse(place['link']);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          }
        },
      ),
    );
  }

  Widget _buildSummarySection(QuerySession session, [int? index]) {
    final rawSummary = session.summary?.trim() ?? "No summary available.";
    final summary = cleanMarkdown(rawSummary);

    // Show full description with beautiful Perplexity-style typing animation
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Builder(
        builder: (context) {
          final animKey = 'answer-${session.query.hashCode}';
          final shouldAnimate = !_hasAnimated.containsKey(animKey);
          return PerplexityTypingAnimation(
            text: summary,
            isStreaming: session.isStreaming,
            animate: shouldAnimate,
            onAnimationComplete: () {
              _hasAnimated[animKey] = true;
            },
            textStyle: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: AppColors.textPrimary,
            ),
            animationDuration: const Duration(milliseconds: 30),
            wordsPerTick: 1, // Smooth word-by-word animation
          );
        },
      ),
    );
  }

  Widget _buildTag(String text) {
    return GestureDetector(
      onTap: () {
        if (text == 'Shopping') {
          // Navigate to ShoppingGridScreen with all products from all sessions
          final allProducts = <Product>[];
          for (final session in conversationHistory) {
            allProducts.addAll(session.products);
          }
          if (allProducts.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: allProducts),
              ),
            );
          }
        } else if (text == 'Hotels') {
          // Navigate to HotelResultsScreen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: 'hotels'),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }


  Widget _buildResultsForSession(QuerySession session) {
    if (session.resultType == 'hotel') {
      return _buildHotelResultsList(session);
    } else {
      return _buildShoppingResultsList(session);
    }
  }

  // ✅ C5: Clean Card Router
  Widget renderCards(String intent, List<dynamic> cards) {
    // ✅ C5: Safe list handling
    final safeCards = cards.isNotEmpty ? cards : <dynamic>[];
    
    switch (intent) {
      case "shopping":
        final products = safeCards.map<Product>((item) {
          try {
            return _mapShoppingResultToProduct(item);
          } catch (e) {
            print('Error mapping product: $e');
            return Product(
              id: DateTime.now().millisecondsSinceEpoch,
              title: 'Error loading product',
              description: 'Unable to load product details',
              price: 0.0,
              source: 'Error',
              rating: 0.0,
              images: [],
              variants: [],
            );
          }
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Popular Models",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // ✅ PATCH D1: Give every list item a stable key
            ...products.map((p) {
              final id = p.id.toString();
              return KeyedSubtree(
                key: ValueKey(id),
                child: _buildProductCard(p),
              );
            }).toList(),
          ],
        );

      case "hotels":
      case "hotel":
        final hotelResults = safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return _buildHotelResultsList(QuerySession(
          query: "",
          products: [],
          hotelResults: hotelResults,
        ));

      case "restaurants":
        final restaurantResults = safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: restaurantResults.map((r) => _buildLocalCard(r)).toList(),
        );

      case "flights":
        final flightResults = safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: flightResults.map((f) => _buildFlightCard(f)).toList(),
        );

      case "location":
        final locationResults = safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // ✅ PATCH D1: Give every list item a stable key
          children: locationResults.map((l) {
            final id = l['title']?.toString() ?? l['name']?.toString() ?? UniqueKey().toString();
            return KeyedSubtree(
              key: ValueKey(id),
              child: _buildLocationCard(l),
            );
          }).toList(),
        );

      case "places":
        // ✅ PATCH C3: Use preprocessed places (zero computation in build)
        final places = _processedResult?["preprocessedPlaces"] ?? safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Places to Visit",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // ✅ PATCH D1: Give every list item a stable key
            ...(places as List).map((p) {
              final id = p['name']?.toString() ?? p['title']?.toString() ?? UniqueKey().toString();
              return KeyedSubtree(
                key: ValueKey(id),
                child: _buildPlaceCard(p),
              );
            }).toList(),
          ],
        );

      case "movies":
        final movieResults = safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Movies",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...movieResults.map((m) => _buildMovieCard(m)).toList(),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ✅ C5: Helper method for flight cards (if not exists)
  Widget _buildFlightCard(Map<String, dynamic> flight) {
    final title = flight['title']?.toString() ?? 'Unknown Flight';
    final price = flight['price']?.toString() ?? 'N/A';
    final airline = flight['airline']?.toString() ?? 'Unknown';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                airline,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingResultsList(QuerySession session) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: session.products.length,
      itemBuilder: (context, index) {
        return Container(
          color: Colors.grey.shade50,
          child: _buildProductCard(session.products[index]),
        );
      },
    );
  }

  Widget _buildHotelResultsList(QuerySession session) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: session.hotelResults.length,
      itemBuilder: (context, index) {
        return Column(
          children: [
            // ✅ PATCH D1: Give every list item a stable key
            KeyedSubtree(
              key: ValueKey(session.hotelResults[index]['id']?.toString() ?? session.hotelResults[index]['name']?.toString() ?? 'hotel-$index'),
              child: _buildHotelCard(session.hotelResults[index]),
            ),
            if (index < session.hotelResults.length - 1) const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildProductCard(Product product) {
    final validImages = product.images
        .where((img) => img.trim().isNotEmpty)
        .toList();

    final hasImage = validImages.isNotEmpty;
    final priceValid = product.price > 0;
    final sourceValid = product.source.isNotEmpty && product.source != "Unknown Source";
    final hasRating = product.rating > 0;

    // Debug: Log image count
    // print('🖼️ Product: ${product.title} - Images: ${validImages.length}');
    if (validImages.isNotEmpty) {
      print('   Image URLs: ${validImages.take(3).join(", ")}${validImages.length > 3 ? "..." : ""}');
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(product: product),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Title (Bold, larger)
          Text(
            product.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          
          // 🔹 Rating + Source (Perplexity-style)
          if (hasRating || sourceValid)
          Row(
            children: [
                if (hasRating) ...[
                  const Icon(Icons.star, size: 16, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                    product.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
                ],
                if (sourceValid) ...[
              Text(
                    product.source,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary, // Light grey for dark theme
                      fontWeight: FontWeight.w500,
                ),
              ),
            ],
              ],
          ),
          const SizedBox(height: 8),
          
          // 🔹 Price (Prominent)
          if (priceValid)
          Text(
              "\$${product.price.toStringAsFixed(2)}",
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          
          // 🔹 Image layout: Single image = compact card, Multiple images = two cards side-by-side
          // Standardized size: 160px height (same as hotels, places, restaurants)
          if (hasImage)
            validImages.length == 1
                ? // Single image: Show in a compact square card
                  SizedBox(
                      width: 160, // Standardized width (matches height)
                      height: 160,
                      child: _buildImage(validImages[0], height: 160),
                    )
                : // Multiple images: Two cards side-by-side
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // First card: Main product image
                        Expanded(
                          child: _buildImage(validImages[0], height: 160),
                        ),
                        // Second card: Extra images
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildExtraImagesCard(validImages.sublist(1), height: 160),
                        ),
                      ],
                    )
          else
            _buildNoImagePlaceholder(height: 160),

          const SizedBox(height: 12),
          
          // 🔹 Description (Better typography) with Perplexity-style animation
          if (product.description.trim().isNotEmpty)
            Builder(
              builder: (context) {
                final animKey = 'product-desc-${product.id}';
                final shouldAnimate = !_hasAnimated.containsKey(animKey);
                return PerplexityTypingAnimation(
                  text: product.description,
                  isStreaming: false, // Product descriptions are pre-generated
                  animate: shouldAnimate,
                  onAnimationComplete: () {
                    _hasAnimated[animKey] = true;
                  },
                  textStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary, // Light grey for dark theme
                    height: 1.5,
                  ),
                  animationDuration: const Duration(milliseconds: 30),
                  wordsPerTick: 1,
                );
              },
            )
          else
            const Text(
              'No description available',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary, // Light grey for dark theme
                height: 1.5,
              ),
            ),

          const SizedBox(height: 12),

          // 🔹 Action Button - Single "Visit site" button
          if (_getProductLink(product)?.isNotEmpty ?? false)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final link = _getProductLink(product)!;
                final url = Uri.parse(link);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: AppColors.textPrimary),
                    const SizedBox(width: 6),
                    Text(
                      'Visit site',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildImage(String url, {double height = 180}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
        fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
        errorBuilder: (_, __, ___) => _buildNoImagePlaceholder(height: height),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: height,
            width: double.infinity,
            alignment: Alignment.center,
            color: Colors.grey.shade200,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          );
        },
      ),
    );
  }

  // Build extra images card - shows remaining images in a grid
  Widget _buildExtraImagesCard(List<String> extraImages, {double height = 140}) {
    if (extraImages.isEmpty) {
      return _buildNoImagePlaceholder(height: height);
    }

    // If only one extra image, show it full
    if (extraImages.length == 1) {
      return _buildImage(extraImages[0], height: height);
    }

    // If multiple extra images, show in a 2x2 grid (max 4 images)
    final imagesToShow = extraImages.take(4).toList();
    final isTwoRows = imagesToShow.length > 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: height,
        child: isTwoRows
            ? Column(
                children: [
                  // Top row: first 2 images
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildSmallImage(imagesToShow[0]),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: _buildSmallImage(imagesToShow.length > 1 ? imagesToShow[1] : imagesToShow[0]),
                        ),
                      ],
                    ),
                  ),
                  if (imagesToShow.length > 2) ...[
                    const SizedBox(height: 2),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSmallImage(imagesToShow[2]),
                          ),
                          if (imagesToShow.length > 3) ...[
                            const SizedBox(width: 2),
                            Expanded(
                              child: _buildSmallImage(imagesToShow[3]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                // Single row: show all images side by side
                children: imagesToShow.asMap().entries.map((entry) {
                  final index = entry.key;
                  final imageUrl = entry.value;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: index > 0 ? 2 : 0),
                      child: _buildSmallImage(imageUrl),
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  // Helper to build small images for grid (no height constraint, fills available space)
  Widget _buildSmallImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
        gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade200,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoImagePlaceholder({double height = 180}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 1),
          borderRadius: BorderRadius.circular(8),
          color: AppColors.surfaceVariant, // Dark theme background
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyProductsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "No specific models found in this price range.",
            style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
          ),
          SizedBox(height: 6),
          Text(
            "Try refining your query (e.g., 'Adidas running shoes under \$200') "
            "or check the official store for updated listings.",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHotelsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "No hotels found for your search.",
            style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
          ),
          SizedBox(height: 6),
          Text(
            "Try refining your query (e.g., 'hotels in downtown Salt Lake City') "
            "or search with specific dates or amenities.",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  // Old _buildActionButton removed - using Perplexity-style version below
  Widget _buildActionButtonOld(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: Colors.teal),
      label: Text(label, style: const TextStyle(color: Colors.teal)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.teal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  // 💬 Follow-up Suggestion Item (Perplexity-style with enhanced styling)
  // ✅ STEP 9: Accept session to pass context
  Widget _buildFollowUpSuggestionItem(String suggestion, int index, {QuerySession? session}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)), // Staggered delay
      curve: Curves.easeOutCubic, // Smoother curve
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)), // Slightly more movement
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onFollowUpQuerySelected(suggestion, previousSession: session),
          borderRadius: BorderRadius.circular(14), // Slightly more rounded
          splashColor: AppColors.accent.withOpacity(0.2), // Dark theme splash
          highlightColor: AppColors.accent.withOpacity(0.1),
      child: Container(
            margin: const EdgeInsets.only(bottom: 10), // Better spacing
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), // More padding
        decoration: BoxDecoration(
              color: AppColors.surface, // Dark theme background
              borderRadius: BorderRadius.circular(14),
          border: Border.all(
                color: AppColors.border, // Dark theme border
                width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
                  color: Colors.black.withOpacity(0.3), // More visible shadow for dark theme
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
            child: Row(
              children: [
                // Left-pointing chevron icon (Perplexity style - refined)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant, // Dark theme variant
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 14,
                    color: AppColors.textPrimary, // White for visibility
                  ),
                ),
                const SizedBox(width: 12),
                // Suggestion text (enhanced typography)
                Expanded(
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15, // Slightly larger
                      height: 1.5, // Better line height
                      fontWeight: FontWeight.w500, // Medium weight for better readability
                      letterSpacing: -0.2, // Tighter letter spacing
                    ),
                    maxLines: 2, // Limit to 2 lines for cleaner look
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 💬 Follow-up Suggestions Section (Legacy - kept for backward compatibility)
  Widget _buildFollowUpSuggestions(List<String> suggestions) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: suggestions.asMap().entries.map((entry) {
          return _buildFollowUpSuggestionItem(entry.value, entry.key);
        }).toList(),
      ),
    );
  }

  // Handle follow-up click
  // ✅ FOLLOW-UP PATCH: Pass context + lastFollowUp + parentQuery
  void _onFollowUpQuerySelected(String query, {QuerySession? previousSession}) {
    _followUpController.text = query;
    _onFollowUpSubmitted(
      previousContext: previousSession,
      lastFollowUp: query, // The clicked follow-up text
      parentQuery: previousSession?.query, // Original query that generated this follow-up
    );
  }

  // Helper to get product link from stored map
  String? _getProductLink(Product product) {
    return _productLinks[product.id];
  }

  Widget _buildHotelCard(Map<String, dynamic> hotel, {bool isHorizontal = false}) {
    // Extract safe hotel data, but preserve original hotel data for coordinate extraction
    final safeHotel = _extractHotelData(hotel);
    // Merge original hotel data to preserve coordinates
    safeHotel.addAll({
      'gps_coordinates': hotel['gps_coordinates'],
      'geo': hotel['geo'],
      'latitude': hotel['latitude'],
      'longitude': hotel['longitude'],
    });
    
    // Calculate prices safely (avoid type cast errors)
    final originalPrice = safeNumber(safeHotel['originalPrice'], 0.0);
    final currentPrice = safeNumber(safeHotel['price'], 0.0);
    final reviewCount = safeInt(safeHotel['reviewCount'], 0);
    
    return GestureDetector(
      onTap: () => _navigateToHotelDetail(safeHotel),
      child: isHorizontal
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
          children: [
            // Hotel name and location
            Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Minimal side padding for content
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    safeHotel['name'],
                    style: AppTypography.title1.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                  ),
                  // Only show separate location if it's different from what's in the hotel name
                  if (safeHotel['location'] != 'Location not specified' && 
                      !safeHotel['name'].toLowerCase().contains(safeHotel['location'].toLowerCase())) ...[
                    const SizedBox(height: 4),
                    Text(
                      safeHotel['location'],
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  
                  // Rating and review count
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                                safeNumber(safeHotel['rating'], 0.0) > 0 ? '${safeNumber(safeHotel['rating'], 0.0).toStringAsFixed(1)}' : 'N/A',
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '($reviewCount reviews)',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Spacer(),
                              // Price
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (originalPrice > 0) ...[
                      Text(
                                        '\$${originalPrice.toInt()}',
                                        style: AppTypography.body1.copyWith(
                                          color: AppColors.textSecondary,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                    ],
                                    if (currentPrice > 0)
                                      Text(
                                        '\$${currentPrice.toStringAsFixed(0)}',
                                        style: AppTypography.title1.copyWith(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Image carousel (clickable to open hotel detail) - Perplexity style: 2 images side-by-side
                    _buildHotelImageCarousel(safeHotel['images'], safeHotel),
                    
                    // Quick actions - Horizontal scrollable
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {}, // Empty onTap to prevent bubbling
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), // Add horizontal padding
                        child: SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildQuickActionButton('Find a room', Icons.bed, () {
                                _navigateToHotelDetail(safeHotel);
                              }),
                              const SizedBox(width: 8),
                              _buildQuickActionButton('Website', Icons.language, () {
                                _launchUrl(safeHotel['link']);
                              }),
                              const SizedBox(width: 8),
                              _buildQuickActionButton('Call', Icons.phone, () {
                                _makePhoneCall(safeHotel['phone']);
                              }),
                              const SizedBox(width: 8),
                              _buildQuickActionButton('Directions', Icons.directions, () {
                                _openHotelDirections(safeHotel);
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Prevent overflow by using minimum size
                children: [
                  // Hotel name and location
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Minimal side padding for content
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          safeHotel['name'],
                          style: AppTypography.title1.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        // Only show separate location if it's different from what's in the hotel name
                        if (safeHotel['location'] != 'Location not specified' && 
                            !safeHotel['name'].toLowerCase().contains(safeHotel['location'].toLowerCase())) ...[
                          const SizedBox(height: 4),
                          Text(
                            safeHotel['location'],
                            style: AppTypography.body1.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        
                        // Rating and review count
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              safeNumber(safeHotel['rating'], 0.0) > 0 ? '${safeNumber(safeHotel['rating'], 0.0).toStringAsFixed(1)}' : 'N/A',
                              style: AppTypography.body1.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '($reviewCount reviews)',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      // Price
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                          children: [
                                  if (originalPrice > 0) ...[
                              Text(
                                      '\$${originalPrice.toInt()}',
                                style: AppTypography.body1.copyWith(
                                  color: AppColors.textSecondary,
                                  decoration: TextDecoration.lineThrough,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                            ],
                                  if (currentPrice > 0)
                              Text(
                                      '\$${currentPrice.toStringAsFixed(0)}',
                                style: AppTypography.title1.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
                  // Image carousel (clickable to open hotel detail) - Perplexity style: 2 images side-by-side
                  _buildHotelImageCarousel(safeHotel['images'], safeHotel),
            
            // Quick actions - Horizontal scrollable
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // Empty onTap to prevent bubbling
              child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), // Add horizontal padding
                child: SizedBox(
                        height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                            _buildQuickActionButton('Find a room', Icons.bed, () {
                        _navigateToHotelDetail(safeHotel);
                      }),
                      const SizedBox(width: 8),
                      _buildQuickActionButton('Website', Icons.language, () {
                        _launchUrl(safeHotel['link']);
                      }),
                      const SizedBox(width: 8),
                      _buildQuickActionButton('Call', Icons.phone, () {
                        _makePhoneCall(safeHotel['phone']);
                      }),
                      const SizedBox(width: 8),
                      _buildQuickActionButton('Directions', Icons.directions, () {
                              _openHotelDirections(safeHotel);
                      }),
                    ],
                  ),
                ),
              ),
            ),
            
            // Description below action buttons - Perplexity style: 3 lines max, compact text
            // Always show Perplexity-style summary
            // ✅ STEP 1 & 2: Use compute() with caching
              Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Add horizontal padding
              child: FutureBuilder<String>(
                future: _getHotelSummary(safeHotel),
                builder: (context, snapshot) {
                  final summary = snapshot.data ?? 'A modern property offering comfortable accommodations.';
                  final animKey = 'hotel-summary-${safeHotel['name']}';
                  final shouldAnimate = !_hasAnimated.containsKey(animKey);
                  return PerplexityTypingAnimation(
                    text: summary,
                    isStreaming: false, // Hotel descriptions are pre-generated
                    animate: shouldAnimate,
                    onAnimationComplete: () {
                      _hasAnimated[animKey] = true;
                    },
                    textStyle: TextStyle(
                      fontSize: 14, // Smaller, more compact text
                      color: AppColors.textPrimary.withOpacity(0.8), // Brighter for better visibility
                      height: 1.4, // Tighter line spacing
                      fontWeight: FontWeight.w400,
                    ),
                    animationDuration: const Duration(milliseconds: 30),
                    wordsPerTick: 1,
                  );
                },
                ),
              ),
          ],
        ),
    );
  }

  Widget _buildHotelImageCarousel(List<String>? images, Map<String, dynamic> hotel) {
    final imageList = images ?? [];
    if (imageList.isEmpty) {
      return GestureDetector(
        onTap: () => _navigateToHotelDetail(hotel),
        child: SizedBox(
          height: 160,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surfaceVariant,
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.hotel,
                  color: AppColors.textSecondary,
                  size: 48,
                ),
                SizedBox(height: 8),
                Text(
                  'No images available',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      );
    }
    
    // Perplexity style: Show 2 images side-by-side, but allow horizontal swiping for more images
    // Calculate how many "pages" we need (each page shows 2 images)
    final pageCount = (imageList.length / 2).ceil();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16), // Add horizontal padding for images
      child: SizedBox(
        height: 160,
        child: PageView.builder(
          physics: const ClampingScrollPhysics(),
          itemCount: pageCount,
          itemBuilder: (context, pageIndex) {
            // Get images for this page (2 images per page)
            final startIndex = pageIndex * 2;
            final firstImage = imageList[startIndex];
            final secondImage = startIndex + 1 < imageList.length ? imageList[startIndex + 1] : null;
            
            return Row(
              children: [
                // First image - takes up available space
                Expanded(
                  child: GestureDetector(
                    onTap: () => _navigateToHotelDetail(hotel),
                    child: Container(
                      height: 160,
                      margin: EdgeInsets.only(right: secondImage != null ? 8 : 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.surfaceVariant,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: firstImage,
                            fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Second image - only if available
                ...(secondImage != null ? [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _navigateToHotelDetail(hotel),
                      child: Container(
                        height: 160,
                        margin: const EdgeInsets.only(left: 8), // Increased from 4 to 8 for better spacing
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.surfaceVariant,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: secondImage,
                            fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] : []),
              ],
            );
          },
        ),
      ),
    );
  }


  // Generate Perplexity-style hotel summary (2-3 sentences, varied and unique)
  // Strategy: Varied openings, specific details, flowing amenities, 150-250 chars
  // ✅ STEP 1 & 2: Get hotel summary with caching and isolate
  Future<String> _getHotelSummary(Map<String, dynamic> hotel) async {
    final hotelId = hotel['name']?.toString() ?? '';
    
    // ✅ STEP 2: Check cache first
    if (_hotelSummaryCache.containsKey(hotelId)) {
      return _hotelSummaryCache[hotelId]!;
  }

    // ✅ STEP 1: Use compute() to run in isolate
    final summary = await compute(generateSummaryIsolate, hotel);
    
    // ✅ STEP 2: Cache the result
    _hotelSummaryCache[hotelId] = summary;
    
    return summary;
  }
  
  String _generatePerplexityStyleSummary(Map<String, dynamic> hotel) {
    final name = safeString(hotel['name'], '');
    final address = safeString(hotel['address'], '');
    final location = safeString(hotel['location'], '');
    final rating = safeNumber(hotel['rating'], 0.0);
    final reviewCount = safeInt(hotel['reviewCount'], 0);
    final amenities = hotel['amenities'] as List<dynamic>? ?? [];
    final description = safeString(hotel['description'], '');
    final nearby = safeString(hotel['nearby'], '');
    
    // 1. DATA EXTRACTION & ANALYSIS
    final nameLower = name.toLowerCase();
    final isStudio = nameLower.contains('studio');
    final isLuxury = nameLower.contains('luxury') || nameLower.contains('premium') || nameLower.contains('boutique');
    final isBoutique = nameLower.contains('boutique') || nameLower.contains('monaco') || nameLower.contains('kimpton');
    final isAirport = nameLower.contains('airport');
    final isDowntown = nameLower.contains('downtown');
    final isExtendedStay = nameLower.contains('extended') || nameLower.contains('long term');
    final isResort = nameLower.contains('resort');
    final isSuites = nameLower.contains('suites') || nameLower.contains('suite');
    final isInn = nameLower.contains('inn');
    
    // Determine hotel class from rating (if not explicitly provided)
    final hotelClass = rating >= 4.5 ? 4 : (rating >= 4.0 ? 3 : (rating >= 3.5 ? 2 : 1));
    final isHighEnd = rating >= 4.5 || isLuxury || isBoutique;
    
    // Extract amenities
    final amenityList = amenities.map((a) => a.toString().toLowerCase()).toList();
    final hasPool = amenityList.any((a) => a.contains('pool') || a.contains('swimming'));
    final hasParking = amenityList.any((a) => a.contains('parking') || a.contains('free parking'));
    final hasBreakfast = amenityList.any((a) => a.contains('breakfast') || a.contains('continental'));
    final hasShuttle = amenityList.any((a) => a.contains('shuttle') || a.contains('airport'));
    final hasFitness = amenityList.any((a) => a.contains('fitness') || a.contains('gym') || a.contains('workout'));
    final hasWifi = amenityList.any((a) => a.contains('wifi') || a.contains('internet') || a.contains('wireless'));
    final hasPets = amenityList.any((a) => a.contains('pet') || a.contains('dog') || a.contains('animal'));
    final hasKitchen = amenityList.any((a) => a.contains('kitchen') || a.contains('cooking') || a.contains('microwave') || a.contains('refrigerator'));
    final hasSpa = amenityList.any((a) => a.contains('spa') || a.contains('massage'));
    final hasRestaurant = amenityList.any((a) => a.contains('restaurant') || a.contains('dining') || a.contains('bar'));
    final hasBusiness = amenityList.any((a) => a.contains('business') || a.contains('meeting') || a.contains('conference'));
    final hasRooftop = amenityList.any((a) => a.contains('rooftop') || a.contains('roof'));
    final isIndoorPool = amenityList.any((a) => a.contains('indoor pool') || a.contains('indoor swimming'));
    
    // Check for unique connections/features in description
    final descLower = description.toLowerCase();
    final hasConventionCenter = descLower.contains('convention') || descLower.contains('conference center');
    final hasConnection = descLower.contains('connected to') || descLower.contains('adjacent to');
    
    // 2. VARIED OPENING PATTERNS (Perplexity style)
    List<String> sentences = [];
    String firstSentence = '';
    
    // Pattern 1: Type-based with star rating (if high-end)
    if (isHighEnd && rating >= 4.0) {
      String typeDesc = '';
      if (isBoutique) {
        typeDesc = 'A ${hotelClass}-star luxury boutique hotel';
      } else if (isLuxury) {
        typeDesc = 'A ${hotelClass}-star luxury hotel';
      } else if (rating >= 4.5) {
        typeDesc = 'A ${hotelClass}-star hotel';
      } else {
        typeDesc = 'A ${hotelClass}-star property';
      }
      
      // Add location context
      if (isDowntown || address.toLowerCase().contains('downtown')) {
        typeDesc += ' in downtown ${location.isNotEmpty && location != 'Location not specified' ? location.split(',')[0] : 'SLC'}';
      } else if (isAirport) {
        typeDesc += ' near the airport';
      }
      
      firstSentence = typeDesc;
    }
    // Pattern 2: Feature-based (unique connections)
    else if (hasConventionCenter || hasConnection) {
      String connection = '';
      if (descLower.contains('convention center')) {
        final match = RegExp(r'connected to (?:the )?([^,\.]+)').firstMatch(descLower);
        if (match != null) {
          connection = match.group(1)?.trim() ?? 'the convention center';
        } else {
          connection = 'the convention center';
        }
        firstSentence = 'A modern hotel connected to $connection';
      } else if (descLower.contains('connected to')) {
        final match = RegExp(r'connected to ([^,\.]+)').firstMatch(descLower);
        if (match != null) {
          connection = match.group(1)?.trim() ?? '';
          firstSentence = 'A hotel connected to $connection';
        } else {
          firstSentence = 'A modern hotel';
        }
      } else {
        firstSentence = 'A modern hotel';
      }
    }
    // Pattern 3: Amenity-led (for budget/mid-range)
    else if (hasPool && hasBreakfast && hasParking && !isHighEnd) {
      firstSentence = 'Clean rooms, free parking';
      if (isIndoorPool) {
        firstSentence += ', indoor pool';
      } else if (hasPool) {
        firstSentence += ', pool';
      }
      if (hasBreakfast) {
        firstSentence += ', ${hasShuttle ? 'airport shuttle' : ''}${hasShuttle && hasBreakfast ? ', ' : ''}${hasBreakfast ? 'hot breakfast' : ''}';
      } else if (hasShuttle) {
        firstSentence += ', airport shuttle';
      }
    }
    // Pattern 4: Location-led (if address is prominent)
    else if (address.isNotEmpty && address.length > 10 && address.length < 80 && 
             !address.toLowerCase().contains('location not specified')) {
      firstSentence = 'Located at $address';
    }
    // Pattern 5: Description-based (if meaningful)
    else if (description.isNotEmpty && description.length > 40 && description.length < 180) {
      // Extract first meaningful sentence from description
      String descStart = description.split(RegExp(r'[.!?]'))[0].trim();
      descStart = descStart.replaceAll(RegExp(name, caseSensitive: false), '').trim();
      descStart = descStart.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      // Clean generic phrases
      descStart = descStart.replaceAll(RegExp(r'comfortable accommodations|excellent stay|top-notch|outstanding|well-appointed', caseSensitive: true), '').trim();
      
      if (descStart.length > 25 && descStart.length < 120 && 
          !descStart.toLowerCase().contains('comfortable') &&
          !descStart.toLowerCase().contains('excellent')) {
        firstSentence = descStart;
      } else {
        // Fallback to type-based
        if (isStudio) {
          firstSentence = 'A studio property';
        } else if (isResort) {
          firstSentence = 'A resort property';
        } else if (isExtendedStay) {
          firstSentence = 'An extended-stay property';
        } else if (isSuites) {
          firstSentence = 'A suite property';
        } else {
          firstSentence = 'A modern property';
        }
      }
    }
    // Pattern 6: Type-based fallback
    else {
      if (isStudio) {
        firstSentence = 'A studio property';
      } else if (isResort) {
        firstSentence = 'A resort property';
      } else if (isExtendedStay) {
        firstSentence = 'An extended-stay property';
      } else if (isSuites) {
        firstSentence = 'A suite property';
      } else if (isInn) {
        firstSentence = 'An inn';
      } else {
        firstSentence = 'A modern property';
      }
    }
    
    // 3. ADD AMENITIES IN FLOWING LANGUAGE
    List<String> keyAmenities = [];
    
    // Prioritize amenities not already mentioned
    if (hasPool && !firstSentence.toLowerCase().contains('pool')) {
      keyAmenities.add(isIndoorPool ? 'indoor pool' : 'pool');
    }
    if (hasRooftop && hasPool && !firstSentence.toLowerCase().contains('pool')) {
      keyAmenities.add('rooftop pool');
    }
    if (hasFitness && !firstSentence.toLowerCase().contains('fitness')) {
      keyAmenities.add('fitness center');
    }
    if (hasRestaurant && !firstSentence.toLowerCase().contains('dining') && !firstSentence.toLowerCase().contains('restaurant')) {
      keyAmenities.add('multiple dining options');
    } else if (hasRestaurant && !firstSentence.toLowerCase().contains('dining') && !firstSentence.toLowerCase().contains('restaurant')) {
      keyAmenities.add('on-site dining');
    }
    if (hasParking && !firstSentence.toLowerCase().contains('parking')) {
      keyAmenities.add('free parking');
    }
    if (hasBreakfast && !firstSentence.toLowerCase().contains('breakfast')) {
      keyAmenities.add('complimentary breakfast');
    }
    if (hasShuttle && !firstSentence.toLowerCase().contains('shuttle')) {
      keyAmenities.add('shuttle service');
    }
    if (hasPets) {
      keyAmenities.add('pet-friendly amenities');
    }
    if (hasKitchen && !firstSentence.toLowerCase().contains('kitchen')) {
      keyAmenities.add('kitchen facilities');
    }
    if (hasSpa && !firstSentence.toLowerCase().contains('spa')) {
      keyAmenities.add('spa services');
    }
    if (hasBusiness && !firstSentence.toLowerCase().contains('business')) {
      keyAmenities.add('business center');
    }
    if (hasWifi && keyAmenities.length < 3) {
      keyAmenities.add('free WiFi');
    }
    
    // Limit to 3-4 most important amenities
    keyAmenities = keyAmenities.take(4).toList();
    
    if (keyAmenities.isNotEmpty) {
      String amenityText = '';
      if (keyAmenities.length == 1) {
        amenityText = keyAmenities[0];
      } else if (keyAmenities.length == 2) {
        amenityText = '${keyAmenities[0]} and ${keyAmenities[1]}';
      } else {
        amenityText = '${keyAmenities.take(keyAmenities.length - 1).join(', ')}, and ${keyAmenities.last}';
      }
      
      // Add amenities with appropriate connector
      if (firstSentence.toLowerCase().contains('featuring') || firstSentence.toLowerCase().contains('offering') || firstSentence.toLowerCase().contains('with')) {
        firstSentence += ', $amenityText';
      } else if (firstSentence.toLowerCase().startsWith('located at')) {
        firstSentence += ', features $amenityText';
      } else {
        firstSentence += ' featuring $amenityText';
      }
    }
    
    // 4. ADD LOCATION CONTEXT & SPECIFIC DETAILS
    final addressLower = address.toLowerCase();
    final locationLower = location.toLowerCase();
    final nearbyLower = nearby.toLowerCase();
    
    String locationContext = '';
    
    // Specific location details (Perplexity style)
    if (address.isNotEmpty && address.length > 10 && address.length < 100 && 
        !address.toLowerCase().contains('location not specified') &&
        !firstSentence.toLowerCase().contains('located at')) {
      // If we haven't used address yet, add it
      if (!firstSentence.toLowerCase().contains(address.split(',')[0].toLowerCase())) {
        locationContext = 'Located at $address';
      }
    } else if (isAirport || addressLower.contains('airport') || locationLower.contains('airport') || nearbyLower.contains('airport')) {
      locationContext = 'conveniently located near the airport';
      if (hasShuttle) {
        locationContext += ' with easy shuttle access';
      }
    } else if (isDowntown || addressLower.contains('downtown') || locationLower.contains('downtown') || nearbyLower.contains('downtown')) {
      locationContext = 'in the downtown area';
      if (hasBusiness) {
        locationContext += ', ideal for business travelers';
      }
    } else if (nearby.isNotEmpty && nearby.length < 60 && 
               !nearbyLower.contains('airport') && !nearbyLower.contains('downtown')) {
      // Use nearby attractions (Perplexity style: "close to Temple Square")
      locationContext = 'close to ${nearby.toLowerCase()}';
    } else if (location.isNotEmpty && location != 'Location not specified' && location.length < 40) {
      locationContext = 'in $location';
    }
    
    // Add location context to first sentence
    if (locationContext.isNotEmpty) {
      if (firstSentence.toLowerCase().startsWith('located at')) {
        // Already has location, don't duplicate
      } else {
        firstSentence += '; $locationContext';
      }
    }
    
    sentences.add(firstSentence);
    
    // 5. SECOND SENTENCE: Additional unique features or rating
    // Prefer unique features over rating if available
    bool addedSecondSentence = false;
    
    // Check for unique features in description
    if (description.isNotEmpty && description.length > 50 && 
        !description.toLowerCase().contains(name.toLowerCase()) &&
        !description.toLowerCase().contains('comfortable accommodations') &&
        !description.toLowerCase().contains('excellent stay')) {
      
      // Extract meaningful content (avoid generic phrases)
      String descContent = description;
      descContent = descContent.replaceAll(RegExp(name, caseSensitive: false), '').trim();
      descContent = descContent.replaceAll(RegExp(r'comfortable accommodations|excellent stay|top-notch|outstanding|exceptional|well-appointed', caseSensitive: false), '').trim();
      descContent = descContent.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      // Look for specific features (Perplexity style)
      if (descContent.toLowerCase().contains('family-friendly')) {
        sentences.add('Family-friendly property with spacious suites');
        addedSecondSentence = true;
      } else if (descContent.toLowerCase().contains('stylish') || descContent.toLowerCase().contains('boutique')) {
        sentences.add('Features stylish rooms and modern amenities');
        addedSecondSentence = true;
      } else {
        // Extract first meaningful sentence (limit to ~100 chars)
        final descSentences = descContent.split(RegExp(r'[.!?]+')).where((s) => s.trim().length > 25).take(1).toList();
        if (descSentences.isNotEmpty) {
          String secondPart = descSentences.first.trim();
          if (secondPart.length > 100) {
            secondPart = secondPart.substring(0, 100).trim();
            final lastSpace = secondPart.lastIndexOf(' ');
            if (lastSpace > 50) secondPart = secondPart.substring(0, lastSpace);
          }
          if (secondPart.isNotEmpty && secondPart.length > 30) {
            sentences.add(secondPart);
            addedSecondSentence = true;
          }
        }
      }
    }
    
    // Add rating if we haven't added a second sentence yet
    if (!addedSecondSentence && rating > 0 && reviewCount > 0) {
      String ratingText = '';
      if (rating >= 4.5) {
        ratingText = 'Highly rated';
      } else if (rating >= 4.0) {
        ratingText = 'Well rated';
      } else if (rating >= 3.5) {
        ratingText = 'Popular';
      }
      
      if (ratingText.isNotEmpty) {
        ratingText += ' among guests';
        if (reviewCount > 1000) {
          ratingText += ' with thousands of reviews';
        } else if (reviewCount > 100) {
          ratingText += ' with many positive reviews';
        }
        sentences.add(ratingText);
      }
    }
    
    // 6. COMBINE INTO 2-3 SENTENCES (150-250 chars target)
    String summary = sentences.take(3).join('. ');
    if (!summary.endsWith('.')) summary += '.';
    
    // Ensure meaningful length (at least 100 chars, max 280)
    if (summary.length < 100 && description.isNotEmpty) {
      // Try to add more from description
      String extra = description.substring(0, (120 - summary.length).clamp(30, 100)).trim();
      extra = extra.replaceAll(RegExp(name, caseSensitive: false), '').trim();
      if (extra.isNotEmpty && !extra.toLowerCase().contains('comfortable') && extra.length > 20) {
        summary = '$summary $extra.';
      }
    } else if (summary.length > 280) {
      // Trim to 2 sentences if too long
      final sentencesList = summary.split('. ');
      if (sentencesList.length > 2) {
        summary = sentencesList.take(2).join('. ') + '.';
      }
    }
    
    return summary.isEmpty ? 'A property offering modern amenities and convenient accommodations.' : summary;
  }

  Widget _buildQuickActionButton(String label, IconData icon, VoidCallback onTap, {bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceVariant : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: enabled ? AppColors.textPrimary : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? AppColors.textPrimary : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📝 Build answer text with inline location cards (Perplexity-style)
  // ✅ NEW: NO FutureBuilder - parsing happens in background or pre-parsed
  Widget _buildAnswerWithInlineLocationCards(QuerySession session) {
    final parsed = session.cachedParsing;

    // If already parsed → render immediately (ZERO isolates)
    if (parsed != null) {
      return _buildAnswerFromParsedContent(session, parsed);
    }

    // Not parsed yet → trigger background parsing ONCE
    _triggerBackgroundParsing(session);

    // Show temporary loading UI (no heavy work)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (session.destinationImages.isNotEmpty)
          _buildDestinationOverview(session.query, session.destinationImages),

        const SizedBox(height: 20),

        const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }

  // ✅ PATCH 4: Trigger background parsing (uses session-based flags)
  void _triggerBackgroundParsing(QuerySession session) {
    if (session.cachedParsing != null) return;
    if (session.isParsing == true) return;

    // Find session index and mark as parsing
    final index = conversationHistory.indexWhere((s) => s.query == session.query);
    if (index == -1) return;
    
    setState(() {
      conversationHistory[index] = conversationHistory[index].copyWith(
        isParsing: true, // ✅ PATCH 4: Mark as parsing
      );
    });

    final input = ParsingInput(
      answerText: session.summary ?? "",
      locationCards: session.locationCards,
      destinationImages: session.destinationImages,
    ).toMap();

    compute(parseAnswerIsolate, input).then((parsed) {
      if (!mounted) return;

      // find session index
      final idx = conversationHistory.indexWhere((s) => s.query == session.query);
      if (idx == -1) return;

      setState(() {
        conversationHistory[idx] =
            conversationHistory[idx].copyWith(
              cachedParsing: parsed,
              isParsing: false, // ✅ PATCH 4: Mark parsing as complete
            );
      });
    });
  }
  
  // ✅ PHASE 2: Helper to build answer from ParsedContent (isolate output)
  Widget _buildAnswerFromParsedContent(QuerySession session, ParsedContent parsed) {
    final List<Widget> widgets = [];
    
    // 1) Destination header (Perplexity-style)
    if (session.destinationImages.isNotEmpty && !session.isStreaming) {
      widgets.add(_buildDestinationOverview(session.query, session.destinationImages));
      widgets.add(const SizedBox(height: 20));
    }
    
    // 2) Briefing text with animation
    if (parsed.briefingText.isNotEmpty) {
      // ✅ PATCH B3: Freeze-proof answer rendering
      final shouldAnimate = session.isStreaming && !_hasAnimated.containsKey("main-answer");
      widgets.add(
        PerplexityTypingAnimation(
          text: parsed.briefingText,
          isStreaming: session.isStreaming,
          animate: shouldAnimate,
          onAnimationComplete: () {
            _hasAnimated["main-answer"] = true;
          },
          textStyle: const TextStyle(
            fontSize: 16,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
          animationDuration: const Duration(milliseconds: 30),
          wordsPerTick: 1,
        ),
      );
      widgets.add(const SizedBox(height: 20));
    }
    
    // 3) Valid place names with animation
    if (parsed.placeNamesText.isNotEmpty) {
      final animKey = 'answer-${session.query.hashCode}-places';
      final shouldAnimate = !_hasAnimated.containsKey(animKey);
      widgets.add(
        PerplexityTypingAnimation(
          text: 'Top places to visit include: ${parsed.placeNamesText}.',
          isStreaming: session.isStreaming,
          animate: shouldAnimate,
          onAnimationComplete: () {
            _hasAnimated[animKey] = true;
          },
          textStyle: const TextStyle(
            fontSize: 16,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
          animationDuration: const Duration(milliseconds: 30),
          wordsPerTick: 1,
        ),
      );
      widgets.add(const SizedBox(height: 20));
    }
    
    // 4) All cards and text segments
    for (int i = 0; i < parsed.segments.length; i++) {
      final segment = parsed.segments[i];
      final text = segment['text'] as String? ?? '';
      final location = segment['location'] as Map<String, dynamic>?;
      
      if (text.isNotEmpty) {
        final animKey = 'answer-${session.query.hashCode}-segment-$i';
        final shouldAnimate = !_hasAnimated.containsKey(animKey);
        widgets.add(
          PerplexityTypingAnimation(
            text: text,
            isStreaming: session.isStreaming,
            animate: shouldAnimate,
            onAnimationComplete: () {
              _hasAnimated[animKey] = true;
            },
            textStyle: const TextStyle(
              fontSize: 16,
              height: 1.6,
              color: AppColors.textPrimary,
            ),
          animationDuration: const Duration(milliseconds: 30),
          wordsPerTick: 1,
        ),
      );
        widgets.add(const SizedBox(height: 16));
      }
      
      if (location != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildLocationCard(location),
          ),
        );
      }
    }
    
    // Add typing cursor if streaming
    if (session.isStreaming) {
      widgets.add(
        const Text(
          '▊',
          style: TextStyle(
            fontSize: 16,
            color: Colors.blueGrey,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
  
  // Parse text and find location mentions, returning segments with matched locations
  // Perplexity-style: Smart matching - if text mentions "Bangkok", show cards for places in Bangkok
  // Returns List<Map<String, dynamic>> where each map has 'text' and optional 'location'
  List<Map<String, dynamic>> _parseTextWithLocations(String text, List<Map<String, dynamic>> locationCards) {
    final List<Map<String, dynamic>> segments = [];
    
    if (locationCards.isEmpty) {
      return [{'text': text, 'location': null}];
    }
    
    // Common location keywords that might be mentioned in text
    final locationKeywords = [
      'bangkok', 'chiang mai', 'phuket', 'ayutthaya', 'krabi', 'pai', 'sukhothai',
      'koh samui', 'kanchanaburi', 'hua hin', 'khao yai', 'erawan', 'grand palace',
      'wat pho', 'wat arun', 'museum siam', 'floating market', 'railay', 'phi phi',
      'koh tao', 'koh phangan', 'koh lipe', 'chaweng', 'patong', 'doi inthanon'
    ];
    
    // Build a map of location names and related keywords to location cards
    final Map<String, Map<String, dynamic>> locationMap = {};
    for (final card in locationCards) {
      final title = (card['title']?.toString() ?? '').toLowerCase().trim();
      final address = (card['address']?.toString() ?? '').toLowerCase().trim();
      
      if (title.isNotEmpty) {
        // Map full title
        locationMap[title] = card;
        
        // Map key words from title
        final words = title.split(' ');
        for (final word in words) {
          if (word.length > 3 && !locationMap.containsKey(word)) {
            locationMap[word] = card;
          }
        }
        
        // Map address keywords (if card is in Bangkok and text mentions Bangkok, match it)
        if (address.isNotEmpty) {
          for (final keyword in locationKeywords) {
            if (address.contains(keyword) && !locationMap.containsKey(keyword)) {
              locationMap[keyword] = card;
            }
          }
        }
      }
    }
    
    // Find all location mentions in text (case-insensitive, word boundaries)
    final List<Map<String, dynamic>> matches = [];
    for (final entry in locationMap.entries) {
      final locationName = entry.key;
      final locationCard = entry.value;
      
      // Find all occurrences of this location name in the text
      final pattern = RegExp('\\b${RegExp.escape(locationName)}\\b', caseSensitive: false);
      final allMatches = pattern.allMatches(text);
      
      for (final match in allMatches) {
        matches.add({
          'start': match.start,
          'end': match.end,
          'locationCard': locationCard,
          'locationName': locationName,
          'length': match.end - match.start,
        });
      }
    }
    
    // Sort matches by position, then by length (longer matches first)
    matches.sort((a, b) {
      final startCompare = (a['start'] as int).compareTo(b['start'] as int);
      if (startCompare != 0) return startCompare;
      return (b['length'] as int).compareTo(a['length'] as int);
    });
    
    // Remove overlapping matches (keep the longest one at each position)
    final List<Map<String, dynamic>> nonOverlapping = [];
    for (final match in matches) {
      bool overlaps = false;
      for (int i = 0; i < nonOverlapping.length; i++) {
        final existing = nonOverlapping[i];
        final matchStart = match['start'] as int;
        final matchEnd = match['end'] as int;
        final existingStart = existing['start'] as int;
        final existingEnd = existing['end'] as int;
        
        if (matchStart < existingEnd && matchEnd > existingStart) {
          // Overlaps - keep the longer one
          if ((match['length'] as int) > (existing['length'] as int)) {
            nonOverlapping[i] = match;
          }
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        nonOverlapping.add(match);
      }
    }
    
    // Sort again after removing overlaps
    nonOverlapping.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
    
    // Track which cards we've already shown to avoid duplicates
    final Set<String> shownCardTitles = {};
    
    // Build segments
    int lastIndex = 0;
    for (final match in nonOverlapping) {
      final matchStart = match['start'] as int;
      final matchEnd = match['end'] as int;
      final locationCard = match['locationCard'] as Map<String, dynamic>;
      final cardTitle = (locationCard['title']?.toString() ?? '').toLowerCase();
      
      // Skip if we've already shown this card
      if (shownCardTitles.contains(cardTitle)) {
        continue;
      }
      
      // Add text before this match
      if (matchStart > lastIndex) {
        final beforeText = text.substring(lastIndex, matchStart);
        if (beforeText.isNotEmpty) {
          segments.add({'text': beforeText, 'location': null});
        }
      }
      
      // Don't add the matched text - just add the card (Perplexity style: card has its own heading)
      // The location name appears in the card title, not duplicated in the text
      segments.add({'text': '', 'location': locationCard});
      shownCardTitles.add(cardTitle);
      
      lastIndex = matchEnd;
    }
    
    // Add remaining text after last match
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex);
      if (remainingText.isNotEmpty) {
        segments.add({'text': remainingText, 'location': null});
      }
    }
    
    // Perplexity-style: ALWAYS show ALL location cards, even if text doesn't mention them all
    // If we have text but no matches were found, show the full text first (including briefing)
    if (shownCardTitles.isEmpty && text.trim().isNotEmpty) {
      segments.insert(0, {'text': text, 'location': null});
    }
    
    // Add ALL location cards that haven't been shown yet (Perplexity shows all cards)
    for (final card in locationCards) {
      final cardTitle = (card['title']?.toString() ?? '').toLowerCase();
      if (!shownCardTitles.contains(cardTitle)) {
        segments.add({'text': '', 'location': card});
        shownCardTitles.add(cardTitle);
      }
    }
    
    return segments;
  }

  // 🌍 Build destination overview section (Perplexity-style: 2 images side-by-side, swipeable)
  Widget _buildDestinationOverview(String query, List<String> images) {
    if (images.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2 images side-by-side with PageView for swiping (Perplexity-style)
        // Use AspectRatio to ensure both images are square and evenly sized
        SizedBox(
          height: MediaQuery.of(context).size.width / 2, // Half screen width = square images
          child: PageView.builder(
          physics: const ClampingScrollPhysics(),
            itemCount: (images.length / 2).ceil(), // Number of pages (2 images per page)
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 2;
              return Row(
                children: [
                  // First image - square aspect ratio
                  if (startIndex < images.length)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: AspectRatio(
                          aspectRatio: 1.0, // Force square (1:1)
                          child: GestureDetector(
                            onTap: () => _viewImagesFullscreen(images, startIndex),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: images[startIndex],
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: Icon(Icons.image, color: AppColors.textSecondary, size: 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Second image - square aspect ratio
                  if (startIndex + 1 < images.length)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: AspectRatio(
                          aspectRatio: 1.0, // Force square (1:1)
                          child: GestureDetector(
                            onTap: () => _viewImagesFullscreen(images, startIndex + 1),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: images[startIndex + 1],
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: Icon(Icons.image, color: AppColors.textSecondary, size: 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
  
  // Build Bookable experiences button for places queries
  Widget _buildBookableExperiencesButton(dynamic session) {
    // Collect all images from all places
    List<String> allImages = [];
    
    if (session.cards != null && session.cards is List) {
      for (var card in session.cards) {
        if (card is Map<String, dynamic>) {
          // Try multiple image fields
          final imageUrl = card['image_url']?.toString() ?? 
                          card['image']?.toString() ?? 
                          card['thumbnail']?.toString() ?? '';
          if (imageUrl.isNotEmpty) {
            allImages.add(imageUrl);
          }
          
          // Also check for images array
          if (card['images'] != null && card['images'] is List) {
            for (var img in card['images']) {
              final imgStr = img?.toString() ?? '';
              if (imgStr.isNotEmpty && !allImages.contains(imgStr)) {
                allImages.add(imgStr);
              }
            }
          }
          
          // Check photos array
          if (card['photos'] != null && card['photos'] is List) {
            for (var photo in card['photos']) {
              final photoStr = photo?.toString() ?? '';
              if (photoStr.isNotEmpty && !allImages.contains(photoStr)) {
                allImages.add(photoStr);
              }
            }
          }
        }
      }
    }
    
    if (allImages.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      child: GestureDetector(
        onTap: () => _viewImagesFullscreen(allImages, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_activity,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Bookable experiences',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // View images in full screen (swipeable)
  void _viewImagesFullscreen(List<String> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageFullscreenView(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  // Helper to build map for place card
  // Build swipeable image carousel for place photos
  Widget _buildPlaceImageCarousel(List<String> images, String placeName, int startIndex) {
    if (images.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
        ),
      );
    }
    
    // Calculate how many images to show (2 per page, starting from startIndex)
    final imagesToShow = <String>[];
    for (int i = startIndex; i < images.length; i += 2) {
      imagesToShow.add(images[i]);
    }
    
    if (imagesToShow.isEmpty) {
      // If no images at this offset, show placeholder
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
        ),
      );
    }
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: PageView.builder(
        itemCount: imagesToShow.length,
        itemBuilder: (context, index) {
          final imageUrl = imagesToShow[index];
          if (imageUrl.isEmpty) {
            return Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
            );
          }
          
          return CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey.shade200,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            ),
            errorWidget: (context, url, error) {
              print('❌ Image load error for $placeName: $error');
              return Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPlaceMap(Map<String, dynamic> place, dynamic geo, String location, String name) {
    // Extract coordinates
    double? lat;
    double? lng;
    
    if (geo != null && geo is Map) {
      final latValue = geo['latitude'] ?? geo['lat'];
      final lngValue = geo['longitude'] ?? geo['lng'];
      if (latValue != null && lngValue != null) {
        lat = latValue is double ? latValue : double.tryParse(latValue.toString());
        lng = lngValue is double ? lngValue : double.tryParse(lngValue.toString());
        
        // Validate coordinates (not 0,0)
        if (lat == 0.0 && lng == 0.0) {
          lat = null;
          lng = null;
        }
      }
    }
    
    // Try extracting from place data directly
    if (lat == null || lng == null) {
      final coords = GeocodingService.extractCoordinates(place);
      if (coords != null) {
        lat = coords['latitude'];
        lng = coords['longitude'];
        
        // Validate coordinates
        if (lat == 0.0 && lng == 0.0) {
          lat = null;
          lng = null;
        }
      }
    }
    
    // ✅ FIX: If still no coordinates, use address for geocoding
    // GoogleMapWidget will handle geocoding automatically
    final addressForGeocoding = location.isNotEmpty 
        ? (location.contains(name) ? location : '$name, $location')
        : null;
    
    // Log for debugging
    if (lat != null && lng != null) {
      print('✅ Place map: $name - Using coordinates: $lat, $lng');
    } else if (addressForGeocoding != null) {
      print('📍 Place map: $name - Will geocode address: $addressForGeocoding');
    } else {
      // print('⚠️ Place map: $name - No coordinates or address available');
    }
    
    return GoogleMapWidget(
      latitude: lat,
      longitude: lng,
      address: addressForGeocoding,
      title: name,
      height: double.infinity, // Will be constrained by AspectRatio
      showMarker: true,
      interactive: false, // Non-interactive in card view
    );
  }

  // 🎯 Build Place Card (Perplexity-style: title+rating, swipeable images side-by-side, description, action buttons)
  Widget _buildPlaceCard(Map<String, dynamic> place) {
    final name = place['name']?.toString() ?? place['title']?.toString() ?? 'Unknown Place';
    final description = place['description']?.toString() ?? '';
    final rating = place['rating']?.toString() ?? '';
    final reviews = place['reviews']?.toString() ?? '';
    final location = place['location']?.toString() ?? place['address']?.toString() ?? '';
    final website = place['website']?.toString() ?? place['link']?.toString() ?? '';
    final phone = place['phone']?.toString() ?? '';
    final geo = place['geo'];
    
    // Collect all available images for this place
    List<String> allImages = [];
    
    // ✅ FIX: Prioritize images array from backend (contains all photos)
    // Add images from images array first (backend provides all photos here)
    if (place['images'] != null && place['images'] is List) {
      // print('🖼️ Place "$name": Found images array with ${(place['images'] as List).length} items');
      for (var img in place['images']) {
        final imgStr = img?.toString() ?? '';
        if (imgStr.isNotEmpty && imgStr.startsWith('http') && !allImages.contains(imgStr)) {
          allImages.add(imgStr);
        }
      }
      print('   Added ${allImages.length} images from images array');
    }
    
    // Add images from photos array (alternative source)
    if (place['photos'] != null && place['photos'] is List) {
      // print('🖼️ Place "$name": Found photos array with ${(place['photos'] as List).length} items');
      for (var photo in place['photos']) {
        final photoStr = photo?.toString() ?? '';
        if (photoStr.isNotEmpty && photoStr.startsWith('http') && !allImages.contains(photoStr)) {
          allImages.add(photoStr);
        }
      }
      print('   Total images after photos array: ${allImages.length}');
    }
    
    // Add primary image (always include it, even if we have images array)
    final imageUrl = place['image_url']?.toString() ?? place['image']?.toString() ?? place['thumbnail']?.toString() ?? '';
    if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
      if (!allImages.contains(imageUrl)) {
        // Add as first image if it's not already in the list
        allImages.insert(0, imageUrl);
        print('   Added primary image_url as first image');
      }
    }
    
    // ✅ DEBUG: Log final image count and URLs
    // print('🖼️ Place "$name" - Final image count: ${allImages.length}');
    for (int i = 0; i < allImages.length && i < 5; i++) {
      print('   Image ${i + 1}: ${allImages[i].length > 60 ? allImages[i].substring(0, 60) + "..." : allImages[i]}');
    }
    
    // If still no images, add placeholder
    if (allImages.isEmpty) {
      // print('⚠️ Place "$name" has no images, adding placeholder');
      allImages.add(''); // Placeholder
    }
    
    // Build map URL from GPS coordinates or address (for Directions button)
    String? mapUrl;
    if (geo != null && geo is Map) {
      final lat = geo['latitude'] ?? geo['lat'];
      final lng = geo['longitude'] ?? geo['lng'];
      if (lat != null && lng != null) {
        mapUrl = 'https://www.google.com/maps?q=$lat,$lng';
      }
    }
    if (mapUrl == null && location.isNotEmpty) {
      mapUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location)}';
    }
    
    // Parse rating to number for display
    double? ratingNum;
    if (rating.isNotEmpty) {
      ratingNum = double.tryParse(rating.replaceAll(RegExp(r'[^\d.]'), ''));
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and rating on same line (Perplexity-style)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              if (ratingNum != null && ratingNum > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(
                  ratingNum.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (reviews.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($reviews)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Swipeable images side-by-side (equal squares, Perplexity-style)
          SizedBox(
            height: MediaQuery.of(context).size.width / 2 - 4, // Half screen width minus spacing = square images
            child: PageView.builder(
              physics: const ClampingScrollPhysics(), // ✅ PATCH 5: Prevent nested scroll freeze
              scrollDirection: Axis.horizontal, // ✅ FIX: Horizontal scrolling
              itemCount: (allImages.length / 2).ceil(), // Number of pages (2 images per page)
              itemBuilder: (context, pageIndex) {
                final startIndex = pageIndex * 2;
                final leftImage = startIndex < allImages.length ? allImages[startIndex] : '';
                final rightImage = startIndex + 1 < allImages.length ? allImages[startIndex + 1] : '';
                
                return Row(
                  children: [
                    // Left image
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: leftImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: leftImage,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey.shade200,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) {
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Right image
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: rightImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: rightImage,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey.shade200,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) {
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          // ✅ FIX: Action buttons (Website, Directions, Call) - moved before description
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (website.isNotEmpty)
                _buildActionButton(
                  icon: Icons.link,
                  label: 'Website',
                  onTap: () async {
                    final uri = Uri.parse(website.startsWith('http') ? website : 'https://$website');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              if (mapUrl != null)
                _buildActionButton(
                  icon: Icons.directions,
                  label: 'Directions',
                  onTap: () async {
                    final uri = Uri.parse(mapUrl!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              if (phone.isNotEmpty)
                _buildActionButton(
                  icon: Icons.phone,
                  label: 'Call',
                  onTap: () async {
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
            ],
          ),
          
          // ✅ FIX: Full description (Perplexity-style, no truncation) with animation - moved after action buttons
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final animKey = 'place-desc-$name';
                final shouldAnimate = !_hasAnimated.containsKey(animKey);
                return PerplexityTypingAnimation(
                  text: description,
                  isStreaming: false, // Place descriptions are pre-generated
                  animate: shouldAnimate,
                  onAnimationComplete: () {
                    _hasAnimated[animKey] = true;
                  },
                  textStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    height: 1.6, // Better line spacing for readability
                  ),
                  animationDuration: const Duration(milliseconds: 30),
                  wordsPerTick: 1,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
  
  // Helper: Build action button (Website, Directions, Call)
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieCard(Map<String, dynamic> movie) {
    final title = movie['title']?.toString() ?? 'Unknown Movie';
    final rating = movie['rating']?.toString() ?? '';
    final image = movie['image']?.toString() ?? '';
    final releaseDate = movie['releaseDate']?.toString() ?? '';
    final description = movie['description']?.toString() ?? '';
    final movieId = movie['id'] as int? ?? 0;
    
    return GestureDetector(
      onTap: () {
        if (movieId > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MovieDetailScreen(
                movieId: movieId,
                movieTitle: title,
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Movie poster
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: image.isNotEmpty
                  ? Image.network(
                      image,
                      width: double.infinity,
                      height: 200,
                      gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 200,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                      ),
                    )
                  : Container(
                      height: 200,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and rating
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (rating.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rating,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Release date
                  if (releaseDate.isNotEmpty)
                    Text(
                      releaseDate,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Description - Full text (no truncation)
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper: Build movie action button
  Widget _buildMovieActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textPrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildLocationCard(Map<String, dynamic> location) {
    // ✅ PATCH C3: Use preprocessed data (already computed, zero work in build)
    final title = location['title'] ?? 'Unknown Location';
    final rating = location['rating'] ?? 0.0;
    final reviews = location['reviews'] ?? '';
    final address = location['address'] ?? '';
    final thumbnail = location['thumbnail'] ?? '';
    final link = location['link'] ?? '';
    final phone = location['phone'] ?? '';
    final images = (location['images'] as List?) ?? [];
    final description = location['description'] ?? '';
    final mapUrl = location['mapUrl'];
    final mainImage = location['mainImage'];
    
    // Perplexity-style: Compact, clean card with title+rating on top, images, then buttons
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and rating on same line (Perplexity-style)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              if (rating > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (reviews.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($reviews)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ],
          ),
          
          // Address (if available) - smaller, subtle
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              address,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
          
          const SizedBox(height: 12),
          
          // Images and map side-by-side (Perplexity-style: square, equal size)
          // ALWAYS show both image and map for business cards (like Google)
          Row(
            children: [
              // Image (square) - ALWAYS show, even if placeholder
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: mainImage != null && mainImage.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              mainImage,
                              fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
                              gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: Colors.grey.shade200,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback to placeholder if image fails
                                return Container(
                                  color: Colors.grey.shade200,
                                  child: Icon(Icons.business, color: Colors.grey, size: 40),
                                );
                              },
                            ),
                          )
                        : Container(
                            // Placeholder if no image available
                            color: AppColors.surfaceVariant,
                            child: Icon(Icons.business, color: AppColors.textSecondary, size: 40),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Map (square, same size as image) - ALWAYS show
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GestureDetector(
                    onTap: () async {
                      if (mapUrl != null) {
                        final uri = Uri.parse(mapUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade100,
                              Colors.blue.shade200,
                            ],
                          ),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'View on map',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Action buttons (Website, Call, Directions) - ALWAYS show all three for business cards (like Google)
          Row(
            children: [
              // Website button - ALWAYS show
              Expanded(
                child: _buildQuickActionButton(
                  'Website', 
                  Icons.language, 
                  link.isNotEmpty
                      ? () async {
                          final uri = Uri.parse(link);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        }
                      : () {
                          // Show message if no website available
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Website not available')),
                          );
                        },
                  enabled: link.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              // Call button - ALWAYS show
              Expanded(
                child: _buildQuickActionButton(
                  'Call', 
                  Icons.phone, 
                  phone.isNotEmpty
                      ? () {
                          _makePhoneCall(phone);
                        }
                      : () {
                          // Show message if no phone available
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Phone number not available')),
                          );
                        },
                  enabled: phone.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              // Directions button - ALWAYS show
              Expanded(
                child: _buildQuickActionButton(
                  'Directions', 
                  Icons.directions, 
                  mapUrl != null
                      ? () async {
                          final uri = Uri.parse(mapUrl!);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        }
                      : () {
                          // Show message if no map available
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Location not available')),
                          );
                        },
                  enabled: mapUrl != null,
                ),
              ),
            ],
          ),
          
          // Rich description (4-5 lines, Perplexity-style) - ALWAYS show below action buttons with animation
          // If no description from OpenAI, use snippet from SerpAPI, or show placeholder
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: description.isNotEmpty
                ? Builder(
                    builder: (context) {
                      final animKey = 'location-desc-$title';
                      final shouldAnimate = !_hasAnimated.containsKey(animKey);
                      return PerplexityTypingAnimation(
                        text: description,
                        isStreaming: false, // Location descriptions are pre-generated
                        animate: shouldAnimate,
                        onAnimationComplete: () {
                          _hasAnimated[animKey] = true;
                        },
                        textStyle: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: AppColors.textPrimary,
                        ),
                        animationDuration: const Duration(milliseconds: 30),
                        wordsPerTick: 1,
                      );
                    },
                  )
                : const Text(
                    'No description available for this location.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpBar() {
    return SafeArea(
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Left: Search Icon
            const Icon(
              Icons.search,
              color: AppColors.textSecondary,
              size: 24,
            ),
            
            const SizedBox(width: 16),
            
            // Center: TextField
            Expanded(
                child: TextField(
                  controller: _followUpController,
                  focusNode: _followUpFocusNode,
                  onSubmitted: (value) => _onFollowUpSubmitted(),
                // ✅ PATCH E4: Debounce follow-up TextField input (prevents 40+ rebuilds per second)
                onChanged: (value) {
                  if (_followUpDebounce?.isActive ?? false) _followUpDebounce!.cancel();
                  _followUpDebounce = Timer(const Duration(milliseconds: 120), () {
                    // Handle input (currently just logging, but can add validation/formatting here)
                    print('Text changed: $value');
                  });
                },
                onTap: () {
                  _followUpFocusNode.requestFocus();
                },
                autofocus: false,
                  minLines: 1,
                  maxLines: 4,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask follow up...',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Right: Send Button
            GestureDetector(
              onTap: _onFollowUpSubmitted,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.tealAccent.shade700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageLayout(Product product) {
    if (product.images.isEmpty) {
      return SizedBox(
        height: 120,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceVariant,
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported,
                        color: AppColors.textSecondary,
                        size: 32,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'No image available',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceVariant,
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported,
                        color: AppColors.textSecondary,
                        size: 32,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'No image available',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: Row(
        children: [
          // First image
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(product: product),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  product.images[0],
                  fit: BoxFit.cover,
                  gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
                  loadingBuilder: (context, child, loadingProgress) {
                  // print('Loading image: ${product.images[0]}');
                    if (loadingProgress == null) {
                      return AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: child,
                      );
                    }
                    return Container(
                      color: AppColors.surfaceVariant,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // print('Image loading error: $error');
                    // print('Image URL: ${product.images[0]}');
                    return Container(
                      color: AppColors.surfaceVariant,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_not_supported,
                              color: AppColors.textSecondary,
                              size: 28,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Image unavailable',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Second image or empty space
          Expanded(
            child: product.images.length > 1
                ? GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProductDetailScreen(product: product),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        product.images[1],
                        fit: BoxFit.cover,
                        gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) {
                            return AnimatedOpacity(
                              opacity: 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: child,
                            );
                          }
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.accent,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          // print('Image loading error: $error');
                          // print('Image URL: ${product.images[1]}');
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    color: AppColors.textSecondary,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Image unavailable',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.surfaceVariant.withOpacity(0.3),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getMockData(String query) {
    // Mock shopping results
    final mockProducts = [
      {
        "title": "Red Summer Dress",
        "price": "\$29.99",
        "thumbnail": "https://picsum.photos/200/300?random=1",
        "link": "https://example.com/dress1",
        "source": "Fashion Store"
      },
      {
        "title": "Blue Jeans",
        "price": "\$49.99",
        "thumbnail": "https://picsum.photos/200/300?random=2",
        "link": "https://example.com/jeans1",
        "source": "Denim Co"
      },
      {
        "title": "White Sneakers",
        "price": "\$79.99",
        "thumbnail": "https://picsum.photos/200/300?random=3",
        "link": "https://example.com/sneakers1",
        "source": "Shoe Store"
      },
      {
        "title": "Black Handbag",
        "price": "\$39.99",
        "thumbnail": "https://picsum.photos/200/300?random=4",
        "link": "https://example.com/bag1",
        "source": "Accessories"
      },
      {
        "title": "Green T-Shirt",
        "price": "\$19.99",
        "thumbnail": "https://picsum.photos/200/300?random=5",
        "link": "https://example.com/tshirt1",
        "source": "Basic Wear"
      },
      {
        "title": "Leather Jacket",
        "price": "\$129.99",
        "thumbnail": "https://picsum.photos/200/300?random=6",
        "link": "https://example.com/jacket1",
        "source": "Outerwear"
      }
    ];

    // Mock hotel results
    final mockHotels = [
      {
        "name": "Grand Hotel Plaza",
        "price": "\$120/night",
        "rating": 4.5,
        "thumbnail": "https://picsum.photos/300/200?random=7",
        "location": "Downtown",
        "amenities": ["WiFi", "Pool", "Gym"]
      },
      {
        "name": "Boutique Inn",
        "price": "\$89/night",
        "rating": 4.2,
        "thumbnail": "https://picsum.photos/300/200?random=8",
        "location": "City Center",
        "amenities": ["WiFi", "Breakfast"]
      },
      {
        "name": "Luxury Resort",
        "price": "\$250/night",
        "rating": 4.8,
        "thumbnail": "https://picsum.photos/300/200?random=9",
        "location": "Beachfront",
        "amenities": ["WiFi", "Pool", "Spa", "Restaurant"]
      }
    ];

    // Determine if it's a hotel query
    final isHotelQuery = query.toLowerCase().contains('hotel') || 
                        query.toLowerCase().contains('stay') ||
                        query.toLowerCase().contains('accommodation');

    return {
      "type": isHotelQuery ? "hotel" : "shopping",
      "results": isHotelQuery ? mockHotels : mockProducts
    };
  }
}

// Full screen image viewer class
class _ImageFullscreenView extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  
  const _ImageFullscreenView({
    required this.images,
    required this.initialIndex,
  });
  
  @override
  State<_ImageFullscreenView> createState() => _ImageFullscreenViewState();
}

class _ImageFullscreenViewState extends State<_ImageFullscreenView> {
  late PageController _pageController;
  late int _currentIndex;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5), // Semi-transparent dark background for visibility
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1}/${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.0,
            child: Center(
              child: Image.network(
                widget.images[index],
                fit: BoxFit.contain,
                gaplessPlayback: true, // ✅ PATCH E2: Prevent white flicker on scroll
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 64,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}



import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import '../models/query_session_model.dart';
import '../models/Product.dart';
import '../isolates/text_parsing_isolate.dart';
import '../isolates/content_normalization_isolate.dart';
import 'agent_provider.dart';

/// ✅ PHASE 6: DisplayContent model - unified content structure for UI rendering
class DisplayContent {
  final String summaryText;
  final List<Map<String, dynamic>> locations;
  final List<String> destinationImages;
  final List<Product> products;
  final List<Map<String, dynamic>> hotels;
  final List<Map<String, dynamic>> flights;
  final List<Map<String, dynamic>> restaurants;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> sources;
  final String answerMarkdown;
  final String resultType;

  DisplayContent({
    required this.summaryText,
    required this.locations,
    required this.destinationImages,
    required this.products,
    required this.hotels,
    required this.flights,
    required this.restaurants,
    required this.sections,
    required this.sources,
    required this.answerMarkdown,
    required this.resultType,
  });

  /// Create empty/fallback content
  factory DisplayContent.empty() {
    return DisplayContent(
      summaryText: '',
      locations: [],
      destinationImages: [],
      products: [],
      hotels: [],
      flights: [],
      restaurants: [],
      sections: [],
      sources: [],
      answerMarkdown: '',
      resultType: 'answer',
    );
  }
}

/// ✅ PHASE 7: Memoized display content provider with keepAlive and isolate offloading
final displayContentProvider = FutureProvider.family<DisplayContent, QuerySession>((ref, session) async {
  // Keep alive to cache processed content
  ref.keepAlive();
  try {
    // ✅ Step 1: Get parsed output if available
    ParsedContent? parsedContent = session.parsedOutput;
    
    // ✅ Step 2: Get agent response for additional data
    final agentResponse = ref.read(agentResponseProvider);
    
    // ✅ FIX A & B: Collect all raw data first, then batch normalize in ONE isolate call
    
    // Step 1: Extract raw summary text (before normalization)
    String rawSummary = session.summary ?? '';
    if (parsedContent != null && parsedContent.briefingText.isNotEmpty) {
      rawSummary = parsedContent.briefingText;
    } else if (rawSummary.isEmpty && agentResponse != null) {
      rawSummary = agentResponse['summary']?.toString() ?? 
                   agentResponse['answer']?.toString() ?? '';
    }
    
    // Step 2: Collect location cards from all sources
    final locationCardsToNormalize = <Map<String, dynamic>>[];
    
    // From parsed content segments
    if (parsedContent != null) {
      for (final segment in parsedContent.segments) {
        final location = segment['location'] as Map<String, dynamic>?;
        if (location != null) {
          locationCardsToNormalize.add(Map<String, dynamic>.from(location));
        }
      }
    }
    
    // From session locationCards
    locationCardsToNormalize.addAll(session.locationCards.map((e) => Map<String, dynamic>.from(e)));
    
    // From agent response
    if (agentResponse != null) {
      final responseLocations = (agentResponse['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      locationCardsToNormalize.addAll(responseLocations);
    }
    
    // ✅ FIX B: Deduplicate location cards before isolate work
    final uniqueLocationCards = {
      for (var e in locationCardsToNormalize)
        e['id']?.toString() ?? e['name']?.toString() ?? e['title']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    // ✅ Step 5: Extract destination images
    final destinationImages = <String>[];
    destinationImages.addAll(session.destinationImages);
    if (agentResponse != null) {
      final images = (agentResponse['destination_images'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
      for (final img in images) {
        if (!destinationImages.contains(img)) {
          destinationImages.add(img);
        }
      }
    }
    
    // ✅ Step 6: Extract products
    final products = <Product>[];
    products.addAll(session.products);
    
    // Also extract from cards
    if (session.cards.isNotEmpty) {
      for (final card in session.cards) {
        try {
          final product = Product.fromJson(card);
          if (!products.any((p) => p.id == product.id)) {
            products.add(product);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Error parsing product from card: $e');
          }
        }
      }
    }
    
    // Step 3: Collect hotel cards from all sources
    final hotelCardsToNormalize = <Map<String, dynamic>>[];
    hotelCardsToNormalize.addAll(session.hotelResults.map((e) => Map<String, dynamic>.from(e)));
    
    // From results
    for (final result in session.results) {
      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        final resultType = resultMap['type']?.toString().toLowerCase() ?? '';
        if (resultType.contains('hotel') || 
            resultMap.containsKey('name') && resultMap.containsKey('rating')) {
          hotelCardsToNormalize.add(resultMap);
        }
      }
    }
    
    // From agent response
    if (agentResponse != null) {
      final responseHotels = (agentResponse['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final intent = agentResponse['intent']?.toString().toLowerCase() ?? '';
      for (final hotel in responseHotels) {
        if (intent.contains('hotel') || hotel.containsKey('name')) {
          hotelCardsToNormalize.add(hotel);
        }
      }
    }
    
    // ✅ FIX B: Deduplicate hotel cards before isolate work
    final uniqueHotelCards = {
      for (var e in hotelCardsToNormalize)
        e['id']?.toString() ?? e['name']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    // Step 4: Collect flight cards
    final flightCardsToNormalize = <Map<String, dynamic>>[];
    for (final result in session.results) {
      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        final resultType = resultMap['type']?.toString().toLowerCase() ?? '';
        if (resultType.contains('flight')) {
          flightCardsToNormalize.add(resultMap);
        }
      }
    }
    
    // ✅ FIX B: Deduplicate flight cards before isolate work
    final uniqueFlightCards = {
      for (var e in flightCardsToNormalize)
        e['id']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    // Step 5: Collect restaurant cards
    final restaurantCardsToNormalize = <Map<String, dynamic>>[];
    for (final result in session.results) {
      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        final resultType = resultMap['type']?.toString().toLowerCase() ?? '';
        if (resultType.contains('restaurant') || resultType.contains('food')) {
          restaurantCardsToNormalize.add(resultMap);
        }
      }
    }
    
    // ✅ FIX B: Deduplicate restaurant cards before isolate work
    final uniqueRestaurantCards = {
      for (var e in restaurantCardsToNormalize)
        e['id']?.toString() ?? e['name']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    // ✅ FIX A: Batch ALL normalization into ONE isolate call
    final normalized = await compute(normalizeDisplayContentIsolate, {
      'summary': rawSummary,
      'locations': uniqueLocationCards,
      'hotels': uniqueHotelCards,
      'flights': uniqueFlightCards,
      'restaurants': uniqueRestaurantCards,
    });
    
    // Extract normalized results (compute returns Map)
    final summaryText = normalized['summary'] as String;
    final locations = (normalized['locations'] as List).cast<Map<String, dynamic>>();
    final hotels = (normalized['hotels'] as List).cast<Map<String, dynamic>>();
    final flights = (normalized['flights'] as List).cast<Map<String, dynamic>>();
    final restaurants = (normalized['restaurants'] as List).cast<Map<String, dynamic>>();
    
    // ✅ Step 8: Extract sections (for hotels) - no normalization needed
    final sections = <Map<String, dynamic>>[];
    if (session.hotelSections != null) {
      sections.addAll(session.hotelSections!.map((e) => Map<String, dynamic>.from(e)));
    }
    if (agentResponse != null) {
      final responseSections = (agentResponse['sections'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      sections.addAll(responseSections);
    }
    
    // ✅ Step 11: Extract sources
    final sources = <Map<String, dynamic>>[];
    sources.addAll(session.sources.map((e) => Map<String, dynamic>.from(e)));
    if (agentResponse != null) {
      final responseSources = (agentResponse['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      sources.addAll(responseSources);
    }
    
    // ✅ Step 12: Build answer markdown (from parsed content or summary)
    String answerMarkdown = summaryText;
    if (parsedContent != null && parsedContent.placeNamesText.isNotEmpty) {
      answerMarkdown += '\n\nTop places to visit include: ${parsedContent.placeNamesText}.';
    }
    
    // ✅ Step 13: Determine result type
    final resultType = session.resultType;
    
    if (kDebugMode) {
      debugPrint('📦 DisplayContent created: $resultType, ${products.length} products, ${hotels.length} hotels, ${locations.length} locations');
    }
    
    return DisplayContent(
      summaryText: summaryText,
      locations: locations,
      destinationImages: destinationImages,
      products: products,
      hotels: hotels,
      flights: flights,
      restaurants: restaurants,
      sections: sections,
      sources: sources,
      answerMarkdown: answerMarkdown,
      resultType: resultType,
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('❌ Error creating DisplayContent: $e\n$st');
    }
    
    // Return fallback content with at least summary
    return DisplayContent(
      summaryText: session.summary ?? 'Content is being processed...',
      locations: [],
      destinationImages: session.destinationImages,
      products: session.products,
      hotels: session.hotelResults,
      flights: [],
      restaurants: [],
      sections: session.hotelSections ?? [],
      sources: session.sources,
      answerMarkdown: session.summary ?? '',
      resultType: session.resultType,
    );
  }
});

// ✅ PHASE 7: Removed local normalization functions - now using isolate functions


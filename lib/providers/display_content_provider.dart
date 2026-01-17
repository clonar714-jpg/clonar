import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import '../models/query_session_model.dart';
import '../models/Product.dart';
import '../isolates/text_parsing_isolate.dart';
import '../isolates/content_normalization_isolate.dart';
import 'agent_provider.dart';


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


final displayContentProvider = FutureProvider.family<DisplayContent, QuerySession>((ref, session) async {
  
  ref.keepAlive();
  try {
    
    ParsedContent? parsedContent = session.parsedOutput;
    
    
    final agentResponse = ref.read(agentResponseProvider);
    
    
    String rawSummary = session.answer ?? session.summary ?? '';
    if (parsedContent != null && parsedContent.briefingText.isNotEmpty) {
      rawSummary = parsedContent.briefingText;
    } else if (rawSummary.isEmpty && agentResponse != null) {
      rawSummary = agentResponse['answer']?.toString() ?? 
                   agentResponse['summary']?.toString() ?? '';
    }
    
    
    final locationCardsToNormalize = <Map<String, dynamic>>[];
    
   
    if (parsedContent != null) {
      for (final segment in parsedContent.segments) {
        final location = segment['location'] as Map<String, dynamic>?;
        if (location != null) {
          locationCardsToNormalize.add(Map<String, dynamic>.from(location));
        }
      }
    }
    
    
    locationCardsToNormalize.addAll(session.locationCards.map((e) => Map<String, dynamic>.from(e)));
    
    
    if (agentResponse != null) {
      final responseLocations = (agentResponse['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      locationCardsToNormalize.addAll(responseLocations);
    }
    
    
    final uniqueLocationCards = {
      for (var e in locationCardsToNormalize)
        e['id']?.toString() ?? e['name']?.toString() ?? e['title']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    
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
    
    
    final products = <Product>[];
    products.addAll(session.products);
    
    
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
    
    
    final hotelCardsToNormalize = <Map<String, dynamic>>[];
    hotelCardsToNormalize.addAll(session.hotelResults.map((e) => Map<String, dynamic>.from(e)));
    
    
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
    
    
    if (agentResponse != null) {
      final responseHotels = (agentResponse['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final intent = agentResponse['intent']?.toString().toLowerCase() ?? '';
      for (final hotel in responseHotels) {
        if (intent.contains('hotel') || hotel.containsKey('name')) {
          hotelCardsToNormalize.add(hotel);
        }
      }
    }
    

    final uniqueHotelCards = {
      for (var e in hotelCardsToNormalize)
        e['id']?.toString() ?? e['name']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    
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
    
    
    final uniqueFlightCards = {
      for (var e in flightCardsToNormalize)
        e['id']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    
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
    
    
    final uniqueRestaurantCards = {
      for (var e in restaurantCardsToNormalize)
        e['id']?.toString() ?? e['name']?.toString() ?? e.hashCode.toString(): e
    }.values.toList();
    
    
    final normalized = await compute(normalizeDisplayContentIsolate, {
      'summary': rawSummary,
      'locations': uniqueLocationCards,
      'hotels': uniqueHotelCards,
      'flights': uniqueFlightCards,
      'restaurants': uniqueRestaurantCards,
    });
    
    
    final summaryText = normalized['summary'] as String;
    final locations = (normalized['locations'] as List).cast<Map<String, dynamic>>();
    final hotels = (normalized['hotels'] as List).cast<Map<String, dynamic>>();
    final flights = (normalized['flights'] as List).cast<Map<String, dynamic>>();
    final restaurants = (normalized['restaurants'] as List).cast<Map<String, dynamic>>();
    
    
    final sections = <Map<String, dynamic>>[];
    if (session.hotelSections != null) {
      sections.addAll(session.hotelSections!.map((e) => Map<String, dynamic>.from(e)));
    }
    if (agentResponse != null) {
      final responseSections = (agentResponse['sections'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      sections.addAll(responseSections);
    }
    
    
    final sources = <Map<String, dynamic>>[];
    sources.addAll(session.sources.map((e) => Map<String, dynamic>.from(e)));
    if (agentResponse != null) {
      final responseSources = (agentResponse['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      sources.addAll(responseSources);
    }
    
    
    String answerMarkdown = summaryText;
    if (parsedContent != null && parsedContent.placeNamesText.isNotEmpty) {
      answerMarkdown += '\n\nTop places to visit include: ${parsedContent.placeNamesText}.';
    }
    
    
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
    // ✅ CRITICAL FIX: Use full answer if available, fallback to summary
    final fallbackText = session.answer ?? session.summary ?? 'Content is being processed...';
    return DisplayContent(
      summaryText: fallbackText,
      locations: [],
      destinationImages: session.destinationImages,
      products: session.products,
      hotels: session.hotelResults,
      flights: [],
      restaurants: [],
      sections: session.hotelSections ?? [],
      sources: session.sources,
      answerMarkdown: fallbackText,
      resultType: session.resultType,
    );
  }
});




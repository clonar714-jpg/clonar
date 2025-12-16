import '../isolates/text_parsing_isolate.dart';
import '../models/Product.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// ✅ RIVERPOD: QuerySession model for session history provider
class QuerySession {
  final String query;
  final String? summary;
  final String? intent;
  final String? cardType;
  final List<Map<String, dynamic>> cards;
  final List<dynamic> results;
  final List<Map<String, dynamic>>? sections; // ✅ FIX: Hotel sections from backend
  final List<Map<String, dynamic>>? mapPoints; // ✅ FIX: Map points for hotels
  final List<String> destinationImages;
  final List<Map<String, dynamic>> locationCards;
  final List<Map<String, dynamic>> sources; // ✅ FIX: Sources from backend
  final List<String> followUpSuggestions; // ✅ FIX: Follow-up suggestions from backend
  final bool isStreaming;
  final bool isParsing;
  final ParsedContent? parsedOutput;
  final List<Map<String, dynamic>>? parsedSegments; // ✅ FIX 2: Cached parsed text segments
  final List<String>? allImages; // ✅ FIX 3: Pre-aggregated images
  final DateTime timestamp;
  final String? imageUrl;
  
  // ✅ Backward compatibility fields (computed from cards/results)
  String get resultType => intent ?? cardType ?? 'answer';
  bool get isLoading => isStreaming || isParsing;
  List<Product> get products => _extractProducts();
  List<Map<String, dynamic>> get hotelResults => _extractHotels();
  List<Map<String, dynamic>>? get hotelSections => _extractHotelSections();
  List<Map<String, dynamic>>? get hotelMapPoints => _extractHotelMapPoints();
  List<Map<String, dynamic>> get rawResults => results.whereType<Map<String, dynamic>>().toList();

  QuerySession({
    required this.query,
    this.summary,
    this.intent,
    this.cardType,
    this.cards = const [],
    this.results = const [],
    this.sections, // ✅ FIX: Hotel sections
    this.mapPoints, // ✅ FIX: Map points
    this.destinationImages = const [],
    this.locationCards = const [],
    this.sources = const [], // ✅ FIX: Sources from backend
    this.followUpSuggestions = const [], // ✅ FIX: Follow-up suggestions from backend
    this.isStreaming = false,
    this.isParsing = false,
    this.parsedOutput,
    this.parsedSegments, // ✅ FIX 2: Cached parsed segments
    this.allImages, // ✅ FIX 3: Pre-aggregated images
    DateTime? timestamp,
    this.imageUrl,
  }) : timestamp = timestamp ?? DateTime.now();
  
  // Helper methods to extract data from cards/results
  List<Product> _extractProducts() {
    if (cards.isEmpty) return [];
    try {
      return cards.map((card) {
        try {
          // ✅ FIX: Normalize card structure to match Product model
          // Backend might send different field names, so we normalize them
          final normalizedCard = <String, dynamic>{};
          
          // Generate ID from title+price if not provided (for products without explicit ID)
          final title = card['title']?.toString() ?? card['name']?.toString() ?? '';
          final price = card['price']?.toString() ?? '';
          final link = card['link']?.toString() ?? card['url']?.toString() ?? '';
          final idHash = '${title}_${price}_${link}'.hashCode;
          
          // Map common field name variations
          normalizedCard['id'] = card['id'] ?? card['product_id'] ?? card['item_id'] ?? idHash.abs();
          normalizedCard['title'] = title.isNotEmpty ? title : 'Untitled Product';
          
          // Description: prioritize snippet, then description, then other fields
          normalizedCard['description'] = card['description']?.toString() ?? 
                                         card['snippet']?.toString() ?? 
                                         card['summary']?.toString() ?? 
                                         'No description available';
          
          // Price: handle string prices (e.g., "55.99" or "$55.99")
          final priceStr = card['price']?.toString() ?? 
                          card['price_value']?.toString() ?? 
                          card['cost']?.toString() ?? 
                          '0';
          final priceNum = double.tryParse(priceStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
          normalizedCard['price'] = priceNum;
          
          // Discount price
          final discountPriceStr = card['discountPrice']?.toString() ?? 
                                  card['discount_price']?.toString() ?? 
                                  card['sale_price']?.toString() ??
                                  card['old_price']?.toString();
          if (discountPriceStr != null) {
            final discountPriceNum = double.tryParse(discountPriceStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
            if (discountPriceNum > 0 && discountPriceNum < priceNum) {
              normalizedCard['discountPrice'] = discountPriceNum;
            }
          }
          
          normalizedCard['source'] = card['source']?.toString() ?? 
                                    (link.isNotEmpty ? link : 'Unknown Source');
          
          // Rating: handle string or number
          final ratingValue = card['rating'] ?? card['overall_rating'] ?? card['stars'] ?? 0;
          normalizedCard['rating'] = ratingValue is num ? ratingValue.toDouble() : 
                                     (double.tryParse(ratingValue.toString()) ?? 0.0);
          
          // Handle images - could be a list or a single string
          if (card['images'] != null) {
            if (card['images'] is List) {
              normalizedCard['images'] = (card['images'] as List)
                  .map((e) => e?.toString())
                  .where((e) => e != null && e.isNotEmpty)
                  .toList();
            } else if (card['images'] is String) {
              normalizedCard['images'] = [card['images']];
            } else {
              normalizedCard['images'] = [];
            }
          } else if (card['image'] != null || card['thumbnail'] != null) {
            final imageUrl = (card['image'] ?? card['thumbnail'])?.toString();
            if (imageUrl != null && imageUrl.isNotEmpty) {
              normalizedCard['images'] = [imageUrl];
            } else {
              normalizedCard['images'] = [];
            }
          } else {
            normalizedCard['images'] = [];
          }
          
          // Handle variants
          normalizedCard['variants'] = card['variants'] ?? card['options'] ?? [];
          
          return Product.fromJson(normalizedCard);
        } catch (e) {
          // ✅ DEBUG: Log parsing errors in debug mode
          if (kDebugMode) {
            debugPrint('⚠️ Error parsing product card: $e');
            debugPrint('   Card keys: ${card.keys}');
            debugPrint('   Card title: ${card['title'] ?? card['name']}');
          }
          return null;
        }
      }).whereType<Product>().toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in _extractProducts: $e');
      }
      return [];
    }
  }
  
  List<Map<String, dynamic>> _extractHotels() {
    if (results.isEmpty) return [];
    try {
      return results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return [];
    }
  }
  
  List<Map<String, dynamic>>? _extractHotelSections() {
    // ✅ FIX: Extract from sections field if available
    if (sections != null && sections!.isNotEmpty) {
      return sections!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    // Fallback: try to extract from results if it contains sections
    return null;
  }
  
  List<Map<String, dynamic>>? _extractHotelMapPoints() {
    // ✅ FIX: Extract from mapPoints field if available
    if (mapPoints != null && mapPoints!.isNotEmpty) {
      return mapPoints!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    // Fallback: try to extract from results if it contains map data
    return null;
  }
  
  // ✅ FIX: Sources and follow-ups are now stored directly, no extraction needed
  // These methods kept for backward compatibility but now just return stored values

  QuerySession copyWith({
    String? query,
    String? summary,
    String? intent,
    String? cardType,
    List<Map<String, dynamic>>? cards,
    List<dynamic>? results,
    List<Map<String, dynamic>>? sections, // ✅ FIX: Hotel sections
    List<Map<String, dynamic>>? mapPoints, // ✅ FIX: Map points
    List<String>? destinationImages,
    List<Map<String, dynamic>>? locationCards,
    List<Map<String, dynamic>>? sources, // ✅ FIX: Sources
    List<String>? followUpSuggestions, // ✅ FIX: Follow-up suggestions
    bool? isStreaming,
    bool? isParsing,
    ParsedContent? parsedOutput,
    List<Map<String, dynamic>>? parsedSegments, // ✅ FIX 2
    List<String>? allImages, // ✅ FIX 3
    DateTime? timestamp,
    String? imageUrl,
  }) {
    return QuerySession(
      query: query ?? this.query,
      summary: summary ?? this.summary,
      intent: intent ?? this.intent,
      cardType: cardType ?? this.cardType,
      cards: cards ?? this.cards,
      results: results ?? this.results,
      sections: sections ?? this.sections, // ✅ FIX: Hotel sections
      mapPoints: mapPoints ?? this.mapPoints, // ✅ FIX: Map points
      destinationImages: destinationImages ?? this.destinationImages,
      locationCards: locationCards ?? this.locationCards,
      sources: sources ?? this.sources, // ✅ FIX: Sources
      followUpSuggestions: followUpSuggestions ?? this.followUpSuggestions, // ✅ FIX: Follow-up suggestions
      isStreaming: isStreaming ?? this.isStreaming,
      isParsing: isParsing ?? this.isParsing,
      parsedOutput: parsedOutput ?? this.parsedOutput,
      parsedSegments: parsedSegments ?? this.parsedSegments, // ✅ FIX 2
      allImages: allImages ?? this.allImages, // ✅ FIX 3
      timestamp: timestamp ?? this.timestamp,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'query': query,
      'summary': summary,
      'intent': intent,
      'cardType': cardType,
      'cards': cards,
      'results': results,
      'sections': sections, // ✅ FIX: Include sections for hotels
      'mapPoints': mapPoints, // ✅ FIX: Include map points for hotels
      'destinationImages': destinationImages,
      'locationCards': locationCards,
      'sources': sources, // ✅ FIX: Include sources
      'followUpSuggestions': followUpSuggestions, // ✅ FIX: Include follow-up suggestions
      'isStreaming': isStreaming,
      'isParsing': isParsing,
      'timestamp': timestamp.toIso8601String(),
      'imageUrl': imageUrl,
      // Note: parsedOutput is not serialized as it's computed
    };
  }

  factory QuerySession.fromJson(Map<String, dynamic> json) {
    return QuerySession(
      query: json['query'] as String,
      summary: json['summary'] as String?,
      intent: json['intent'] as String?,
      cardType: json['cardType'] as String?,
      cards: (json['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
      results: json['results'] as List? ?? [],
      sections: (json['sections'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(), // ✅ FIX: Include sections
      mapPoints: (json['mapPoints'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(), // ✅ FIX: Include map points
      destinationImages: (json['destinationImages'] as List?)?.map((e) => e.toString()).toList() ?? [],
      locationCards: (json['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
      sources: (json['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [], // ✅ FIX: Include sources
      followUpSuggestions: (json['followUpSuggestions'] as List?)?.map((e) => e.toString()).toList() ?? [], // ✅ FIX: Include follow-up suggestions
      isStreaming: json['isStreaming'] as bool? ?? false,
      isParsing: json['isParsing'] as bool? ?? false,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : null,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}


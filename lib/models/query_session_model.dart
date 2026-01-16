import 'dart:math';
import '../isolates/text_parsing_isolate.dart';
import '../models/Product.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// ✅ PERPLEXITY-STYLE: Phase enum controls WHAT is shown
/// Phase controls UI structure, streaming controls text flow
enum QueryPhase {
  searching,  // Show "Working..." UI
  answering,  // Mount AnswerWidget ONCE, text streams internally
  done,       // Attach sources/images/follow-ups
}

/// ✅ RIVERPOD: QuerySession model for session history provider
/// 
/// ✅ CRITICAL: Finalized Sessions are Immutable
/// - Once isFinalized = true, answer content (sections, sources, cards, images) is LOCKED
/// - DB does NOT store sections/sources/cards - only streaming answers have this data
/// - DB-hydrated sessions can only update metadata (timestamps), never answer content
/// - This prevents DB from overwriting finalized streaming answer content
/// 
/// Finalization Rules:
/// - Streaming END event sets isFinalized = true
/// - Non-streaming complete responses also set isFinalized = true
/// - Finalized sessions preserve answer content when merged with DB-hydrated sessions
class QuerySession {
  final String sessionId; // ✅ CRITICAL: Unique identifier for this session (prevents race conditions)
  final String query;
  final String? summary;
  final String? answer; // ✅ CRITICAL: Full answer text from END event (preserves complete answer, not just first paragraph)
  final String? intent;
  final String? cardType;
  final List<Map<String, dynamic>> cards; // ✅ DEPRECATED: Use cardsByDomain instead
  // ✅ PERPLEXITY-STYLE: Structured cards by domain
  final Map<String, dynamic>? cardsByDomain; // { products: [], hotels: [], places: [], movies: [] }
  // ✅ PERPLEXITY-STYLE: UI requirements from backend
  final Map<String, dynamic>? uiRequirements; // { needsCards, needsImages, needsMaps, ... }
  // ✅ ARCHITECTURE FIX: Backend UI decision contract
  final String? scenario; // { hotel_browse, hotel_lookup_single, product_browse, general_answer, ... }
  final Map<String, dynamic>? uiDecision; // { showMap, showCards, showImages, showComparison }
  final List<dynamic> results;
  final List<Map<String, dynamic>>? sections; // ✅ FIX: Hotel sections from backend
  final List<Map<String, dynamic>>? mapPoints; // ✅ FIX: Map points for hotels
  final List<String> destinationImages;
  final List<Map<String, dynamic>>? videos; // ✅ NEW: Videos from search results { url, thumbnail, title }
  final List<Map<String, dynamic>> locationCards;
  final List<Map<String, dynamic>> sources; // ✅ FIX: Sources from backend
  final List<String> followUpSuggestions; // ✅ FIX: Follow-up suggestions from backend
  final QueryPhase phase; // ✅ PERPLEXITY-STYLE: Phase controls WHAT is shown (searching → answering → done)
  final bool isStreaming;
  final bool isParsing;
  final bool isFinalized; // ✅ PERPLEXITY-STYLE: Prevents streaming events from overwriting END event data
  final bool hasReceivedFirstChunk; // ✅ PERPLEXITY-STYLE: Track when first content chunk arrives (token-aware loading)
  // ✅ NEW: UI Enhancement fields
  final List<String> reasoningSteps; // ✅ Enhancement 1: AI reasoning steps
  final int? researchStep; // ✅ Enhancement 3: Current research step (1, 2, 3...)
  final int? maxResearchSteps; // ✅ Enhancement 3: Total research steps (2, 6, or 25)
  final String? currentAction; // ✅ Enhancement 3: Current action being performed
  final ParsedContent? parsedOutput;
  final List<Map<String, dynamic>>? parsedSegments; // ✅ FIX 2: Cached parsed text segments
  final List<String>? allImages; // ✅ FIX 3: Pre-aggregated images
  final DateTime timestamp;
  final String? imageUrl;
  final String? error; // ✅ NEW: Error message for connection/API errors
  final String? conversationId; // ✅ NEW: Conversation ID for saving messages to backend
  
  // ✅ SIMPLIFIED: No more hotel/learn query logic - just use sections directly
  String get resultType => 'answer'; // Always 'answer' - no more intent detection
  bool get isLoading => isStreaming || isParsing;
  List<Map<String, dynamic>> get rawResults => results.whereType<Map<String, dynamic>>().toList();
  
  // ✅ DEPRECATED: These are no longer used (kept for backward compatibility only)
  @Deprecated('Use sections directly instead')
  List<Product> get products => [];
  @Deprecated('Use sections directly instead')
  List<Map<String, dynamic>> get hotelResults => [];
  @Deprecated('Use sections directly instead')
  List<Map<String, dynamic>>? get hotelSections => null;
  @Deprecated('Use sections directly instead')
  List<Map<String, dynamic>>? get hotelMapPoints => null;

  QuerySession({
    required String? sessionId, // ✅ CRITICAL: Unique identifier (generated on creation)
    required this.query,
    this.summary,
    this.answer, // ✅ CRITICAL: Full answer text from END event
    this.intent,
    this.cardType,
    this.cards = const [], // ✅ DEPRECATED: Keep for backward compatibility
    this.cardsByDomain, // ✅ NEW: Structured cards by domain
    this.uiRequirements, // ✅ NEW: UI requirements from backend
    this.scenario, // ✅ ARCHITECTURE FIX: Backend scenario
    this.uiDecision, // ✅ ARCHITECTURE FIX: Backend UI decision
    this.results = const [],
    this.sections, // ✅ FIX: Hotel sections
    this.mapPoints, // ✅ FIX: Map points
    this.destinationImages = const [],
    this.videos, // ✅ NEW: Videos from search results
    this.locationCards = const [],
    this.sources = const [], // ✅ FIX: Sources from backend
    this.followUpSuggestions = const [], // ✅ FIX: Follow-up suggestions from backend
    this.phase = QueryPhase.searching, // ✅ PERPLEXITY-STYLE: Default searching, transitions to answering on first token
    this.isStreaming = false,
    this.isParsing = false,
    this.isFinalized = false, // ✅ PERPLEXITY-STYLE: Default false, set to true by END event
    this.hasReceivedFirstChunk = false, // ✅ PERPLEXITY-STYLE: Default false, set to true when first content chunk arrives
    // ✅ NEW: UI Enhancement fields
    this.reasoningSteps = const [], // ✅ Enhancement 1: AI reasoning steps
    this.researchStep, // ✅ Enhancement 3: Current research step
    this.maxResearchSteps, // ✅ Enhancement 3: Total research steps
    this.currentAction, // ✅ Enhancement 3: Current action
    this.parsedOutput,
    this.parsedSegments, // ✅ FIX 2: Cached parsed segments
    this.allImages, // ✅ FIX 3: Pre-aggregated images
    DateTime? timestamp,
    this.imageUrl,
    this.error, // ✅ NEW: Error message
    this.conversationId, // ✅ NEW: Conversation ID for saving messages
  }) : sessionId = sessionId ?? _generateSessionId(),
       timestamp = timestamp ?? DateTime.now();
  
  // ✅ Generate unique session ID (UUID-like format)
  static String generateSessionId() {
    final random = Random.secure();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final part1 = random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final part2 = random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final part3 = random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final part4 = random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return '${timestamp}_$part1$part2$part3$part4';
  }
  
  // Private helper for default generation
  static String _generateSessionId() => generateSessionId();
  
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
  
  // ✅ REMOVED: _extractHotelSections - no longer needed, use sections directly
  
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
    String? sessionId, // ✅ CRITICAL: Preserve sessionId (never change it)
    String? query,
    String? summary,
    String? answer, // ✅ CRITICAL: Full answer text from END event
    String? intent,
    String? cardType,
    List<Map<String, dynamic>>? cards, // ✅ DEPRECATED
    Map<String, dynamic>? cardsByDomain, // ✅ NEW
    Map<String, dynamic>? uiRequirements, // ✅ NEW
    String? scenario, // ✅ ARCHITECTURE FIX: Backend scenario
    Map<String, dynamic>? uiDecision, // ✅ ARCHITECTURE FIX: Backend UI decision
    List<dynamic>? results,
    List<Map<String, dynamic>>? sections, // ✅ FIX: Hotel sections
    List<Map<String, dynamic>>? mapPoints, // ✅ FIX: Map points
    List<String>? destinationImages,
    List<Map<String, dynamic>>? videos, // ✅ NEW: Videos from search results
    List<Map<String, dynamic>>? locationCards,
    List<Map<String, dynamic>>? sources, // ✅ FIX: Sources
    List<String>? followUpSuggestions, // ✅ FIX: Follow-up suggestions
    QueryPhase? phase, // ✅ PERPLEXITY-STYLE: Phase controls WHAT is shown
    bool? isStreaming,
    bool? isParsing,
    bool? isFinalized, // ✅ PERPLEXITY-STYLE: Prevents streaming from overwriting END data
    bool? hasReceivedFirstChunk, // ✅ PERPLEXITY-STYLE: Track when first content chunk arrives
    // ✅ NEW: UI Enhancement fields
    List<String>? reasoningSteps, // ✅ Enhancement 1: AI reasoning steps
    int? researchStep, // ✅ Enhancement 3: Current research step
    int? maxResearchSteps, // ✅ Enhancement 3: Total research steps
    String? currentAction, // ✅ Enhancement 3: Current action
    ParsedContent? parsedOutput,
    List<Map<String, dynamic>>? parsedSegments, // ✅ FIX 2
    List<String>? allImages, // ✅ FIX 3
    DateTime? timestamp,
    String? imageUrl,
    String? error, // ✅ NEW: Error message
    String? conversationId, // ✅ NEW: Conversation ID
  }) {
    return QuerySession(
      sessionId: sessionId ?? this.sessionId, // ✅ CRITICAL: Preserve sessionId
      query: query ?? this.query,
      summary: summary ?? this.summary,
      answer: answer ?? this.answer, // ✅ CRITICAL: Preserve full answer text
      intent: intent ?? this.intent,
      cardType: cardType ?? this.cardType,
      cards: cards ?? this.cards, // ✅ DEPRECATED
      cardsByDomain: cardsByDomain ?? this.cardsByDomain, // ✅ NEW
      uiRequirements: uiRequirements ?? this.uiRequirements, // ✅ NEW
      scenario: scenario ?? this.scenario, // ✅ ARCHITECTURE FIX: Backend scenario
      uiDecision: uiDecision ?? this.uiDecision, // ✅ ARCHITECTURE FIX: Backend UI decision
      results: results ?? this.results,
      sections: sections ?? this.sections, // ✅ FIX: Hotel sections
      mapPoints: mapPoints ?? this.mapPoints, // ✅ FIX: Map points
      destinationImages: destinationImages ?? this.destinationImages,
      videos: videos ?? this.videos, // ✅ NEW: Videos from search results
      locationCards: locationCards ?? this.locationCards,
      sources: sources ?? this.sources, // ✅ FIX: Sources
      followUpSuggestions: followUpSuggestions ?? this.followUpSuggestions, // ✅ FIX: Follow-up suggestions
      phase: phase ?? this.phase, // ✅ PERPLEXITY-STYLE: Phase can only advance forward
      isStreaming: isStreaming ?? this.isStreaming,
      isParsing: isParsing ?? this.isParsing,
      isFinalized: isFinalized ?? this.isFinalized, // ✅ PERPLEXITY-STYLE: Preserve finalized state
      hasReceivedFirstChunk: hasReceivedFirstChunk ?? this.hasReceivedFirstChunk, // ✅ PERPLEXITY-STYLE: Preserve first chunk state
      // ✅ NEW: UI Enhancement fields
      reasoningSteps: reasoningSteps ?? this.reasoningSteps, // ✅ Enhancement 1
      researchStep: researchStep ?? this.researchStep, // ✅ Enhancement 3
      maxResearchSteps: maxResearchSteps ?? this.maxResearchSteps, // ✅ Enhancement 3
      currentAction: currentAction ?? this.currentAction, // ✅ Enhancement 3
      parsedOutput: parsedOutput ?? this.parsedOutput,
      parsedSegments: parsedSegments ?? this.parsedSegments, // ✅ FIX 2
      allImages: allImages ?? this.allImages, // ✅ FIX 3
      timestamp: timestamp ?? this.timestamp,
      imageUrl: imageUrl ?? this.imageUrl,
      error: error ?? this.error, // ✅ NEW: Error message
      conversationId: conversationId ?? this.conversationId, // ✅ NEW: Conversation ID
    );
  }

  /// ✅ MERGE: Merge incoming partial update with existing session (ChatGPT/Perplexity-style)
  /// Rules:
  /// - Lists: null → keep existing, non-empty → replace, empty [] → clear
  /// - Strings: null/empty → keep existing, non-empty → replace
  /// - cardsByDomain: null → keep existing, non-null → merge by domain key
  /// - Booleans: always use incoming value
  /// - ✅ PERPLEXITY-STYLE: If existing session is finalized, streaming events cannot overwrite structured data
  QuerySession mergeWith(QuerySession incoming) {
    // ✅ PERPLEXITY-STYLE: If existing session is finalized, streaming events can only update summary
    // Structured data (sections, sources, cards) is locked and cannot be overwritten
    final isExistingFinalized = this.isFinalized;
    // ✅ Rule 1: Lists (sections, sources, followUpSuggestions)
    // ✅ PERPLEXITY-STYLE: If existing is finalized, preserve structured data (sections, sources, cards)
    // Streaming "message" events cannot overwrite data set by "end" event
    List<Map<String, dynamic>>? mergedSections;
    if (isExistingFinalized) {
      // ✅ FINALIZED: Preserve existing sections - streaming cannot overwrite
      mergedSections = this.sections;
    } else if (incoming.sections == null) {
      mergedSections = this.sections; // Keep existing
    } else {
      mergedSections = incoming.sections; // Replace (even if empty)
    }

    // ✅ sources is non-nullable List
    List<Map<String, dynamic>> mergedSources;
    if (isExistingFinalized) {
      // ✅ FINALIZED: Preserve existing sources - streaming cannot overwrite
      mergedSources = this.sources;
    } else {
      // For non-nullable lists, we always use incoming (even if empty = explicit clear)
      mergedSources = incoming.sources; // Replace (even if empty)
    }

    // ✅ followUpSuggestions is non-nullable List
    List<String> mergedFollowUpSuggestions;
    if (isExistingFinalized) {
      // ✅ FINALIZED: Preserve existing follow-ups - streaming cannot overwrite
      mergedFollowUpSuggestions = this.followUpSuggestions;
    } else {
      // For non-nullable lists, we always use incoming (even if empty = explicit clear)
      mergedFollowUpSuggestions = incoming.followUpSuggestions; // Replace (even if empty)
    }

    // ✅ Rule 2: Summary/text fields
    // null/empty → keep existing, non-empty → replace
    String? mergedSummary;
    if (incoming.summary == null || incoming.summary!.isEmpty) {
      mergedSummary = this.summary; // Keep existing
    } else {
      mergedSummary = incoming.summary; // Replace
    }

    // ✅ CRITICAL: Answer field - preserve full answer text (not just summary)
    // If finalized, preserve existing answer - streaming cannot overwrite
    String? mergedAnswer;
    if (isExistingFinalized) {
      // ✅ FINALIZED: Preserve existing answer - streaming cannot overwrite
      mergedAnswer = this.answer;
    } else if (incoming.answer == null || incoming.answer!.isEmpty) {
      mergedAnswer = this.answer; // Keep existing
    } else {
      mergedAnswer = incoming.answer; // Replace with full answer from END event
    }

    String? mergedIntent;
    if (incoming.intent == null || incoming.intent!.isEmpty) {
      mergedIntent = this.intent; // Keep existing
    } else {
      mergedIntent = incoming.intent; // Replace
    }

    String? mergedCardType;
    if (incoming.cardType == null || incoming.cardType!.isEmpty) {
      mergedCardType = this.cardType; // Keep existing
    } else {
      mergedCardType = incoming.cardType; // Replace
    }

    String? mergedImageUrl;
    if (incoming.imageUrl == null || incoming.imageUrl!.isEmpty) {
      mergedImageUrl = this.imageUrl; // Keep existing
    } else {
      mergedImageUrl = incoming.imageUrl; // Replace
    }

    String? mergedError;
    if (incoming.error == null || incoming.error!.isEmpty) {
      mergedError = this.error; // Keep existing
    } else {
      mergedError = incoming.error; // Replace
    }

    // ✅ Rule 3: cardsByDomain - merge by domain key
    // ✅ PERPLEXITY-STYLE: If finalized, preserve existing cards - streaming cannot overwrite
    Map<String, dynamic>? mergedCardsByDomain;
    if (isExistingFinalized) {
      // ✅ FINALIZED: Preserve existing cards - streaming cannot overwrite
      mergedCardsByDomain = this.cardsByDomain;
    } else if (incoming.cardsByDomain == null) {
      mergedCardsByDomain = this.cardsByDomain; // Keep existing
    } else {
      // Merge by domain: replace domains present in incoming, preserve others
      final merged = <String, dynamic>{};
      if (this.cardsByDomain != null) {
        merged.addAll(this.cardsByDomain!); // Start with existing
      }
      merged.addAll(incoming.cardsByDomain!); // Overwrite with incoming domains
      mergedCardsByDomain = merged.isEmpty ? null : merged;
    }

    // ✅ Rule 4: Other lists
    // ✅ PERPLEXITY-STYLE: If finalized, preserve structured data - streaming cannot overwrite
    // Non-nullable lists: always use incoming (even if empty = explicit clear)
    // Nullable lists: null → keep existing, non-null → replace
    
    // destinationImages is non-nullable List<String>
    final mergedDestinationImages = isExistingFinalized 
        ? this.destinationImages // ✅ FINALIZED: Preserve existing
        : incoming.destinationImages; // Replace (even if empty)
    
    // videos is nullable List<Map<String, dynamic>>?
    List<Map<String, dynamic>>? mergedVideos;
    if (isExistingFinalized) {
      mergedVideos = this.videos; // ✅ FINALIZED: Preserve existing
    } else if (incoming.videos == null) {
      mergedVideos = this.videos; // Keep existing
    } else {
      mergedVideos = incoming.videos; // Replace (even if empty)
    }

    // mapPoints is nullable List<Map<String, dynamic>>?
    List<Map<String, dynamic>>? mergedMapPoints;
    if (isExistingFinalized) {
      mergedMapPoints = this.mapPoints; // ✅ FINALIZED: Preserve existing
    } else if (incoming.mapPoints == null) {
      mergedMapPoints = this.mapPoints; // Keep existing
    } else {
      mergedMapPoints = incoming.mapPoints; // Replace (even if empty)
    }

    // locationCards is non-nullable List<Map<String, dynamic>>
    final mergedLocationCards = isExistingFinalized
        ? this.locationCards // ✅ FINALIZED: Preserve existing
        : incoming.locationCards; // Replace (even if empty)
    
    // results is non-nullable List<dynamic>
    final mergedResults = isExistingFinalized
        ? this.results // ✅ FINALIZED: Preserve existing
        : incoming.results; // Replace (even if empty)

    // ✅ Rule 5: Other optional fields
    Map<String, dynamic>? mergedUiRequirements;
    if (incoming.uiRequirements == null) {
      mergedUiRequirements = this.uiRequirements; // Keep existing
    } else {
      mergedUiRequirements = incoming.uiRequirements; // Replace
    }
    
    // ✅ ARCHITECTURE FIX: Merge scenario and uiDecision (backend decisions)
    String? mergedScenario;
    if (incoming.scenario == null) {
      mergedScenario = this.scenario; // Keep existing
    } else {
      mergedScenario = incoming.scenario; // Replace (backend decision is authoritative)
    }
    
    Map<String, dynamic>? mergedUiDecision;
    if (incoming.uiDecision == null) {
      mergedUiDecision = this.uiDecision; // Keep existing
    } else {
      mergedUiDecision = incoming.uiDecision; // Replace (backend decision is authoritative)
    }

    List<Map<String, dynamic>>? mergedParsedSegments;
    if (incoming.parsedSegments == null) {
      mergedParsedSegments = this.parsedSegments; // Keep existing
    } else {
      mergedParsedSegments = incoming.parsedSegments; // Replace (even if empty)
    }

    List<String>? mergedAllImages;
    if (incoming.allImages == null) {
      mergedAllImages = this.allImages; // Keep existing
    } else {
      mergedAllImages = incoming.allImages; // Replace (even if empty)
    }

    ParsedContent? mergedParsedOutput;
    if (incoming.parsedOutput == null) {
      mergedParsedOutput = this.parsedOutput; // Keep existing
    } else {
      mergedParsedOutput = incoming.parsedOutput; // Replace
    }

    // ✅ NEW: UI Enhancement fields - always merge (append for reasoning, replace for progress)
    List<String> mergedReasoningSteps;
    if (incoming.reasoningSteps.isEmpty) {
      mergedReasoningSteps = this.reasoningSteps; // Keep existing
    } else {
      // Append new reasoning steps (don't replace, accumulate)
      mergedReasoningSteps = [...this.reasoningSteps, ...incoming.reasoningSteps];
    }

    // Research progress - always use incoming if provided (real-time updates)
    final mergedResearchStep = incoming.researchStep ?? this.researchStep;
    final mergedMaxResearchSteps = incoming.maxResearchSteps ?? this.maxResearchSteps;
    final mergedCurrentAction = incoming.currentAction ?? this.currentAction;

    // ✅ PERPLEXITY-STYLE: Phase can only advance forward (searching → answering → done)
    QueryPhase mergedPhase;
    if (incoming.phase.index > this.phase.index) {
      mergedPhase = incoming.phase; // Advance phase
    } else {
      mergedPhase = this.phase; // Keep existing phase (never go backwards)
    }

    // ✅ Rule 6: Booleans - always use incoming value
    // ✅ PERPLEXITY-STYLE: isFinalized can only go from false → true (never back to false)
    final mergedIsStreaming = incoming.isStreaming;
    final mergedIsParsing = incoming.isParsing;
    final mergedIsFinalized = incoming.isFinalized || this.isFinalized; // Once true, stays true

    // ✅ Query and timestamp: use existing (shouldn't change during merge)
    // Cards (deprecated): keep existing for backward compatibility
    final mergedCards = this.cards; // Keep existing (deprecated field)

    return QuerySession(
      sessionId: this.sessionId, // ✅ CRITICAL: Preserve sessionId during merge
      query: this.query, // Query never changes
      summary: mergedSummary,
      answer: mergedAnswer, // ✅ CRITICAL: Preserve full answer text
      intent: mergedIntent,
      cardType: mergedCardType,
      cards: mergedCards, // ✅ DEPRECATED: Keep existing
      cardsByDomain: mergedCardsByDomain,
      uiRequirements: mergedUiRequirements,
      scenario: mergedScenario,
      uiDecision: mergedUiDecision,
      results: mergedResults,
      sections: mergedSections,
      mapPoints: mergedMapPoints,
      destinationImages: mergedDestinationImages,
      videos: mergedVideos,
      locationCards: mergedLocationCards,
      sources: mergedSources,
      followUpSuggestions: mergedFollowUpSuggestions,
      phase: mergedPhase, // ✅ PERPLEXITY-STYLE: Phase can only advance forward
      isStreaming: mergedIsStreaming,
      isParsing: mergedIsParsing,
      isFinalized: mergedIsFinalized, // ✅ PERPLEXITY-STYLE: Preserve finalized state
      parsedOutput: mergedParsedOutput,
      parsedSegments: mergedParsedSegments,
      allImages: mergedAllImages,
      timestamp: this.timestamp, // Timestamp never changes
      imageUrl: mergedImageUrl,
      error: mergedError,
      // ✅ NEW: UI Enhancement fields
      reasoningSteps: mergedReasoningSteps, // ✅ Enhancement 1
      researchStep: mergedResearchStep, // ✅ Enhancement 3
      maxResearchSteps: mergedMaxResearchSteps, // ✅ Enhancement 3
      currentAction: mergedCurrentAction, // ✅ Enhancement 3
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId, // ✅ CRITICAL: Include sessionId for persistence
      'query': query,
      'summary': summary,
      'answer': answer, // ✅ CRITICAL: Include full answer text
      'intent': intent,
      'cardType': cardType,
      'cards': cards, // ✅ DEPRECATED
      'cardsByDomain': cardsByDomain, // ✅ NEW
      'uiRequirements': uiRequirements, // ✅ NEW
      'results': results,
      'sections': sections, // ✅ FIX: Include sections for hotels
      'mapPoints': mapPoints, // ✅ FIX: Include map points for hotels
      'destinationImages': destinationImages,
      'videos': videos, // ✅ NEW: Include videos from search results
      'locationCards': locationCards,
      'sources': sources, // ✅ FIX: Include sources
      'followUpSuggestions': followUpSuggestions, // ✅ FIX: Include follow-up suggestions
      'phase': phase.name, // ✅ PERPLEXITY-STYLE: Include phase
      'isStreaming': isStreaming,
      'isParsing': isParsing,
      'timestamp': timestamp.toIso8601String(),
      'imageUrl': imageUrl,
      'error': error, // ✅ NEW: Error message
      // Note: parsedOutput is not serialized as it's computed
    };
  }

  factory QuerySession.fromJson(Map<String, dynamic> json) {
    return QuerySession(
      sessionId: json['sessionId'] as String?, // ✅ CRITICAL: Restore sessionId if present
      query: json['query'] as String,
      summary: json['summary'] as String?,
      answer: json['answer'] as String?, // ✅ CRITICAL: Include full answer text
      intent: json['intent'] as String?,
      cardType: json['cardType'] as String?,
      cards: (json['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [], // ✅ DEPRECATED
      cardsByDomain: json['cardsByDomain'] != null ? Map<String, dynamic>.from(json['cardsByDomain']) : null, // ✅ NEW
      uiRequirements: json['uiRequirements'] != null ? Map<String, dynamic>.from(json['uiRequirements']) : null, // ✅ NEW
      results: json['results'] as List? ?? [],
      sections: (json['sections'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(), // ✅ FIX: Include sections
      mapPoints: (json['mapPoints'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(), // ✅ FIX: Include map points
      destinationImages: (json['destinationImages'] as List?)?.map((e) => e.toString()).toList() ?? [],
      locationCards: (json['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
      sources: (json['sources'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [], // ✅ FIX: Include sources
      followUpSuggestions: (json['followUpSuggestions'] as List?)?.map((e) => e.toString()).toList() ?? [], // ✅ FIX: Include follow-up suggestions
      phase: json['phase'] != null ? QueryPhase.values.firstWhere((p) => p.name == json['phase'], orElse: () => QueryPhase.searching) : QueryPhase.searching, // ✅ PERPLEXITY-STYLE: Restore phase
      isStreaming: json['isStreaming'] as bool? ?? false,
      isParsing: json['isParsing'] as bool? ?? false,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : null,
      imageUrl: json['imageUrl'] as String?,
      error: json['error'] as String?, // ✅ NEW: Error message
    );
  }
}


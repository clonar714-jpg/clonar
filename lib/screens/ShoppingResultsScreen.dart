import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../isolates/text_parsing_isolate.dart' show ParsedContent;
import '../isolates/hotel_summary_isolate.dart' show buildHotelSummary; // ✅ FIX 1
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Product.dart';
import '../providers/agent_provider.dart';
import '../providers/parsed_agent_output_provider.dart';
import '../providers/session_history_provider.dart';
import '../providers/follow_up_engine_provider.dart';
import '../providers/follow_up_controller_provider.dart';
import '../providers/display_content_provider.dart';
import '../providers/scroll_provider.dart';
import '../models/query_session_model.dart';
import '../widgets/AnswerHeaderRow.dart';
import '../widgets/GoogleMapWidget.dart';
import '../widgets/HotelMapView.dart';
import '../widgets/StreamingTextWidget.dart';
import '../widgets/SessionRenderer.dart';
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

// ✅ RIVERPOD: Removed old QuerySession class - now using lib/models/query_session_model.dart

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

class ShoppingResultsScreen extends ConsumerStatefulWidget {
  final String query;
  final String? imageUrl;
  final List<Map<String, dynamic>>? initialConversationHistory; // ✅ Accept conversation history

  const ShoppingResultsScreen({
    super.key,
    required this.query,
    this.imageUrl,
    this.initialConversationHistory, // ✅ Optional conversation history
  });

  @override
  ConsumerState<ShoppingResultsScreen> createState() => _ShoppingResultsScreenState();
}

class _ShoppingResultsScreenState extends ConsumerState<ShoppingResultsScreen> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // ✅ STEP 3: Prevent rebuilds
  
  // ✅ PHASE 4B: All animation state removed - now using streamingTextProvider
  
  // ✅ RIVERPOD: Keep only UI-related state (not business logic)
  // Map to store product links by product ID (UI state only)
  final Map<int, String> _productLinks = {};
  // Keeps track of expanded summaries per query index (UI state only)
  final Map<int, bool> _expandedSummaries = {};
  // ✅ STEP 2: Cache for hotel summaries (UI state only)
  final Map<String, String> _hotelSummaryCache = {};

  static const int _maxVisibleProducts = 12;
  static const int _maxVisibleHotelsPerSection = 8;
  static const int _maxVisiblePlaces = 8;
  static const int _maxVisibleMovies = 6;

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
  // ✅ FIX 5: Replace Timer debounce with ValueNotifier (prevents rebuilds)
  final ValueNotifier<String> _followUpTextNotifier = ValueNotifier<String>('');

  // Hotel view mode: 'list' or 'map' (UI state only)
  String _hotelViewMode = 'list';

  // Scroll-to-bottom button state (UI state only)
  bool _isAtBottom = true;
  bool _showScrollToBottomButton = false;
  Timer? _scrollThrottleTimer;
  final double _scrollThreshold = 150.0; // px threshold for showing button
  
  // ✅ RIVERPOD: Removed _buildSessionsFromResponse - now using sessionHistoryProvider directly

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // register lifecycle listener
    if (kDebugMode) {
      debugPrint('ShoppingResultsScreen query: "${widget.query}"');
    }
    
    // ✅ FIX 4: Ensure keyboard doesn't auto-pop when navigating back
    // Unfocus the follow-up field immediately to prevent auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _followUpFocusNode.unfocus();
      }
    });
    
    // Add scroll listener for scroll-to-bottom button
    _scrollController.addListener(_handleScroll);
    
    // ✅ RIVERPOD: Initialize query keys for initial conversation history
    if (widget.initialConversationHistory != null && widget.initialConversationHistory!.isNotEmpty) {
      for (int i = 0; i < widget.initialConversationHistory!.length; i++) {
        _queryKeys.add(GlobalKey());
      }
    }
    // Add key for current query
      _queryKeys.add(GlobalKey());
    
    // ✅ RIVERPOD: Trigger agent query on init (deferred to after first frame)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
        // ✅ FIX: Only submit query if it hasn't been submitted already (check session history)
        // Check if there's already a session with this exact query (including imageUrl)
        // This prevents duplicate submissions when ShopScreen already submitted the query
        final existingSessions = ref.read(sessionHistoryProvider);
        final trimmedQuery = widget.query.trim();
        final queryAlreadySubmitted = existingSessions.any((s) => 
          s.query.trim() == trimmedQuery && 
          s.imageUrl == widget.imageUrl &&
          (s.isStreaming || s.isParsing || s.summary != null) // Check if query is processing or completed
        );
        
        if (!queryAlreadySubmitted) {
          // Submit query to agent provider only if not already submitted
          ref.read(agentControllerProvider.notifier).submitQuery(widget.query, imageUrl: widget.imageUrl);
        } else if (kDebugMode) {
          debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery" (already in session history)');
        }
      }
    });
    
    _followUpController.addListener(() {
      // Removed print from listener - avoid logging every keystroke
    });
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

  // ✅ PHASE 4C: Removed deprecated _streamAnswerResponse and _waitForAnimationToComplete methods
  // These methods are now handled by agentControllerProvider and streamingTextProvider
  // ✅ FINAL CLEANUP: Removed _generateFollowUpSuggestions and _generateFallbackSuggestions
  // Follow-up suggestions are now handled by the backend and Riverpod providers

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
    if (kDebugMode) {
      debugPrint('🧭 Opening directions for hotel: ${hotel['name'] ?? hotel['title']}');
    }
    
    // Priority 1: Use coordinates if available (most accurate)
    final coords = GeocodingService.extractCoordinates(hotel);
    
    if (coords != null && coords['latitude'] != null && coords['longitude'] != null) {
      final lat = coords['latitude']!;
      final lng = coords['longitude']!;
      
      // Validate coordinates (not 0,0)
      if (lat != 0.0 && lng != 0.0) {
        // Use /dir/ endpoint for turn-by-turn directions
        final Uri mapsUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
        if (await canLaunchUrl(mapsUri)) {
          await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
          if (kDebugMode) {
            debugPrint('✅ Opened Google Maps with coordinates');
          }
          return;
        } else {
          if (kDebugMode) {
            debugPrint('❌ Cannot launch URL: $mapsUri');
          }
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
        if (kDebugMode) {
          debugPrint('🗺️ Switching hotel view to: $mode');
        }
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

  Widget _buildViewAllProductsButton(List<Product> products) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: AppColors.primary,
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShoppingGridScreen(products: products),
            ),
          );
        },
        icon: const Icon(Icons.grid_view, size: 16, color: AppColors.primary),
        label: Text(
          'View all ${products.length} products',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildViewAllHotelsButton(String query, {int hiddenCount = 0}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: AppColors.primary,
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: query),
            ),
          );
        },
        icon: const Icon(Icons.travel_explore, size: 16, color: AppColors.primary),
        label: Text(
          hiddenCount > 0
              ? 'View full list (+$hiddenCount more)'
              : 'View full hotel list',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsNote(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  // ✅ PRODUCTION FIX: Use ValueNotifier instead of setState to prevent rebuilds
  final ValueNotifier<bool> _isAtBottomNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _showScrollButtonNotifier = ValueNotifier<bool>(false);
  
  // Handle scroll events with throttling for performance
  void _handleScroll() {
    // Throttle scroll events to improve performance
    _scrollThrottleTimer?.cancel();
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      final distanceFromBottom = maxScroll - currentScroll;
      
      // Check if user is at bottom (within 10px tolerance)
      final isAtBottomNow = distanceFromBottom <= 10.0;
      
      // Show button if scrolled up and at least 150px from bottom
      final shouldShowButton = !isAtBottomNow && distanceFromBottom >= _scrollThreshold;
      
      // ✅ PRODUCTION FIX: Update ValueNotifiers instead of setState (prevents full rebuild)
      if (mounted) {
        _isAtBottomNotifier.value = isAtBottomNow;
        _showScrollButtonNotifier.value = shouldShowButton;
        // Keep local state in sync for backward compatibility
        _isAtBottom = isAtBottomNow;
        _showScrollToBottomButton = shouldShowButton;
      }
    });
  }

  // Scroll to bottom smoothly
  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;
    
    try {
          final maxScroll = _scrollController.position.maxScrollExtent;
      await _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      
      // ✅ PRODUCTION FIX: Update ValueNotifiers instead of setState
      if (mounted) {
        _isAtBottomNotifier.value = true;
        _showScrollButtonNotifier.value = false;
        _isAtBottom = true;
        _showScrollToBottomButton = false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error scrolling to bottom: $e');
      }
      // Fallback: jump to bottom if animate fails
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        if (mounted) {
          _isAtBottomNotifier.value = true;
          _showScrollButtonNotifier.value = false;
          _isAtBottom = true;
          _showScrollToBottomButton = false;
        }
      }
    }
  }

  // Check scroll position when new content loads
  void _checkScrollPositionAfterContentLoad() {
                if (!mounted || !_scrollController.hasClients) return;
                
    WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      final distanceFromBottom = maxScroll - currentScroll;
      
      final isAtBottomNow = distanceFromBottom <= 10.0;
      final shouldShowButton = !isAtBottomNow && distanceFromBottom >= _scrollThreshold;
      
      if (mounted) {
        _isAtBottomNotifier.value = isAtBottomNow;
        _showScrollButtonNotifier.value = shouldShowButton;
        _isAtBottom = isAtBottomNow;
        _showScrollToBottomButton = shouldShowButton;
                  }
                });
              }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    // ✅ FIX 5: Dispose ValueNotifier
    _followUpTextNotifier.dispose();
    _followUpController.dispose();
    _followUpFocusNode.dispose();
    _scrollThrottleTimer?.cancel();
    _isAtBottomNotifier.dispose();
    _showScrollButtonNotifier.dispose();
    super.dispose();
  }

  // ✅ STEP 9: Accept previousContext to pass to backend
  // ✅ FOLLOW-UP PATCH: Accept lastFollowUp and parentQuery
  // ✅ RIVERPOD: Updated to use agentControllerProvider
  void _onFollowUpSubmitted({
    QuerySession? previousContext,
    String? lastFollowUp,
    String? parentQuery,
  }) {
    final query = _followUpController.text.trim();
    if (kDebugMode) {
      debugPrint('ShoppingResultsScreen follow-up query: "$query"');
    }
    
    if (query.isNotEmpty) {
      // Clear the field first
      _followUpController.clear();
      
      // ✅ RIVERPOD: Get previous session from provider
      final sessions = ref.read(sessionHistoryProvider);
      final previousSession = previousContext ?? 
          (sessions.isNotEmpty ? sessions.last : null);
      
      // ✅ RIVERPOD: Submit follow-up query using agent controller
      ref.read(agentControllerProvider.notifier).submitFollowUp(
        query,
        previousSession?.query ?? '',
      );
      
      // Add query key for new session
      _queryKeys.add(GlobalKey());
      
      // Dismiss keyboard after a short delay
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      });
    } else {
      // If empty, just focus back to the field
      if (kDebugMode) {
        debugPrint('Empty query - refocusing field');
      }
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
        // ✅ PATCH B: Prevent scroll lock / ensureVisible freeze
        Future.delayed(const Duration(milliseconds: 1), () {
          if (!mounted) return;
          Scrollable.ensureVisible(
            context!,
            duration: const Duration(milliseconds: 1),
            alignment: 0.0, // 0.0 = top of viewport
            curve: Curves.easeOut,
          );
        });
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
    if (kDebugMode) {
      debugPrint('🎯 _scrollToQuery called with index: $queryIndex');
    }
    
    // Wait a bit for the widget to be fully built
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) {
        return;
      }
      
      if (queryIndex >= 0 && queryIndex < _queryKeys.length) {
        final key = _queryKeys[queryIndex];
        final hasContext = key.currentContext != null;
        
        if (hasContext) {
          // ✅ PATCH B: Prevent scroll lock / ensureVisible freeze
          Future.delayed(const Duration(milliseconds: 1), () {
            if (!mounted) return;
            try {
              Scrollable.ensureVisible(
                key.currentContext!,
                duration: const Duration(milliseconds: 1),
                alignment: 0.0, // 0.0 = top of viewport
                curve: Curves.easeInOut,
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('   ❌ Scrollable.ensureVisible failed: $e');
              }
            }
          });
          return;
      }
      }
      
      // Fallback: calculate approximate scroll position
      if (_scrollController.hasClients) {
        // Estimate position: each query session is roughly 600-800px tall
        final estimatedPosition = queryIndex * 700.0;
        final clampedPosition = estimatedPosition.clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          clampedPosition,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // ✅ FINAL CLEANUP: Removed orphaned _handleAgentResponse method - now handled by agentControllerProvider

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

  // ✅ FINAL CLEANUP: Removed orphaned deprecated method body - all logic moved to Riverpod providers

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
    
    // ✅ PRODUCTION: Removed debug prints to prevent emulator freezes
    
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

    // ✅ FIX: ref.listen can only be called directly in build method, not inside Builder widgets
    // Listen to scroll provider for auto-scroll events
    ref.listen<ScrollEvent?>(scrollProvider, (previous, next) {
      if (!mounted) return;
      if (next != null && _scrollController.hasClients) {
        switch (next) {
          case ScrollEvent.scrollToBottom:
            _scrollToBottom();
            break;
          case ScrollEvent.scrollToTop:
            if (mounted && _scrollController.hasClients) {
              _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            }
            break;
          case ScrollEvent.scrollToIndex:
            if (mounted) {
              final sessions = ref.read(sessionHistoryProvider);
              if (sessions.isNotEmpty && _queryKeys.length > sessions.length - 1) {
                final key = _queryKeys[sessions.length - 1];
                final context = key.currentContext;
                if (context != null && mounted) {
                  Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                }
              }
            }
            break;
        }
      }
    });
    
    // ✅ FIX: Listen to session history changes - scroll to top when new query is added
    ref.listen<List<QuerySession>>(sessionHistoryProvider, (previous, next) {
      if (!mounted) return;
      if (next.length > (previous?.length ?? 0)) {
        // New query added - scroll to top to show the query
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(scrollProvider.notifier).scrollToTop();
          }
        });
      }
    });
    
    // ✅ FIX: Don't auto-scroll when results arrive - keep position at top
    // Removed auto-scroll on agent state change - user should see query at top and swipe up to see results

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
      body: Stack(
        children: [
          GestureDetector(
        behavior: HitTestBehavior.translucent, // Changed from opaque to allow scrolling
        onTap: () {
          FocusScope.of(context).unfocus(); // dismiss keyboard on any tap
        },
        child: Column(
        children: [
              // ✅ PRODUCTION: Optimized session history watch - only rebuilds when length changes
              Builder(
                builder: (context) {
                  // ✅ PRODUCTION FIX: Use .select() to only watch session count, not entire list
                  // This prevents rebuilds when session content changes (only rebuilds when new session added)
                  final sessionCount = ref.watch(sessionHistoryProvider.select((sessions) => sessions.length));
                  final sessions = ref.read(sessionHistoryProvider); // Read once, don't watch
                  
                  // ✅ FIX: ref.listen calls moved to main build method (above this Builder)
                  // ref.listen can only be called directly in build method, not inside Builder widgets
                  
                  // ✅ FIX: Move session restoration to initState to avoid blocking build
                  // If no sessions and we have initial conversation history, restore it
                  // ✅ CRITICAL FIX: Clear session history first to ensure only this chat's sessions are shown
                  if (widget.initialConversationHistory != null && widget.initialConversationHistory!.isNotEmpty) {
                    // ✅ PRODUCTION FIX: Defer session restoration to avoid blocking build
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      
                      // ✅ CRITICAL FIX: Clear existing sessions first to prevent showing chats from other conversations
                      ref.read(sessionHistoryProvider.notifier).clear();
                      
                      // Now restore only this chat's conversation history
                      for (final sessionData in widget.initialConversationHistory!) {
                        final session = QuerySession(
                          query: sessionData['query'] as String,
                          summary: sessionData['summary'] as String?,
                          intent: sessionData['intent'] as String?,
                          cardType: sessionData['cardType'] as String?,
                          cards: (sessionData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                          results: sessionData['results'] ?? [],
                          destinationImages: (sessionData['destination_images'] as List?)?.map((e) => e.toString()).toList() ?? [],
                          locationCards: (sessionData['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                          isStreaming: false,
                          isParsing: false,
                        );
                        ref.read(sessionHistoryProvider.notifier).addSession(session);
                      }
                    });
                  }
                  
                  // ✅ PRODUCTION: Use CustomScrollView + SliverList for better performance
                  // ✅ FIX: Removed nested Column - CustomScrollView handles all scrolling
                  return Expanded(
                    child: RepaintBoundary(
                      child: CustomScrollView(
              controller: _scrollController,
                        slivers: [
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                // ✅ FIX: Watch session history to rebuild when sessions update
                                final currentSessions = ref.watch(sessionHistoryProvider);
                                
                                // ✅ DEBUG: Log when UI rebuilds
                                if (index == 0 && currentSessions.isNotEmpty) {
                                  final firstSession = currentSessions[0];
                                  print("🔄 UI REBUILD - Session count: ${currentSessions.length}");
                                  print("  - First session query: ${firstSession.query}");
                                  print("  - First session isStreaming: ${firstSession.isStreaming}");
                                  print("  - First session cards: ${firstSession.cards.length}");
                                  print("  - First session summary: ${firstSession.summary != null && firstSession.summary!.isNotEmpty}");
                                }
                                
                                if (index >= currentSessions.length) return const SizedBox.shrink();
                                
                                final session = currentSessions[index];
                                
                                // ✅ PRODUCTION FIX: Move parsing logic out of build - handle in provider
                                // Parsing should be handled by agent_provider, not in UI build method
                                
                                return RepaintBoundary(
                                  key: ValueKey('session-$index-${session.query.hashCode}'),
                                  child: SessionRenderer(
                                    model: SessionRenderModel(
                                      session: session,
                                      index: index,
                                      context: context,
                                      onFollowUpTap: _onFollowUpQuerySelected,
                                      onHotelTap: _navigateToHotelDetail,
                                      onProductTap: (product) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ProductDetailScreen(product: product),
                                          ),
                                        );
                                      },
                                      onViewAllHotels: (query) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => HotelResultsScreen(query: query),
                                          ),
                                        );
                                      },
                                      onViewAllProducts: (query) {
                                        final sessions = ref.read(sessionHistoryProvider);
                                        final currentSession = sessions.isNotEmpty ? sessions.last : null;
                                        if (currentSession != null && currentSession.products.isNotEmpty) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ShoppingGridScreen(products: currentSession.products),
                                            ),
                                          );
                                        }
                                      },
                                      query: widget.query,
                                    ),
                                  ),
                                );
                              },
                              childCount: sessionCount, // Use watched count for list length
                              // ✅ PRODUCTION: Enable keepAlive to prevent map widgets from being disposed when scrolled out of view
                              addAutomaticKeepAlives: true,
                              addRepaintBoundaries: false, // We already wrap in RepaintBoundary
                            ),
                          ),
                          // ✅ FIX: Add bottom padding to prevent content from being hidden under follow-up bar
                          SliverPadding(
                            padding: const EdgeInsets.only(bottom: 100), // Account for follow-up bar height (SafeArea + padding + input field)
                          ),
                        ],
                      ),
                    ),
                  );
                },
          ),
          
          // Follow-up input bar
          _buildFollowUpBar(),
        ],
        ),
          ),
          // Scroll-to-bottom floating button
          _buildScrollToBottomButton(),
        ],
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
          // ✅ PRODUCTION FIX: Move history building to microtask to avoid blocking navigation
          Future.delayed(const Duration(milliseconds: 100), () {
            Future.microtask(() {
              if (!mounted) return;
            // ✅ Return conversation history when navigating back
              final sessions = ref.read(sessionHistoryProvider);
              final historyToReturn = sessions.map((session) {
              return {
                'query': session.query,
                'summary': session.summary ?? '',
                'intent': session.intent ?? session.resultType,
                'cardType': session.cardType ?? session.resultType,
                'cards': session.products.map((p) => {
                  'title': p.title,
                  'price': p.price,
                  'rating': p.rating,
                  'images': p.images,
                  'source': p.source,
                }).toList(),
                'results': session.rawResults,
              };
            }).toList();
              if (mounted) {
            Navigator.pop(context, historyToReturn);
              }
            });
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

  // Build scroll-to-bottom floating button
  Widget _buildScrollToBottomButton() {
    // Calculate bottom position accounting for follow-up bar (approximately 80px)
    final bottomPosition = 80.0;
    // Calculate horizontal center position
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonWidth = 44.0;
    final leftPosition = (screenWidth - buttonWidth) / 2;
    
    // ✅ PRODUCTION FIX: Use ValueListenableBuilder to prevent full rebuilds
    return ValueListenableBuilder<bool>(
      valueListenable: _showScrollButtonNotifier,
      builder: (context, showButton, child) {
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          bottom: showButton ? bottomPosition : -60.0, // Slide down when hidden
          left: leftPosition,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showButton ? 1.0 : 0.0,
              child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: showButton ? 1.0 : 0.8,
              child: Material(
                elevation: 8.0,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: const CircleBorder(),
                color: AppColors.surface,
                child: InkWell(
                  onTap: _scrollToBottom,
                  borderRadius: BorderRadius.circular(24.0),
                  child: Container(
                    width: 44.0,
                    height: 44.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.border.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textPrimary,
                      size: 28.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
          
          // Show loading state ONLY if streaming AND no cards/data available yet
          // ✅ FIX: Show content even if parsing is in progress, as long as we have data
          if (session.isStreaming && session.cards.isEmpty && session.locationCards.isEmpty && session.rawResults.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            // Show content when loaded (or if we have data even while parsing)
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
                        // ✅ FIX: Only show "Shopping" tag if intent is actually shopping AND products exist
                        // For places queries, always show "Places" tag regardless of products
                        _buildIntentTag(
                          (session.resultType == 'shopping' && session.products.isNotEmpty) 
                              ? 'shopping' 
                              : session.resultType, 
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
                  // ✅ FIX: Hotels summary is shown after map, not here
                  if (session.resultType != 'answer' && session.resultType != 'places' && session.resultType != 'location' && session.resultType != 'movies' && session.resultType != 'hotel' && session.resultType != 'hotels')
                    _buildSummarySection(session, index),

                  if (session.resultType != 'answer' && session.resultType != 'places' && session.resultType != 'location' && session.resultType != 'movies' && session.resultType != 'hotel' && session.resultType != 'hotels')
                    const SizedBox(height: 12),

                  // ✅ FIX: For hotels, show map right after tags and before summary
                  if ((session.resultType == 'hotel' || session.resultType == 'hotels')) ...[
                    // ✅ PRODUCTION FIX: Calculate stable hash once, don't watch provider (prevents rebuilds)
                    Builder(
                      builder: (context) {
                        // ✅ PRODUCTION: Calculate hash from session directly (don't watch provider)
                        // This prevents rebuilds when other session data changes
                        final hotelCount = session.hotelResults.length;
                        final mapPointsCount = session.hotelMapPoints?.length ?? 0;
                        final hotelDataHash = '$hotelCount-$mapPointsCount'.hashCode;
                        
                        // ✅ PRODUCTION: Use stable key that only changes when hotel data changes
                        // ✅ PRODUCTION: Memoize map widget to prevent unnecessary rebuilds
                        final mapWidget = _buildHotelMap(session, hotelDataHash);
                        if (mapWidget != null) {
                          return RepaintBoundary(
                            key: ValueKey('hotel-map-$hotelDataHash'),
                            child: Column(
                              children: [
                                mapWidget,
                                const SizedBox(height: 16),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    // ✅ FIX: Show summary only once (after map, before hotels)
                    if (session.summary != null && session.summary!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        child: StreamingTextWidget(
                          targetText: session.summary ?? "",
                          enableAnimation: false, // ✅ PRODUCTION: Disabled to prevent frame skips
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],

                  // ✅ SHOW RESULTS BASED ON INTENT TYPE
                  _buildIntentBasedContent(session),

                  // ✅ FIX: Follow-ups appear AFTER all results (not inside intent content)
                  // This ensures they don't cover the last hotel results
                  // NOTE: Hotel follow-ups are now rendered INSIDE _buildIntentBasedContent (hotel layout)
                  // to ensure they appear after ALL hotel cards
                  if ((session.resultType == 'places' || session.resultType == 'location' ||
                      session.resultType == 'movies' || session.resultType == 'shopping')) ...[
                    const SizedBox(height: 32),
                    Builder(
                      builder: (context) {
                        final followUpsAsync = ref.watch(followUpEngineProvider(session));
                        return followUpsAsync.when(
                          data: (followUps) {
                            if (followUps.isEmpty) return const SizedBox.shrink();
                            // ✅ FIX: Limit to 3 follow-ups
                            final limitedFollowUps = followUps.take(3).toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...limitedFollowUps.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final suggestion = entry.value;
                                  return _buildFollowUpSuggestionItem(suggestion, index, session: session);
                                }),
                              ],
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ],

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
          // ✅ PHASE 6: Use unified display content provider
          Builder(
            builder: (context) {
              final contentAsync = ref.watch(displayContentProvider(session));
              return contentAsync.when(
                data: (content) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (content.summaryText.isNotEmpty)
                        _buildSummary(content.summaryText),
                      if (content.destinationImages.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildImageSection(content.destinationImages, session.query),
                      ],
                      if (content.locations.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildLocationSection(content.locations),
                      ],
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
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
            // ✅ PRODUCTION FIX: Use ListView.builder for products to handle large lists efficiently
            Builder(
              builder: (context) {
                final visibleProducts = session.products.take(_maxVisibleProducts).toList();
                return Column(
                  children: [
                    ...visibleProducts.map((p) {
                      final id = p.id.toString();
                      return KeyedSubtree(
                        key: ValueKey(id),
                        child: _buildProductCard(p),
                      );
                    }),
                    if (session.products.length > visibleProducts.length)
                      _buildViewAllProductsButton(session.products),
                  ],
                );
              },
            ),
          ],
          // ✅ FIX: Follow-ups are rendered AFTER all results (not here) to avoid duplicates
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
          // ✅ PRODUCTION FIX: Use ListView.builder for large product lists
          if (session.products.isNotEmpty)
            Builder(
              builder: (context) {
                final visibleProducts = session.products.take(_maxVisibleProducts).toList();
                return Column(
                  children: [
                    ...visibleProducts.map(
                      (p) => KeyedSubtree(
                        key: ValueKey(p.id.toString()),
                        child: _buildProductCard(p),
                      ),
                    ),
                    if (session.products.length > visibleProducts.length)
                      _buildViewAllProductsButton(session.products),
                  ],
                );
              },
            )
          else
            _buildEmptyProductsState(),
          // ✅ FIX: Follow-ups are rendered AFTER all results (not here) to avoid duplicates
        ],
      );
    }
    
    // 🏨 Hotel Layout (Perplexity-style - EXACT MATCH)
    if (intent == 'hotel' || intent == 'hotels') {
      // Check if we have the new grouped structure
      final hasSections = session.hotelSections != null && session.hotelSections!.isNotEmpty;
      final hasMapPoints = session.hotelMapPoints != null && session.hotelMapPoints!.isNotEmpty;
      
      // Debug logging removed from build method
      
      return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Important: Allow ListView to scroll
            children: [
          // ✅ FIX: Map is now rendered before _buildIntentBasedContent (after tags)
          // ✅ FIX: Summary is now rendered only once (removed duplicate)
          
          // ✅ STEP 3: Hotel sections (after description) - Perplexity style
          
          // ✅ STEP 3: Hotel sections (after description) - Perplexity style
          // Hotels displayed VERTICALLY (one after another), with section headings
          Builder(
            builder: (context) {
              // ✅ PRODUCTION: Removed debug print to prevent emulator freezes
              if (hasSections) {
                return Column(
                  children: session.hotelSections!.map((section) {
                    final title = section['title']?.toString() ?? 'Hotels';
                    final items = (section['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
                    
                    // Removed print from loop - only log summary outside build
                    if (items.isEmpty) {
                      // print('⚠️ Section "$title" is empty, skipping');
                      return const SizedBox.shrink(); // Hide empty sections
                    }
              
                    // Limit initial rendering to prevent blocking (show only a handful of cards)
                    final itemsToShow = items.take(_maxVisibleHotelsPerSection).toList();
                    final hiddenCount = items.length - itemsToShow.length;
              
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
                        // ✅ PRODUCTION FIX: Use ListView.builder for large hotel lists to prevent freeze
                        SizedBox(
                          height: itemsToShow.length * 250.0, // Approximate height per hotel card
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: itemsToShow.length,
                            itemBuilder: (context, idx) {
                              final hotel = itemsToShow[idx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 0),
                                child: Column(
                                  children: [
                                    KeyedSubtree(
                                      key: ValueKey(hotel['id']?.toString() ?? hotel['name']?.toString() ?? 'hotel-$idx'),
                                      child: _buildHotelCard(hotel, isHorizontal: false),
                                    ),

                                    if (idx < itemsToShow.length - 1) const SizedBox(height: 20),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        if (hiddenCount > 0) ...[

                          const SizedBox(height: 12),

                          _buildViewAllHotelsButton(session.query, hiddenCount: hiddenCount),

                        ],

                        const SizedBox(height: 24), // More spacing between sections
                      ],
                    );
                  }).toList(),
                );
              } else if (session.hotelResults.isNotEmpty) {
                // Fallback: Old flat list view
                final visibleHotels = session.hotelResults.take(_maxVisibleHotelsPerSection).toList();

                return Padding(

                  padding: const EdgeInsets.symmetric(horizontal: 0),

                  child: Column(

                    children: [

                      // ✅ PRODUCTION FIX: Use ListView.builder instead of .map() to prevent freeze
                      SizedBox(
                        height: visibleHotels.length * 250.0,
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: visibleHotels.length,
                          itemBuilder: (context, idx) {
                            final hotel = visibleHotels[idx];
                            return Column(
                              children: [
                                KeyedSubtree(
                                  key: ValueKey(hotel['id']?.toString() ?? hotel['name']?.toString() ?? 'hotel-$idx'),
                                  child: _buildHotelCard(hotel),
                                ),
                                if (idx < visibleHotels.length - 1) const SizedBox(height: 20),
                              ],
                            );
                          },
                        ),
                      ),

                      if (session.hotelResults.length > visibleHotels.length)

                        _buildViewAllHotelsButton(

                          session.query,

                          hiddenCount: session.hotelResults.length - visibleHotels.length,

                        ),

                    ],

                  ),

                );

              } else {
                return _buildEmptyHotelsState();
              }
            },
          ),
          // ✅ FIX: Follow-ups appear AFTER all hotel results (at the very end of hotel layout)
          const SizedBox(height: 32),
          Builder(
            builder: (context) {
              final followUpsAsync = ref.watch(followUpEngineProvider(session));
              return followUpsAsync.when(
                data: (followUps) {
                  if (followUps.isEmpty) return const SizedBox.shrink();
                  // ✅ FIX: Limit to 3 follow-ups
                  final limitedFollowUps = followUps.take(3).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...limitedFollowUps.asMap().entries.map((entry) {
                        final index = entry.key;
                        final suggestion = entry.value;
                        return _buildFollowUpSuggestionItem(suggestion, index, session: session);
                      }),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
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
                        ? CachedNetworkImage(
                            imageUrl: thumbnail,
                            fit: BoxFit.cover,
                            // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                            placeholder: (context, url) => Container(
                              color: AppColors.surfaceVariant,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) {
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
          // ✅ PHASE 5: Use follow-up engine provider
          Builder(
            builder: (context) {
              final followUpsAsync = ref.watch(followUpEngineProvider(session));
              return followUpsAsync.when(
                data: (followUps) {
                  if (followUps.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            const SizedBox(height: 24),
                      ...followUps.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
                        return _buildFollowUpSuggestionItem(suggestion, index, session: session);
            }),
          ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
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
          // ✅ PHASE 5: Use follow-up engine provider
          Builder(
            builder: (context) {
              final followUpsAsync = ref.watch(followUpEngineProvider(session));
              return followUpsAsync.when(
                data: (followUps) {
                  if (followUps.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            const SizedBox(height: 24),
                      ...followUps.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
                        return _buildFollowUpSuggestionItem(suggestion, index, session: session);
            }),
          ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
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
            StreamingTextWidget(
              targetText: session.summary ?? "",
              enableAnimation: false, // ✅ PRODUCTION: Disabled to prevent frame skips
              style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    height: 1.6,
                  ),
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
                  // ✅ PRODUCTION FIX: Limit places to prevent freeze, use ListView.builder for large lists
                  if (places.length > _maxVisiblePlaces)
                    SizedBox(
                      height: _maxVisiblePlaces * 200.0, // Approximate height per place card
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _maxVisiblePlaces,
                        itemBuilder: (context, idx) {
                          final place = places[idx];
                          final id = place['name']?.toString() ?? place['title']?.toString() ?? 'place-$idx';
                          return KeyedSubtree(
                            key: ValueKey(id),
                            child: _buildPlaceCard(place),
                          );
                        },
                      ),
                    )
                  else
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
          
          // ✅ PHASE 5: Use follow-up engine provider
          Builder(
            builder: (context) {
              final followUpsAsync = ref.watch(followUpEngineProvider(session));
              return followUpsAsync.when(
                data: (followUps) {
                  if (followUps.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            const SizedBox(height: 24),
                      ...followUps.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
                        return _buildFollowUpSuggestionItem(suggestion, index, session: session);
            }),
          ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
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
            renderCards('movies', movieCards, session: session)
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "No movies found",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          // ✅ PHASE 5: Use follow-up engine provider
          Builder(
            builder: (context) {
              final followUpsAsync = ref.watch(followUpEngineProvider(session));
              return followUpsAsync.when(
                data: (followUps) {
                  if (followUps.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            const SizedBox(height: 24),
                      ...followUps.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
                        return _buildFollowUpSuggestionItem(suggestion, index, session: session);
            }),
          ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
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

  // ✅ PRODUCTION: Cache map widgets to prevent recreation
  final Map<int, Widget> _mapWidgetCache = {};
  static const int _maxCacheSize = 5; // Limit cache size to prevent memory issues

  // 🗺️ Build hotel map (extract from hotel results if map points not provided)
  Widget? _buildHotelMap(QuerySession session, [int? cacheKey]) {
    // ✅ PRODUCTION: Return cached widget if available
    if (cacheKey != null && _mapWidgetCache.containsKey(cacheKey)) {
      return _mapWidgetCache[cacheKey];
    }
    // Try to get map points from session
    List<Map<String, dynamic>>? mapPoints = session.hotelMapPoints;
    
    // ✅ FIX: If no map points, generate them from hotel results
    if ((mapPoints == null || mapPoints.isEmpty) && session.hotelResults.isNotEmpty) {
      mapPoints = session.hotelResults.where((hotel) {
        final lat = hotel['latitude'] ?? hotel['geo']?['latitude'] ?? hotel['gps_coordinates']?['latitude'];
        final lng = hotel['longitude'] ?? hotel['geo']?['longitude'] ?? hotel['gps_coordinates']?['longitude'];
        return lat != null && lng != null;
      }).map((hotel) {
        final lat = hotel['latitude'] ?? hotel['geo']?['latitude'] ?? hotel['gps_coordinates']?['latitude'];
        final lng = hotel['longitude'] ?? hotel['geo']?['longitude'] ?? hotel['gps_coordinates']?['longitude'];
        return {
          'latitude': lat is num ? lat.toDouble() : double.tryParse(lat.toString()) ?? 0.0,
          'longitude': lng is num ? lng.toDouble() : double.tryParse(lng.toString()) ?? 0.0,
          'title': hotel['name']?.toString() ?? 'Hotel',
          'address': hotel['address']?.toString() ?? '',
        };
      }).toList();
    }
    
    if (mapPoints == null || mapPoints.isEmpty) {
      return null; // No map to show
    }
    
    // ✅ PRODUCTION: Wrap map in RepaintBoundary and use ValueKey to prevent unnecessary rebuilds
    final mapWidget = RepaintBoundary(
      key: ValueKey('map-${mapPoints.length}-${mapPoints.isNotEmpty ? mapPoints.first['latitude'] : 0}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FullScreenMapScreen(
                  points: mapPoints!,
                  title: widget.query,
                ),
              ),
            );
          },
          child: Stack(
            children: [
              HotelMapView(
                key: ValueKey('hotel-map-view-${mapPoints.length}'), // ✅ PRODUCTION: Key prevents rebuild when points don't change
                points: mapPoints,
                height: MediaQuery.of(context).size.height * 0.65,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapScreen(
                        points: mapPoints!,
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
    );
    
    // ✅ PRODUCTION: Cache the widget if cache key provided
    if (cacheKey != null) {
      // ✅ PRODUCTION: Limit cache size to prevent memory issues
      if (_mapWidgetCache.length >= _maxCacheSize) {
        // Remove oldest entry (simple FIFO)
        final firstKey = _mapWidgetCache.keys.first;
        _mapWidgetCache.remove(firstKey);
      }
      _mapWidgetCache[cacheKey] = mapWidget;
    }
    
    return mapWidget;
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
          final sessions = ref.read(sessionHistoryProvider);
          for (final s in sessions) {
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
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                  placeholder: (context, url) => Container(
                    width: 60,
                    height: 60,
                    color: AppColors.surfaceVariant,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) {
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
      child: StreamingTextWidget(
        targetText: summary,
        enableAnimation: false, // ✅ PRODUCTION: Disabled to prevent frame skips
        style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: AppColors.textPrimary,
            ),
      ),
    );
  }

  Widget _buildTag(String text) {
    return GestureDetector(
      onTap: () {
        if (text == 'Shopping') {
          // Navigate to ShoppingGridScreen with all products from all sessions
          final allProducts = <Product>[];
          final sessions = ref.read(sessionHistoryProvider);
          for (final session in sessions) {
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
  Widget renderCards(String intent, List<dynamic> cards, {QuerySession? session}) {
    // ✅ C5: Safe list handling
    final safeCards = cards.isNotEmpty ? cards : <dynamic>[];
    
    switch (intent) {
      case "shopping":
        final products = safeCards.map<Product>((item) {
          try {
            return _mapShoppingResultToProduct(item);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error mapping product: $e');
            }
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
            // ✅ PRODUCTION FIX: Use ListView.builder for large product lists
            Builder(
              builder: (context) {
                final visibleProducts = products.take(_maxVisibleProducts).toList();
                return Column(
                  children: [
                    ...visibleProducts.map((p) {
                      final id = p.id.toString();
                      return KeyedSubtree(
                        key: ValueKey(id),
                        child: _buildProductCard(p),
                      );
                    }),
                    if (products.length > visibleProducts.length)
                      _buildViewAllProductsButton(products),
                  ],
                );
              },
            ),
          ],
        );

      case "hotels":
      case "hotel":
        final hotelResults = safeCards
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return _buildHotelResultsList(QuerySession(
          query: session?.query ?? "",
          results: hotelResults,
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
        // ✅ BUCKET 3: Use provider-based content instead of _processedResult
        // Since this is in a build method context, we'll use safeCards directly
        // The displayContentProvider is used at a higher level in _buildQuerySession
        final places = safeCards
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
            Builder(

              builder: (context) {

                final placesList = places as List;

                final visiblePlaces = placesList.take(_maxVisiblePlaces).toList();

                return Column(

                  children: [

                    ...visiblePlaces.map((p) {

                      final id = p['name']?.toString() ?? p['title']?.toString() ?? UniqueKey().toString();

                      return KeyedSubtree(

                        key: ValueKey(id),

                        child: _buildPlaceCard(p),

                      );

                    }).toList(),

                    if (placesList.length > visiblePlaces.length)

                      _buildResultsNote('+${placesList.length - visiblePlaces.length} more locations'),

                  ],

                );

              },

            ),

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
            Builder(

              builder: (context) {

                final visibleMovies = movieResults.take(_maxVisibleMovies).toList();

                return Column(

                  children: [

                    ...visibleMovies.map((m) => KeyedSubtree(

                      key: ValueKey(m['id']?.toString() ?? UniqueKey().toString()),

                      child: _buildMovieCard(m),

                    )).toList(),

                    if (movieResults.length > visibleMovies.length)

                      _buildResultsNote('+${movieResults.length - visibleMovies.length} more movies'),

                  ],

                );

              },

            ),

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
    final visibleProducts = session.products.take(_maxVisibleProducts).toList();
    return Column(
      children: [
        ...visibleProducts.map(
          (product) => Container(
            color: Colors.grey.shade50,
            child: _buildProductCard(product),
          ),
        ),
        if (session.products.length > visibleProducts.length)
          _buildViewAllProductsButton(session.products),
      ],
    );
  }

  Widget _buildHotelResultsList(QuerySession session) {

    final visibleHotels = session.hotelResults.take(_maxVisibleHotelsPerSection).toList();

    return Column(

      children: [

        ...visibleHotels.asMap().entries.map(

          (entry) => Column(

            children: [

              KeyedSubtree(

                key: ValueKey(entry.value['id']?.toString() ?? entry.value['name']?.toString() ?? 'hotel-${entry.key}'),

                child: _buildHotelCard(entry.value),

              ),

              if (entry.key < visibleHotels.length - 1) const SizedBox(height: 20),

            ],

          ),

        ),

        if (session.hotelResults.length > visibleHotels.length)

          _buildViewAllHotelsButton(

            session.query,

            hiddenCount: session.hotelResults.length - visibleHotels.length,

          ),

      ],

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

    // Debug: Log image count (removed from build method)
    // Image URLs logging removed to avoid performance issues

    return RepaintBoundary(
      child: GestureDetector(
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
          
          // 🔹 Description - Use product's own description, not session summary
          if (product.description.trim().isNotEmpty)
            Text(
              product.description,
              style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary, // Light grey for dark theme
                    height: 1.5,
                  ),
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
      ),
    );
  }

  Widget _buildImage(String url, {double height = 180}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
        // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
        placeholder: (context, url) => Container(
            height: height,
            width: double.infinity,
            alignment: Alignment.center,
            color: Colors.grey.shade200,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
        ),
        errorWidget: (context, url, error) => _buildNoImagePlaceholder(height: height),
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
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
        // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
        placeholder: (context, url) => Container(
            color: Colors.grey.shade200,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
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
          onTap: () {
            if (session != null) {
              _onFollowUpQuerySelected(suggestion, session);
            }
          },
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

  // ✅ PHASE 5: Handle follow-up click using follow-up controller
  void _onFollowUpQuerySelected(String query, QuerySession parentSession) {
    ref.read(followUpControllerProvider.notifier).handleFollowUp(query, parentSession);
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
            // ✅ FIX: Use hotel's own description, not session summary
            // Always show Perplexity-style summary
            // ✅ STEP 1 & 2: Use compute() with caching
              Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Add horizontal padding
              child: FutureBuilder<String>(
                future: _getHotelSummary(safeHotel),
                builder: (context, snapshot) {
                  final summary = snapshot.data ?? 'A modern property offering comfortable accommodations.';
                  // ✅ FIX: Use hotel's own description, not streamingTextProvider (which contains session summary)
                  return Text(
                    summary,
                    style: TextStyle(
                      fontSize: 14, // Smaller, more compact text
                      color: AppColors.textPrimary.withOpacity(0.8), // Brighter for better visibility
                      height: 1.4, // Tighter line spacing
                      fontWeight: FontWeight.w400,
                    ),
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
        // ✅ FIX 4: Guard PageView creation - if only 1 image, return single image widget
        child: pageCount < 2
            ? (imageList.isNotEmpty
                ? GestureDetector(
                    onTap: () => _navigateToHotelDetail(hotel),
                    child: Container(
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.surfaceVariant,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: imageList[0],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink())
            : PageView.builder(
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
    // ✅ PHASE 4B: Removed compute() - summary generation moved to provider
    // final summary = await compute(generateSummaryIsolate, hotel);
    final summary = _generatePerplexityStyleSummary(hotel); // Use direct method instead
    
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

  // ✅ PHASE 6: Removed _buildAnswerWithInlineLocationCards and _buildAnswerFromParsedContent
  // Now using unified displayContentProvider
  
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
          // ✅ FIX 4: Guard PageView creation - if < 2 images, return single image
          child: images.length < 2
              ? (images.isNotEmpty
                  ? GestureDetector(
                      onTap: () => _viewImagesFullscreen(images, 0),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: images[0],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink())
              : PageView.builder(
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
    
    // ✅ FIX 4: Guard PageView creation - if < 2 images, return single image
    if (imagesToShow.length < 2) {
      if (imagesToShow.isEmpty || imagesToShow[0].isEmpty) {
        return Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: imagesToShow[0],
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
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
          ),
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
              if (kDebugMode) {
                debugPrint('❌ Image load error for $placeName: $error');
              }
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
    
    // Debug logging removed - avoid logging in build method
    
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
      // ✅ PRODUCTION FIX: Removed debug print from build() method to prevent UI blocking
      // This was causing hundreds of prints during widget rendering, freezing the app
    }
    
    // Add images from photos array (alternative source)
    if (place['photos'] != null && place['photos'] is List) {
      for (var photo in place['photos']) {
        final photoStr = photo?.toString() ?? '';
        if (photoStr.isNotEmpty && photoStr.startsWith('http') && !allImages.contains(photoStr)) {
          allImages.add(photoStr);
        }
      }
      // Removed print from loop
    }
    
    // Add primary image (always include it, even if we have images array)
    final imageUrl = place['image_url']?.toString() ?? place['image']?.toString() ?? place['thumbnail']?.toString() ?? '';
    if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
      if (!allImages.contains(imageUrl)) {
        // Add as first image if it's not already in the list
        allImages.insert(0, imageUrl);
      }
    }
    
    // Removed print loop - avoid printing multiple image URLs
    
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
          
          // ✅ FIX: Full description (Perplexity-style, no truncation) - show place's own description, not session summary
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    height: 1.6, // Better line spacing for readability
                  ),
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
                  ? CachedNetworkImage(
                      imageUrl: image,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                      placeholder: (context, url) => Container(
                        height: 200,
                        color: AppColors.surfaceVariant,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
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
                            child: CachedNetworkImage(
                              imageUrl: mainImage,
                              fit: BoxFit.cover, // Fill entire card without empty space (like Perplexity)
                              // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
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
                ? StreamingTextWidget(
                    targetText: description,
                    enableAnimation: false, // ✅ PRODUCTION: Disabled to prevent frame skips
                    style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: AppColors.textPrimary,
                        ),
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
                // ✅ FIX 5: Use ValueNotifier instead of Timer (prevents rebuilds)
                onChanged: (value) {
                  _followUpTextNotifier.value = value;
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
                child: CachedNetworkImage(
                  imageUrl: product.images[0],
                  fit: BoxFit.cover,
                  // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                  placeholder: (context, url) => Container(
                      color: AppColors.surfaceVariant,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                        ),
                      ),
                  ),
                  errorWidget: (context, url, error) {
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
                      child: CachedNetworkImage(
                        imageUrl: product.images[1],
                        fit: BoxFit.cover,
                        // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                        placeholder: (context, url) => Container(
                            color: AppColors.surfaceVariant,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.accent,
                                ),
                              ),
                            ),
                        ),
                        errorWidget: (context, url, error) {
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

  // ✅ BUCKET 1: Build methods for unified content display
  Widget _buildSummary(String summary) {
    if (summary.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Text(
        summary,
        style: const TextStyle(fontSize: 16, height: 1.45),
      ),
    );
  }

  Widget _buildImageSection(List<String> images, String query) {
    if (images.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 160,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: images.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: images[index],
                width: 160,
                height: 160,
                fit: BoxFit.cover,
                // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                placeholder: (context, url) => Container(
                  width: 160,
                  height: 160,
                  color: Colors.grey.shade200,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 160,
                  height: 160,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLocationSection(List<Map<String, dynamic>> locations) {
    if (locations.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: locations.map((loc) {
          final title = loc['title']?.toString() ?? loc['name']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Text("📍 $title", style: const TextStyle(fontSize: 16)),
          );
        }).toList(),
      ),
    );
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
              child: CachedNetworkImage(
                imageUrl: widget.images[index],
                fit: BoxFit.contain,
                // ✅ PRODUCTION: CachedNetworkImage caches to disk, persists across scrolls/navigation
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) {
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

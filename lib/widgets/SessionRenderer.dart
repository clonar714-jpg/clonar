import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/query_session_model.dart';
import '../models/Product.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../providers/follow_up_engine_provider.dart';
import '../widgets/StreamingTextWidget.dart';
import '../widgets/HotelMapView.dart';
import '../screens/FullScreenMapScreen.dart';
import '../screens/HotelResultsScreen.dart';
import '../screens/ShoppingGridScreen.dart';
import '../screens/MovieDetailScreen.dart';
import '../services/AgentService.dart';

class SessionRenderModel {
  final QuerySession session;
  final int index;
  final BuildContext context;
  final Function(String, QuerySession) onFollowUpTap;
  final Function(Map<String, dynamic>) onHotelTap;
  final Function(Product) onProductTap;
  final Function(String) onViewAllHotels;
  final Function(String) onViewAllProducts;
  final String? query;
  
  SessionRenderModel({
    required this.session,
    required this.index,
    required this.context,
    required this.onFollowUpTap,
    required this.onHotelTap,
    required this.onProductTap,
    required this.onViewAllHotels,
    required this.onViewAllProducts,
    this.query,
  });
}

class SessionRenderer extends StatelessWidget {
  final SessionRenderModel model;
  
  const SessionRenderer({super.key, required this.model});
  
  @override
  Widget build(BuildContext context) {
    return _SessionContentRenderer(model: model);
  }
}

class _SessionContentRenderer extends ConsumerWidget {
  final SessionRenderModel model;
  
  const _SessionContentRenderer({required this.model});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = model.session;
    
    return Padding(
      key: ValueKey('session-${model.index}'),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ FIX 3: Add horizontal padding to query text (16px like description/images)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              session.query,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          
          // ✅ FIX: Show loading indicator ONLY when there's no data
          // ROOT CAUSE FIX: Don't check isStreaming/isParsing flags - they may not flip correctly
          // Data presence is the only reliable signal
          Builder(
            builder: (context) {
              final hasSummary = session.summary != null && session.summary!.isNotEmpty;
              final hasCards = session.cards.isNotEmpty;
              final hasLocationCards = session.locationCards.isNotEmpty;
              final hasRawResults = session.rawResults.isNotEmpty;
              final hasHotelSections = session.hotelSections != null && session.hotelSections!.isNotEmpty;
              final hasHotelResults = session.hotelResults.isNotEmpty;
              
              final hasNoData = !hasSummary && 
                               !hasCards && 
                               !hasLocationCards && 
                               !hasRawResults && 
                               !hasHotelSections && 
                               !hasHotelResults;
              
              // ✅ ROOT CAUSE FIX: Loading depends ONLY on data presence, not flags
              final isLoading = hasNoData;
              
              // ✅ FIX: Log loading state for debugging
              if (isLoading) {
                print("⏳ LOADING STATE - Query: '${session.query}'");
                print("  - hasSummary: $hasSummary");
                print("  - hasCards: $hasCards (${session.cards.length})");
                print("  - hasLocationCards: $hasLocationCards (${session.locationCards.length})");
                print("  - hasRawResults: $hasRawResults (${session.rawResults.length})");
                print("  - hasHotelSections: $hasHotelSections (${session.hotelSections?.length ?? 0})");
                print("  - hasHotelResults: $hasHotelResults (${session.hotelResults.length})");
                print("  - hasNoData: $hasNoData");
                print("  - isLoading: $isLoading (based on data only, not flags)");
              } else {
                print("✅ NOT LOADING - Query: '${session.query}' - Data present, rendering content");
                print("  - hasSummary: $hasSummary");
                print("  - hasCards: $hasCards (${session.cards.length})");
                print("  - hasLocationCards: $hasLocationCards (${session.locationCards.length})");
                print("  - Will render content now");
              }
              
              if (isLoading) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Searching...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTags(context, session, ref),
                  // ✅ FIX: Add spacing between tags and content (16px for movies, hotels)
                  if (session.resultType == 'movies' || session.resultType == 'hotel' || session.resultType == 'hotels')
                    const SizedBox(height: 16),
                  // ✅ FIX 2: Add spacing between tags and map for hotels
                  if (session.resultType == 'hotel' || session.resultType == 'hotels')
                    ...(_buildHotelMap(session) != null ? [_buildHotelMap(session)!] : []),
                  // ✅ For movies: Show summary AFTER cards, not before
                  if (session.resultType != 'movies')
                    if (session.summary != null && session.summary!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Overview',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            StreamingTextWidget(
                              targetText: session.summary ?? "",
                              enableAnimation: false,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textPrimary,
                                height: 1.65, // ✅ Perplexity: Slightly more line spacing for readability
                                letterSpacing: -0.1, // ✅ Perplexity: Tighter letter spacing
                                fontWeight: FontWeight.w400, // ✅ Perplexity: Normal weight (not bold)
                              ),
                            ),
                          ],
                        ),
                      ),
                  _buildIntentBasedContent(context, session, ref),
                  // ✅ For movies: Show Core Details and Box Office sections ONLY for specific queries (1 movie)
                  // For general queries (multiple movies), these sections are not shown in SessionRenderer
                  if (session.resultType == 'movies' && session.cards.length == 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _MovieDetailsSections(movies: session.cards),
                    ),
                  if ((session.resultType == 'places' || session.resultType == 'location' || session.resultType == 'movies' || session.resultType == 'shopping'))
                    _buildFollowUps(session, ref),
                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTags(BuildContext context, QuerySession session, WidgetRef ref) {
    final tags = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
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
      _buildIntentTag(session.resultType, session, ref),
    ];
    
    // ✅ FIX: Add "Paid Experiences" tag for ALL places queries (future: will show Expedia/affiliate API results)
    if (session.resultType == 'places' || session.resultType == 'location') {
      tags.add(_buildPaidExperienceTag());
    }
    
    // ✅ FIX: Add movie-specific tags (Showtimes, Cast & Crew, Trailers, Reviews)
    if (session.resultType == 'movies' && session.cards.isNotEmpty) {
      tags.addAll(_buildMovieTags(context, session, ref));
    }
    
    // ✅ FIX 3: Add horizontal padding to tags (16px like description/images)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags,
      ),
    );
  }
  
  // ✅ FIX: Build "Paid Experiences" tag (always shown for places queries)
  Widget _buildPaidExperienceTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_activity, size: 14, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          const Text(
            'Paid Experiences',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildIntentTag(String intent, QuerySession session, WidgetRef ref) {
    IconData icon;
    String label;
    
    switch (intent) {
      case 'shopping':
        icon = Icons.shopping_bag;
        label = 'Shopping';
        break;
      case 'hotel':
      case 'hotels':
        icon = Icons.hotel;
        label = 'Hotels';
        break;
      case 'places':
      case 'location':
        icon = Icons.location_on;
        label = 'Places';
        break;
      case 'movies':
        icon = Icons.movie;
        label = 'Movies';
        break;
      default:
        icon = Icons.search;
        label = 'Search';
    }
    
    // ✅ FIX: Add click navigation to tags (Hotels/Shopping)
    return GestureDetector(
      onTap: () {
        if (intent == 'hotel' || intent == 'hotels') {
          // Navigate to HotelResultsScreen
          Navigator.push(
            model.context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: session.query),
            ),
          );
        } else if (intent == 'shopping') {
          // ✅ FIX: Each session is isolated - only show products from THIS specific query
          // Example: "new balance shoes" query → only new balance shoes
          //          "nike running shoes" query → only nike shoes (not new balance + nike)
          // Each QuerySession has its own cards array, so session.products only contains
          // products from this specific query, not from other queries in the conversation
          final sessionProducts = session.products;
          if (sessionProducts.isNotEmpty) {
            Navigator.push(
              model.context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: sessionProducts),
              ),
            );
          } else {
            ScaffoldMessenger.of(model.context).showSnackBar(
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
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget? _buildHotelMap(QuerySession session) {
    List<Map<String, dynamic>>? mapPoints = session.hotelMapPoints;
    
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
      return null;
    }
    
    final hotelDataHash = '${session.hotelResults.length}-${mapPoints.length}'.hashCode;
    
    return RepaintBoundary(
      key: ValueKey('hotel-map-$hotelDataHash'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: () {
            Navigator.of(model.context).push(
              MaterialPageRoute(
                builder: (context) => FullScreenMapScreen(
                  points: mapPoints!,
                  title: session.query,
                ),
              ),
            );
          },
          child: Stack(
            children: [
              HotelMapView(
                key: ValueKey('hotel-map-view-${mapPoints.length}'),
                points: mapPoints,
                height: MediaQuery.of(model.context).size.height * 0.65,
                onTap: () {
                  Navigator.of(model.context).push(
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapScreen(
                        points: mapPoints!,
                        title: session.query,
                      ),
                    ),
                  );
                },
              ),
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
  }
  
  Widget _buildIntentBasedContent(BuildContext context, QuerySession session, WidgetRef ref) {
    final intent = session.resultType;
    
    if (intent == 'shopping' && session.products.isNotEmpty) {
      return _buildShoppingContent(session);
    } else if (intent == 'hotel' || intent == 'hotels') {
      // ✅ FIX 4: Relax empty-guard logic - check hotelSections first, then hotelResults
      // Temporarily removed isEmpty checks to see if backend data is being filtered out
      if (session.hotelSections != null && session.hotelSections!.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('🏨 Rendering hotel sections: ${session.hotelSections!.length} sections');
        }
        return _buildHotelSectionsContent(session, ref);
      } else if (session.hotelResults.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('🏨 Rendering hotel results: ${session.hotelResults.length} hotels');
        }
        return _buildHotelContent(session, ref);
      } else {
        // ✅ FIX 4: Even if empty, log to see what's happening
        if (kDebugMode) {
          debugPrint('⚠️ Hotel intent but no data:');
          debugPrint('  - hotelSections: ${session.hotelSections?.length ?? 0}');
          debugPrint('  - hotelResults: ${session.hotelResults.length}');
          debugPrint('  - sections field: ${session.sections?.length ?? 0}');
          debugPrint('  - cards: ${session.cards.length}');
          debugPrint('  - results: ${session.results.length}');
        }
      }
    } else if ((intent == 'places' || intent == 'location')) {
      // ✅ FIX 4: Relaxed - removed isEmpty check temporarily
      return _buildPlacesContent(session, ref);
    } else if (intent == 'movies') {
      // ✅ FIX 4: Relaxed - removed isEmpty check temporarily
      return _buildMoviesContent(context, session, ref);
    }
    
    return const SizedBox.shrink();
  }
  
  Widget _buildShoppingContent(QuerySession session) {
    const maxVisible = 12;
    final visibleProducts = session.products.take(maxVisible).toList();
    
    return Column(
      children: [
        ...visibleProducts.map((product) => RepaintBoundary(
          key: ValueKey('product-${product.id}'),
          child: _buildProductCard(product),
        )),
        if (session.products.length > visibleProducts.length)
          _buildViewAllProductsButton(session.products),
      ],
    );
  }
  
  Widget _buildHotelSectionsContent(QuerySession session, WidgetRef ref) {
    // ✅ FIX: Render hotel sections (grouped structure from backend)
    final sections = session.hotelSections;
    if (sections == null || sections.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ SessionRenderer: hotelSections is null or empty for query: "${session.query}"');
        debugPrint('  - session.sections: ${session.sections?.length ?? 0}');
        debugPrint('  - session.hotelResults: ${session.hotelResults.length}');
      }
      return const SizedBox.shrink();
    }
    
    const maxVisiblePerSection = 5;
    
    if (kDebugMode) {
      debugPrint('🏨 SessionRenderer: Rendering ${sections.length} hotel sections for query: "${session.query}"');
      for (int i = 0; i < sections.length; i++) {
        final section = sections[i];
        final title = section['title']?.toString() ?? 'Unknown';
        final items = (section['items'] as List?)?.length ?? 0;
        debugPrint('  Section $i: "$title" with $items items');
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...sections.map((section) {
          final title = section['title']?.toString() ?? 'Hotels';
          final items = (section['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          
          // ✅ FIX 4: Relaxed empty check - log but still try to render
          if (items.isEmpty) {
            print("⚠️ Section '$title' has no items - skipping");
            return const SizedBox.shrink();
          }
          
          print("✅ Rendering section '$title' with ${items.length} items");
          final itemsToShow = items.take(maxVisiblePerSection).toList();
          final hiddenCount = items.length - itemsToShow.length;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              // Hotel cards in this section
              ...itemsToShow.map((hotel) => RepaintBoundary(
                key: ValueKey('hotel-${hotel['id'] ?? hotel['name'] ?? hotel.hashCode}'),
                child: _buildHotelCard(hotel),
              )),
              // View all button if there are more hotels
              if (hiddenCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildViewAllHotelsButton(session.query),
                ),
              const SizedBox(height: 24),
            ],
          );
        }),
        _buildFollowUps(session, ref),
      ],
    );
  }

  Widget _buildHotelContent(QuerySession session, WidgetRef ref) {
    // ✅ FALLBACK: Old flat list view (for backward compatibility)
    const maxVisible = 8;
    final visibleHotels = session.hotelResults.take(maxVisible).toList();
    
    return Column(
      children: [
        ...visibleHotels.map((hotel) => RepaintBoundary(
          key: ValueKey('hotel-${hotel['id'] ?? hotel['name']}'),
          child: _buildHotelCard(hotel),
        )),
        if (session.hotelResults.length > visibleHotels.length)
          _buildViewAllHotelsButton(session.query),
        _buildFollowUps(session, ref),
      ],
    );
  }
  
  Widget _buildPlacesContent(QuerySession session, WidgetRef ref) {
    const maxVisible = 8;
    final places = session.cards.take(maxVisible).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...places.map((place) => RepaintBoundary(
          key: ValueKey('place-${place['name'] ?? place['title']}'),
          child: _buildPlaceCard(place),
        )),
        if (session.cards.length > places.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+${session.cards.length - places.length} more locations',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildMoviesContent(BuildContext context, QuerySession session, WidgetRef ref) {
    // Show all movies (no limit)
    final movies = session.cards;
    final totalMovies = movies.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...movies.map((movie) => RepaintBoundary(
          key: ValueKey('movie-${movie['id']}'),
          child: _buildMovieCard(context, movie, totalMovies),
        )),
      ],
    );
  }
  
  Widget _buildProductCard(Product product) {
    final validImages = product.images.where((img) => img.trim().isNotEmpty).toList();
    final hasImage = validImages.isNotEmpty;
    
    return GestureDetector(
      onTap: () => model.onProductTap(product),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            if (product.rating > 0)
              Row(
                children: [
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
                ],
              ),
            if (product.rating > 0) const SizedBox(height: 8),
            if (product.price > 0)
              Text(
                "\$${product.price.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            if (product.price > 0) const SizedBox(height: 12),
            if (hasImage)
              SizedBox(
                width: 160,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: validImages[0],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            if (hasImage) const SizedBox(height: 12),
            Text(
              product.description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHotelCard(Map<String, dynamic> hotel) {
    return _HotelCardWidget(hotel: hotel, onTap: () => model.onHotelTap(hotel));
  }
  
  // Build movie card with navigation
  Widget _buildMovieCard(BuildContext context, Map<String, dynamic> movie, int totalMovies) {
    final title = movie['title']?.toString() ?? 'Unknown Movie';
    // Extract rating - handle both string format "7.5/10" and number format
    final ratingValue = movie['rating'];
    String rating = '';
    if (ratingValue != null) {
      if (ratingValue is String && ratingValue.isNotEmpty && ratingValue != 'null') {
        rating = ratingValue;
      } else if (ratingValue is num && ratingValue > 0) {
        rating = '${ratingValue.toStringAsFixed(1)}/10';
      } else if (ratingValue.toString().isNotEmpty && ratingValue.toString() != 'null') {
        rating = ratingValue.toString();
      }
    }
    final image = movie['poster']?.toString() ?? movie['image']?.toString() ?? '';
    final releaseDate = movie['releaseDate']?.toString() ?? '';
    final description = movie['description']?.toString() ?? '';
    final movieId = movie['id'] as int? ?? 0;
    
    // Extract multiple images if available
    final List<String> images = [];
    // Check for images array first (new format with multiple images)
    if (movie['images'] != null) {
      if (movie['images'] is List) {
        for (var img in movie['images'] as List) {
          final imgUrl = img.toString();
          if (imgUrl.isNotEmpty && !images.contains(imgUrl)) {
            images.add(imgUrl);
          }
        }
      }
    }
    // Fallback to single image if no images array
    if (images.isEmpty && image.isNotEmpty) {
      images.add(image);
    }
    
    return GestureDetector(
      onTap: () {
        if (movieId > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => MovieDetailScreen(
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
            // Movie poster(s) - horizontal scrolling if multiple
            if (images.isNotEmpty)
              images.length == 1
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: images[0],
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 200,
                          color: AppColors.surfaceVariant,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 200,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : _MoviePosterCarousel(images: images),
            // ✅ TMDB Rating after poster
            if (rating.isNotEmpty && rating != 'null') ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 18, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      rating,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TMDB',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
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
                  // ✅ For general queries (multiple movies): Show plot/description
                  // For specific queries (1 movie), plot is shown in Core Details as "Storyline"
                  if (description.isNotEmpty && totalMovies > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Movie poster carousel widget (for multiple images)
  Widget _MoviePosterCarousel({required List<String> images}) {
    return _MoviePosterCarouselWidget(images: images);
  }
  
  // Build movie-specific tags (Showtimes, Cast & Crew, Trailers, Reviews)
  List<Widget> _buildMovieTags(BuildContext context, QuerySession session, WidgetRef ref) {
    if (session.cards.isEmpty) return [];
    
    final firstMovie = session.cards[0];
    final movieId = firstMovie['id'] as int? ?? 0;
    final movieTitle = firstMovie['title']?.toString();
    final isInTheaters = firstMovie['isInTheaters'] == true;
    
    final tags = <Widget>[];
    
    // Showtimes tag - only show if movie is currently in theaters
    if (isInTheaters && movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 2, // Showtimes tab
                  isInTheaters: isInTheaters, // Pass isInTheaters flag to ensure Showtimes tab is visible
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
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
      );
    }
    
    // Cast & Crew tag
    if (movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 1, // Cast tab
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
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
      );
    }
    
    // Trailers & Clips tag
    if (movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 3, // Trailers tab
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
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
      );
    }
    
    // Reviews tag
    if (movieId > 0) {
      tags.add(
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MovieDetailScreen(
                  movieId: movieId,
                  movieTitle: movieTitle,
                  initialTabIndex: 4, // Reviews tab
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline, size: 14, color: AppColors.textPrimary),
                SizedBox(width: 4),
                Text(
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
      );
    }
    
    return tags;
  }
  
  Future<void> _openHotelWebsite(BuildContext context, Map<String, dynamic> hotel) async {
    final link = hotel['link']?.toString() ?? hotel['website']?.toString() ?? hotel['url']?.toString() ?? '';
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Website not available')),
      );
      return;
    }
    
    try {
      final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open website')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening website: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening website')),
      );
    }
  }
  
  Future<void> _callHotel(BuildContext context, Map<String, dynamic> hotel) async {
    final phone = hotel['phone']?.toString() ?? hotel['phone_number']?.toString() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available')),
      );
      return;
    }
    
    try {
      // Clean phone number (remove spaces, dashes, etc.)
      final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      final uri = Uri.parse('tel:$cleanPhone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot make phone call')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling hotel: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error making phone call')),
      );
    }
  }
  
  Future<void> _openHotelDirections(BuildContext context, Map<String, dynamic> hotel) async {
    final address = hotel['address']?.toString() ?? hotel['location']?.toString() ?? '';
    final lat = hotel['latitude'] ?? hotel['lat'];
    final lng = hotel['longitude'] ?? hotel['lng'];
    
    Uri? mapsUri;
    
    // Prefer coordinates if available
    if (lat != null && lng != null) {
      final latValue = lat is double ? lat : double.tryParse(lat.toString()) ?? 0.0;
      final lngValue = lng is double ? lng : double.tryParse(lng.toString()) ?? 0.0;
      if (latValue != 0.0 && lngValue != 0.0) {
        mapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latValue,$lngValue');
      }
    }
    
    // Fallback to address if no coordinates
    if (mapsUri == null && address.isNotEmpty) {
      mapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    }
    
    if (mapsUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }
    
    try {
      if (await canLaunchUrl(mapsUri)) {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open directions')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening directions: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening directions')),
      );
    }
  }
  
  Widget _buildHotelActionButton(String label, IconData icon, VoidCallback onTap, {required bool enabled}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceVariant : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? AppColors.accent.withOpacity(0.3) : Colors.grey.shade400,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: enabled ? AppColors.accent : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? AppColors.textPrimary : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPlaceCard(Map<String, dynamic> place) {
    return _PlaceCardWidget(place: place);
  }
  
  Widget _buildViewAllHotelsButton(String query) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: AppColors.primary,
        ),
        onPressed: () => model.onViewAllHotels(query),
        icon: const Icon(Icons.travel_explore, size: 16, color: AppColors.primary),
        label: const Text(
          'View full hotel list',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
  
  Widget _buildViewAllProductsButton(List<Product> products) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: AppColors.primary,
        ),
        onPressed: () => model.onViewAllProducts(model.session.query),
        icon: const Icon(Icons.shopping_bag, size: 16, color: AppColors.primary),
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
  
  Widget _buildFollowUps(QuerySession session, WidgetRef ref) {
    final followUpsAsync = ref.watch(followUpEngineProvider(session));
    
    return followUpsAsync.when(
      data: (followUps) {
        if (followUps.isEmpty) return const SizedBox.shrink();
        final limited = followUps.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            ...limited.asMap().entries.map((entry) {
              return _buildFollowUpItem(entry.value, entry.key, session);
            }),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
  
  Widget _buildFollowUpItem(String suggestion, int index, QuerySession session) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => model.onFollowUpTap(suggestion, session),
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.accent.withOpacity(0.2),
          highlightColor: AppColors.accent.withOpacity(0.1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    suggestion,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ FIX 1: StatefulWidget for HotelCard to manage PageController
class _HotelCardWidget extends StatefulWidget {
  final Map<String, dynamic> hotel;
  final VoidCallback onTap;
  
  const _HotelCardWidget({required this.hotel, required this.onTap});
  
  @override
  State<_HotelCardWidget> createState() => _HotelCardWidgetState();
}

class _HotelCardWidgetState extends State<_HotelCardWidget> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  
  @override
  void initState() {
    super.initState();
    final images = _extractImages(widget.hotel);
    if (images.length > 1) {
      _pageController = PageController();
      _pageController.addListener(_onPageChanged);
    }
  }
  
  @override
  void dispose() {
    final images = _extractImages(widget.hotel);
    if (images.length > 1) {
      _pageController.removeListener(_onPageChanged);
      _pageController.dispose();
    }
    super.dispose();
  }
  
  void _onPageChanged() {
    if (_pageController.hasClients) {
      final newIndex = _pageController.page?.round() ?? 0;
      if (newIndex != _currentPageIndex) {
        setState(() {
          _currentPageIndex = newIndex;
        });
      }
    }
  }
  
  List<String> _extractImages(Map<String, dynamic> hotel) {
    final List<String> images = [];
    final imagesData = hotel['images'];
    if (imagesData != null) {
      if (imagesData is List) {
        for (final img in imagesData) {
          if (img is String && img.isNotEmpty) {
            images.add(img);
          } else if (img is Map) {
            final thumbnail = img['thumbnail']?.toString();
            final original = img['original_image']?.toString();
            final image = img['image']?.toString();
            final url = img['url']?.toString();
            final urlToAdd = thumbnail ?? original ?? image ?? url;
            if (urlToAdd != null && urlToAdd.isNotEmpty) {
              images.add(urlToAdd);
            }
          }
        }
      } else if (imagesData is String && imagesData.isNotEmpty) {
        images.add(imagesData);
      }
    }
    if (images.isEmpty) {
      final thumbnail = hotel['thumbnail']?.toString();
      if (thumbnail != null && thumbnail.isNotEmpty) {
        images.add(thumbnail);
      }
    }
    return images;
  }
  
  double _safeNumber(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }
  
  bool _hasHotelWebsite(Map<String, dynamic> hotel) {
    return (hotel['website']?.toString() ?? hotel['url']?.toString() ?? '').isNotEmpty;
  }
  
  bool _hasHotelPhone(Map<String, dynamic> hotel) {
    return (hotel['phone']?.toString() ?? hotel['phone_number']?.toString() ?? '').isNotEmpty;
  }
  
  bool _hasHotelLocation(Map<String, dynamic> hotel) {
    final lat = hotel['latitude'] ?? hotel['lat'] ?? hotel['gps_coordinates']?['latitude'];
    final lng = hotel['longitude'] ?? hotel['lng'] ?? hotel['gps_coordinates']?['longitude'];
    return lat != null && lng != null;
  }
  
  void _openHotelWebsite(Map<String, dynamic> hotel) async {
    final url = hotel['website']?.toString() ?? hotel['url']?.toString();
    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
  
  void _callHotel(Map<String, dynamic> hotel) async {
    final phone = hotel['phone']?.toString() ?? hotel['phone_number']?.toString();
    if (phone != null && phone.isNotEmpty) {
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }
  
  void _openHotelDirections(Map<String, dynamic> hotel) async {
    final lat = hotel['latitude'] ?? hotel['lat'] ?? hotel['gps_coordinates']?['latitude'];
    final lng = hotel['longitude'] ?? hotel['lng'] ?? hotel['gps_coordinates']?['longitude'];
    if (lat != null && lng != null) {
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
  
  Widget _buildHotelActionButton(String label, IconData icon, VoidCallback onPressed, {required bool enabled}) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? AppColors.primary : Colors.grey.shade300,
        foregroundColor: enabled ? Colors.white : Colors.grey.shade600,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final name = widget.hotel['name']?.toString() ?? 'Unknown Hotel';
    final rating = _safeNumber(widget.hotel['rating'], 0.0);
    final price = _safeNumber(widget.hotel['price'], 0.0);
    final description = widget.hotel['description']?.toString() ?? widget.hotel['summary']?.toString() ?? '';
    final images = _extractImages(widget.hotel);
    
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppTypography.title1.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (rating > 0) ...[
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    rating.toStringAsFixed(1),
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                if (price > 0)
                  Text(
                    '\$${price.toStringAsFixed(0)}',
                    style: AppTypography.title1.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: images.length == 1
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: images[0],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported, color: Colors.grey),
                          ),
                        ),
                      )
                    : PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(right: index < images.length - 1 ? 8 : 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: images[index],
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // ✅ FIX 1: Image indicator dots update based on current page
              if (images.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == _currentPageIndex ? AppColors.accent : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.image_not_supported, color: Colors.grey, size: 48),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildHotelActionButton(
                    'Website',
                    Icons.language,
                    () => _openHotelWebsite(widget.hotel),
                    enabled: _hasHotelWebsite(widget.hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHotelActionButton(
                    'Call',
                    Icons.phone,
                    () => _callHotel(widget.hotel),
                    enabled: _hasHotelPhone(widget.hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHotelActionButton(
                    'Directions',
                    Icons.directions,
                    () => _openHotelDirections(widget.hotel),
                    enabled: _hasHotelLocation(widget.hotel),
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ✅ FIX 1 & 2: StatefulWidget for PlaceCard to manage PageController and fix layout order
class _PlaceCardWidget extends StatefulWidget {
  final Map<String, dynamic> place;
  
  const _PlaceCardWidget({required this.place});
  
  @override
  State<_PlaceCardWidget> createState() => _PlaceCardWidgetState();
}

class _PlaceCardWidgetState extends State<_PlaceCardWidget> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  
  @override
  void initState() {
    super.initState();
    final images = _extractImages(widget.place);
    if (images.length > 1) {
      _pageController = PageController();
      _pageController.addListener(_onPageChanged);
    }
  }
  
  @override
  void dispose() {
    final images = _extractImages(widget.place);
    if (images.length > 1) {
      _pageController.removeListener(_onPageChanged);
      _pageController.dispose();
    }
    super.dispose();
  }
  
  void _onPageChanged() {
    if (_pageController.hasClients) {
      final newIndex = _pageController.page?.round() ?? 0;
      if (newIndex != _currentPageIndex) {
        setState(() {
          _currentPageIndex = newIndex;
        });
      }
    }
  }
  
  List<String> _extractImages(Map<String, dynamic> place) {
    final List<String> images = [];
    final Set<String> seenUrls = {};
    
    final imagesList = place['images'] as List?;
    final singleImage = place['image']?.toString() ?? 
                        place['thumbnail']?.toString() ?? 
                        place['photo']?.toString();
    
    if (imagesList != null && imagesList.isNotEmpty) {
      for (final img in imagesList) {
        final imgUrl = img?.toString().trim() ?? '';
        if (imgUrl.isNotEmpty && !seenUrls.contains(imgUrl)) {
          images.add(imgUrl);
          seenUrls.add(imgUrl);
        }
      }
    }
    
    if (singleImage != null && singleImage.isNotEmpty) {
      final trimmedSingleImage = singleImage.trim();
      if (!seenUrls.contains(trimmedSingleImage)) {
        images.insert(0, trimmedSingleImage);
        seenUrls.add(trimmedSingleImage);
      }
    }
    
    return images;
  }
  
  double _safeNumber(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }
  
  @override
  Widget build(BuildContext context) {
    final name = widget.place['name']?.toString() ?? widget.place['title']?.toString() ?? 'Unknown Place';
    final description = widget.place['description']?.toString() ?? widget.place['summary']?.toString() ?? '';
    final rating = _safeNumber(widget.place['rating'], 0.0);
    final images = _extractImages(widget.place);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ FIX 2: Place name and rating BEFORE images
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (rating > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
          // ✅ FIX 2: Images AFTER name and rating
          if (images.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: images.length == 1
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: images[0],
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported, color: Colors.grey),
                        ),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: EdgeInsets.only(right: index < images.length - 1 ? 8 : 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: images[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.image_not_supported, color: Colors.grey),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // ✅ FIX 1: Image indicator dots update based on current page
            if (images.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentPageIndex ? AppColors.accent : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ],
          // ✅ FIX 2: Description AFTER images
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Movie poster carousel StatefulWidget
class _MoviePosterCarouselWidget extends StatefulWidget {
  final List<String> images;
  
  const _MoviePosterCarouselWidget({required this.images});
  
  @override
  State<_MoviePosterCarouselWidget> createState() => _MoviePosterCarouselWidgetState();
}

class _MoviePosterCarouselWidgetState extends State<_MoviePosterCarouselWidget> {
  late PageController _pageController;
  int _currentIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index < widget.images.length - 1 ? 8 : 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: widget.images[index],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.images.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _currentIndex ? AppColors.accent : Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Widget to display Core Details and Box Office sections for movies
class _MovieDetailsSections extends StatefulWidget {
  final List<Map<String, dynamic>> movies;

  const _MovieDetailsSections({required this.movies});

  @override
  State<_MovieDetailsSections> createState() => _MovieDetailsSectionsState();
}

class _MovieDetailsSectionsState extends State<_MovieDetailsSections> {
  Map<String, dynamic>? _movieDetails;
  Map<String, dynamic>? _credits;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMovieDetails();
  }

  Future<void> _loadMovieDetails() async {
    if (widget.movies.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final firstMovie = widget.movies[0];
    final movieId = firstMovie['id'] as int? ?? 0;

    if (movieId == 0) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final details = await AgentService.getMovieDetails(movieId);
      final credits = await AgentService.getMovieCredits(movieId);
      
      if (mounted) {
        setState(() {
          _movieDetails = details;
          _credits = credits;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading movie details: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatRuntime(int? minutes) {
    if (minutes == null) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) {
      return '$hours hours $mins minutes';
    } else if (hours > 0) {
      return '$hours hours';
    } else if (mins > 0) {
      return '$mins minutes';
    }
    return '';
  }

  Widget _buildCoreDetailsSection() {
    final crew = _credits?['crew'] as List? ?? [];
    final cast = _credits?['cast'] as List? ?? [];
    final movieDetails = _movieDetails ?? {};
    
    // Extract director
    final director = crew.firstWhere(
      (c) => c['job'] == 'Director',
      orElse: () => null,
    );
    
    // Extract composer
    final composer = crew.firstWhere(
      (c) => c['job'] == 'Original Music Composer' || c['job'] == 'Music',
      orElse: () => null,
    );
    
    // Extract top cast (starring)
    final topCast = cast.take(3).toList();
    
    // Extract runtime
    final runtime = _formatRuntime(movieDetails['runtime'] as int?);
    
    // Extract storyline (overview)
    final storyline = movieDetails['overview']?.toString() ?? '';
    
    if (director == null && topCast.isEmpty && runtime.isEmpty && storyline.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Core Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (director != null) ...[
          _buildDetailRow('Director', '${director['name']?.toString() ?? 'Unknown'}.'),
          const SizedBox(height: 12),
        ],
        if (topCast.isNotEmpty) ...[
          _buildDetailRow(
            'Starring',
            topCast.asMap().entries.map((entry) {
              final index = entry.key;
              final actor = entry.value;
              final name = actor['name']?.toString() ?? 'Unknown';
              final character = actor['character']?.toString();
              if (character != null && character.isNotEmpty) {
                return '$name (as $character)';
              }
              if (index == topCast.length - 1 && topCast.length > 1) {
                return 'and $name';
              }
              return name;
            }).join(', '),
          ),
          const SizedBox(height: 12),
        ],
        if (storyline.isNotEmpty) ...[
          _buildDetailRow('Storyline', '"$storyline"'),
          const SizedBox(height: 12),
        ],
        if (composer != null) ...[
          _buildDetailRow('Music', 'Composed by ${composer['name']?.toString() ?? 'Unknown'}.'),
          const SizedBox(height: 12),
        ],
        if (runtime.isNotEmpty) ...[
          _buildDetailRow('Running Time', 'Approximately $runtime.'),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxOfficeSection() {
    final movieDetails = _movieDetails ?? {};
    final budget = movieDetails['budget'] as int?;
    final revenue = movieDetails['revenue'] as int?;
    final rating = (movieDetails['vote_average'] as num?)?.toDouble() ?? 0.0;
    final voteCount = movieDetails['vote_count'] as int? ?? 0;
    
    // Format currency
    String formatCurrency(int? amount) {
      if (amount == null || amount == 0) return '';
      if (amount >= 1000000000) {
        return '\$${(amount / 1000000000).toStringAsFixed(2)}B';
      } else if (amount >= 1000000) {
        return '\$${(amount / 1000000).toStringAsFixed(2)}M';
      } else if (amount >= 1000) {
        return '\$${(amount / 1000).toStringAsFixed(2)}K';
      }
      return '\$$amount';
    }
    
    final budgetFormatted = formatCurrency(budget);
    final revenueFormatted = formatCurrency(revenue);
    
    // Generate box office content
    final List<String> boxOfficeItems = [];
    
    if (budgetFormatted.isNotEmpty || revenueFormatted.isNotEmpty) {
      if (budgetFormatted.isNotEmpty && revenueFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film had a production budget of $budgetFormatted and grossed $revenueFormatted worldwide.');
      } else if (budgetFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film had a production budget of $budgetFormatted.');
      } else if (revenueFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film grossed $revenueFormatted worldwide.');
      }
    }
    
    if (revenueFormatted.isNotEmpty && budgetFormatted.isNotEmpty && budget != null && budget > 0) {
      final profit = revenue! - budget;
      final profitFormatted = formatCurrency(profit);
      if (profit > 0) {
        boxOfficeItems.add('**Weekend Performance:** The film generated a profit of $profitFormatted.');
      }
    }
    
    if (rating > 0 && voteCount > 0) {
      final ratingText = rating >= 7.0 
          ? 'positive' 
          : rating >= 5.0 
              ? 'mixed' 
              : 'negative';
      boxOfficeItems.add('**Critical Response:** The film has received $ratingText reviews, with an average rating of ${rating.toStringAsFixed(1)}/10 based on ${voteCount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} votes.');
    }
    
    if (boxOfficeItems.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text(
          'Box Office & Reception',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...boxOfficeItems.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildBoxOfficeItem(item),
        )),
      ],
    );
  }

  Widget _buildBoxOfficeItem(String text) {
    // Parse format: "**Label:** content"
    final match = RegExp(r'\*\*(.+?):\*\*\s*(.+)').firstMatch(text);
    if (match != null) {
      final label = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      return RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: content,
              style: const TextStyle(
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }
    // Fallback if format doesn't match
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_movieDetails == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCoreDetailsSection(),
        _buildBoxOfficeSection(),
        const SizedBox(height: 20),
      ],
    );
  }
}

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
import '../providers/session_history_provider.dart';
import '../widgets/StreamingTextWidget.dart';
import '../widgets/HotelMapView.dart';
import '../screens/FullScreenMapScreen.dart';
import '../screens/HotelResultsScreen.dart';
import '../screens/ShoppingGridScreen.dart';

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
          Padding(
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
                  _buildTags(session, ref),
                  // ✅ FIX 2: Add spacing between tags and map for hotels
                  if (session.resultType == 'hotel' || session.resultType == 'hotels')
                    ...(_buildHotelMap(session) != null ? [const SizedBox(height: 16), _buildHotelMap(session)!] : []),
                  // ✅ Perplexity-style: Query overview/description (contextual, informative, sets expectations)
                  if (session.summary != null && session.summary!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: StreamingTextWidget(
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
                    ),
                  _buildIntentBasedContent(session, ref),
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
  
  Widget _buildTags(QuerySession session, WidgetRef ref) {
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
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags,
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
          // Navigate to ShoppingGridScreen with all products
          final allProducts = <Product>[];
          final sessions = ref.read(sessionHistoryProvider);
          for (final s in sessions) {
            allProducts.addAll(s.products);
          }
          if (allProducts.isNotEmpty) {
            Navigator.push(
              model.context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: allProducts),
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
  
  Widget _buildIntentBasedContent(QuerySession session, WidgetRef ref) {
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
      return _buildMoviesContent(session, ref);
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
  
  Widget _buildMoviesContent(QuerySession session, WidgetRef ref) {
    const maxVisible = 6;
    final movies = session.cards.take(maxVisible).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...movies.map((movie) => RepaintBoundary(
          key: ValueKey('movie-${movie['id']}'),
          child: _buildMovieCard(movie),
        )),
        if (session.cards.length > movies.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+${session.cards.length - movies.length} more movies',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
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
    final name = hotel['name']?.toString() ?? 'Unknown Hotel';
    final rating = _safeNumber(hotel['rating'], 0.0);
    final price = _safeNumber(hotel['price'], 0.0);
    final description = hotel['description']?.toString() ?? hotel['summary']?.toString() ?? '';
    
    // ✅ FIX: Properly extract images from various formats (string, List<string>, List<Map>)
    final List<String> images = [];
    final imagesData = hotel['images'];
    if (imagesData != null) {
      if (imagesData is List) {
        for (final img in imagesData) {
          if (img is String && img.isNotEmpty) {
            images.add(img);
          } else if (img is Map) {
            // Try multiple fields: thumbnail, original_image, image, url
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
    
    // Fallback to thumbnail if no images found
    if (images.isEmpty) {
      final thumbnail = hotel['thumbnail']?.toString();
      if (thumbnail != null && thumbnail.isNotEmpty) {
        images.add(thumbnail);
      }
    }
    
    return GestureDetector(
      onTap: () => model.onHotelTap(hotel),
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
              // Image indicator dots if more than 1 image
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
                        color: index == 0 ? AppColors.accent : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              // Show placeholder if no images
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
            // ✅ FIX: Add action buttons (Website, Call, Directions) before description
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildHotelActionButton(
                    'Website',
                    Icons.language,
                    () => _openHotelWebsite(hotel),
                    enabled: _hasHotelWebsite(hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHotelActionButton(
                    'Call',
                    Icons.phone,
                    () => _callHotel(hotel),
                    enabled: _hasHotelPhone(hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHotelActionButton(
                    'Directions',
                    Icons.directions,
                    () => _openHotelDirections(hotel),
                    enabled: _hasHotelLocation(hotel),
                  ),
                ),
              ],
            ),
            // ✅ FIX 1: Hotel description - same styling as products (no maxLines, full description)
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                // ✅ FIX 1: Remove maxLines to match products (show full description)
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildPlaceCard(Map<String, dynamic> place) {
    final name = place['name']?.toString() ?? place['title']?.toString() ?? 'Unknown Place';
    final description = place['description']?.toString() ?? place['summary']?.toString() ?? '';
    final rating = _safeNumber(place['rating'], 0.0);
    
    // ✅ FIX: Properly extract and deduplicate place images (remove duplicates)
    final List<String> images = [];
    final Set<String> seenUrls = {}; // Track seen URLs to prevent duplicates
    
    // First, collect all possible image sources
    final imagesList = place['images'] as List?;
    final singleImage = place['image']?.toString() ?? 
                        place['thumbnail']?.toString() ?? 
                        place['photo']?.toString();
    
    // Extract from images array if available (deduplicate as we go)
    if (imagesList != null && imagesList.isNotEmpty) {
      for (final img in imagesList) {
        final imgUrl = img?.toString().trim() ?? '';
        if (imgUrl.isNotEmpty && !seenUrls.contains(imgUrl)) {
          images.add(imgUrl);
          seenUrls.add(imgUrl);
        }
      }
    }
    
    // Add single image field if not already in the list (avoid duplicate of first image)
    if (singleImage != null && singleImage.isNotEmpty) {
      final trimmedSingleImage = singleImage.trim();
      if (!seenUrls.contains(trimmedSingleImage)) {
        images.insert(0, trimmedSingleImage); // Add at beginning as primary image
        seenUrls.add(trimmedSingleImage);
      }
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ FIX 3: Show place images with horizontal scrolling (like hotels)
          if (images.isNotEmpty)
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
          if (images.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Image indicator dots if more than 1 image
            if (images.length > 1)
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
                      color: index == 0 ? AppColors.accent : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
          ],
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
          // ✅ FIX 1: Place description - same styling as products (no maxLines, full description)
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              // ✅ FIX 1: Remove maxLines to match products (show full description)
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildMovieCard(Map<String, dynamic> movie) {
    final title = movie['title']?.toString() ?? 'Unknown Movie';
    final poster = movie['poster']?.toString() ?? movie['image']?.toString();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (poster != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: poster,
                width: 80,
                height: 120,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 80,
                  height: 120,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 80,
                  height: 120,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              ),
            ),
          if (poster != null) const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 2,
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
  
  double _safeNumber(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    final str = value.toString().trim();
    if (str.isEmpty) return fallback;
    return double.tryParse(str) ?? fallback;
  }
  
  // ✅ FIX: Helper methods for hotel action buttons
  bool _hasHotelWebsite(Map<String, dynamic> hotel) {
    final link = hotel['link']?.toString() ?? hotel['website']?.toString() ?? hotel['url']?.toString() ?? '';
    return link.isNotEmpty && (link.startsWith('http://') || link.startsWith('https://'));
  }
  
  bool _hasHotelPhone(Map<String, dynamic> hotel) {
    final phone = hotel['phone']?.toString() ?? hotel['phone_number']?.toString() ?? '';
    return phone.isNotEmpty;
  }
  
  bool _hasHotelLocation(Map<String, dynamic> hotel) {
    final address = hotel['address']?.toString() ?? hotel['location']?.toString() ?? '';
    final lat = hotel['latitude'] ?? hotel['lat'];
    final lng = hotel['longitude'] ?? hotel['lng'];
    return address.isNotEmpty || (lat != null && lng != null);
  }
  
  Future<void> _openHotelWebsite(Map<String, dynamic> hotel) async {
    final link = hotel['link']?.toString() ?? hotel['website']?.toString() ?? hotel['url']?.toString() ?? '';
    if (link.isEmpty) {
      ScaffoldMessenger.of(model.context).showSnackBar(
        const SnackBar(content: Text('Website not available')),
      );
      return;
    }
    
    try {
      final uri = Uri.parse(link.startsWith('http') ? link : 'https://$link');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(model.context).showSnackBar(
          const SnackBar(content: Text('Cannot open website')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening website: $e');
      }
      ScaffoldMessenger.of(model.context).showSnackBar(
        const SnackBar(content: Text('Error opening website')),
      );
    }
  }
  
  Future<void> _callHotel(Map<String, dynamic> hotel) async {
    final phone = hotel['phone']?.toString() ?? hotel['phone_number']?.toString() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(model.context).showSnackBar(
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
        ScaffoldMessenger.of(model.context).showSnackBar(
          const SnackBar(content: Text('Cannot make phone call')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling hotel: $e');
      }
      ScaffoldMessenger.of(model.context).showSnackBar(
        const SnackBar(content: Text('Error making phone call')),
      );
    }
  }
  
  Future<void> _openHotelDirections(Map<String, dynamic> hotel) async {
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
      ScaffoldMessenger.of(model.context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }
    
    try {
      if (await canLaunchUrl(mapsUri)) {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(model.context).showSnackBar(
          const SnackBar(content: Text('Cannot open directions')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening directions: $e');
      }
      ScaffoldMessenger.of(model.context).showSnackBar(
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
}


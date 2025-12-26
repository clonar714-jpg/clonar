// ======================================================================
// PERPLEXITY ANSWER WIDGET - Simple, clean answer display
// ======================================================================
// Displays Perplexity-style answers with sections and sources
// No cards, no complexity - just answer + sections + sources

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/AppColors.dart';
import '../widgets/StreamingTextWidget.dart';
import '../models/query_session_model.dart';
import '../providers/follow_up_controller_provider.dart';
import '../utils/card_converters.dart';
import '../screens/ProductDetailScreen.dart';
import '../screens/HotelDetailScreen.dart';
import '../screens/MovieDetailScreen.dart';
import '../screens/PlaceDetailScreen.dart';
import '../screens/ShoppingGridScreen.dart';
import '../screens/HotelResultsScreen.dart';
import '../widgets/HotelMapView.dart';
import '../screens/FullScreenMapScreen.dart';
import '../models/Product.dart';

/// Simple Perplexity-style answer widget
/// Displays: Answer text (with sections) + Sources (clickable links)
/// ✅ NO HEADERS - Just answer content directly
class PerplexityAnswerWidget extends StatefulWidget {
  final QuerySession session;

  const PerplexityAnswerWidget({
    Key? key,
    required this.session,
  }) : super(key: key);

  @override
  State<PerplexityAnswerWidget> createState() => _PerplexityAnswerWidgetState();
}

class _PerplexityAnswerWidgetState extends State<PerplexityAnswerWidget> {
  int _selectedTagIndex = 0; // 0: Clonar, 1: Sources, 2: Media (Images + Videos)

  @override
  Widget build(BuildContext context) {
    // ✅ CRITICAL: Log IMMEDIATELY when widget builds
    print('🔥🔥🔥 PerplexityAnswerWidget.build() called for query: "${widget.session.query}"');
    
    final summary = widget.session.summary ?? "";
    final sections = widget.session.sections;
    final sources = widget.session.sources;
    final images = _getAllImages();
    
    // ✅ CRITICAL: Log what we're rendering (use print for visibility)
    print('📝 PerplexityAnswerWidget: Building answer widget');
    print('  - Summary length: ${summary.length}');
    print('  - Sections: ${sections?.length ?? 0}');
    print('  - Sources: ${sources.length}');
    print('  - Images: ${images.length}');
    
    if (sections != null && sections.isNotEmpty) {
      print('  - First section title: ${sections[0]['title']}');
      print('  - All section titles: ${sections.map((s) => s['title']).join(', ')}');
    }

    // ✅ NEW: Tag-based interface with 3 tags: Clonar, Sources, Images (styled like ShoppingResultsScreen)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ Tag-style chips (no icons, styled like ShoppingResultsScreen)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTag('Clonar', 0),
              _buildTag('Sources', 1),
              _buildTag('Media', 2), // ✅ RENAMED: Images → Media (includes images + videos)
              // ✅ Dynamic tags: Shopping/Hotels (only when cards exist)
              if (_hasProductCards()) _buildNavigationTag('Shopping', context),
              if (_hasHotelCards()) _buildNavigationTag('Hotels', context),
            ],
          ),
        ),
        
        // Content based on selected tag
        Expanded(
          child: IndexedStack(
            index: _selectedTagIndex,
            children: [
              // Tag 0: Clonar - Answer content
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAnswerContent(summary, sections),
                    // ✅ PERPLEXITY-STYLE: Display map if search returned map data
                    if (_shouldShowMap()) ...[
                      const SizedBox(height: 32),
                      _buildMapSection(context),
                    ],
                    // ✅ PERPLEXITY-STYLE: Display cards if search returned card data
                    if (_shouldShowCards()) ...[
                      const SizedBox(height: 32),
                      _buildCardsSection(context),
                    ],
                    const SizedBox(height: 32),
                    _buildFollowUps(context),
                  ],
                ),
              ),
              
              // Tag 1: Sources - Numbered sources list
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildSourcesTab(sources),
              ),
              
              // Tag 2: Images - Image grid
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildImagesTab(images),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // ✅ Build tag-style chip (styled like ShoppingResultsScreen, no icons)
  Widget _buildTag(String label, int index) {
    final isSelected = _selectedTagIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTagIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.primary.withOpacity(0.2) 
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: isSelected 
              ? Border.all(color: AppColors.primary, width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected 
                ? AppColors.primary 
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
  
  // ✅ Build navigation tag (Shopping/Hotels) - navigates to respective screens
  Widget _buildNavigationTag(String label, BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (label == 'Shopping') {
          // Convert product cards to Product models and navigate
          final products = _getProductsFromCards();
          if (products.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: products),
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
        } else if (label == 'Hotels') {
          // Navigate to HotelResultsScreen with query
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: widget.session.query),
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
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
  
  // ✅ Helper: Check if product cards exist
  bool _hasProductCards() {
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return false;
    final products = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
    return products.isNotEmpty;
  }
  
  // ✅ Helper: Check if hotel cards exist
  bool _hasHotelCards() {
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return false;
    final hotels = (cardsByDomain['hotels'] as List?)?.whereType<Map>().toList() ?? [];
    return hotels.isNotEmpty;
  }
  
  // ✅ Helper: Convert product cards to Product models
  List<Product> _getProductsFromCards() {
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return [];
    
    final productCards = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
    return productCards.map((card) => cardToProduct(Map<String, dynamic>.from(card))).toList();
  }
  
  // ✅ Helper: Get all images from session
  List<String> _getAllImages() {
    final images = <String>[];
    
    // Add search images (all domains: web, products, hotels, places, movies)
    // Note: destinationImages name is legacy - it contains all search images, not just destinations
    if (widget.session.destinationImages.isNotEmpty) {
      images.addAll(widget.session.destinationImages);
    }
    
    // Add allImages if available
    if (widget.session.allImages != null && widget.session.allImages!.isNotEmpty) {
      images.addAll(widget.session.allImages!);
    }
    
    // Extract images from cards
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain != null) {
      // Products
      final products = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
      for (final card in products) {
        if (card['thumbnail'] != null) images.add(card['thumbnail'].toString());
        if (card['images'] is List) {
          images.addAll((card['images'] as List).map((e) => e.toString()));
        }
      }
      
      // Hotels
      final hotels = (cardsByDomain['hotels'] as List?)?.whereType<Map>().toList() ?? [];
      for (final card in hotels) {
        if (card['thumbnail'] != null) images.add(card['thumbnail'].toString());
        if (card['images'] is List) {
          images.addAll((card['images'] as List).map((e) => e.toString()));
        }
      }
      
      // Places
      final places = (cardsByDomain['places'] as List?)?.whereType<Map>().toList() ?? [];
      for (final card in places) {
        if (card['thumbnail'] != null) images.add(card['thumbnail'].toString());
        if (card['images'] is List) {
          images.addAll((card['images'] as List).map((e) => e.toString()));
        }
      }
      
      // Movies
      final movies = (cardsByDomain['movies'] as List?)?.whereType<Map>().toList() ?? [];
      for (final card in movies) {
        if (card['thumbnail'] != null) images.add(card['thumbnail'].toString());
        if (card['images'] is List) {
          images.addAll((card['images'] as List).map((e) => e.toString()));
        }
      }
    }
    
    // Remove duplicates and empty strings
    return images.where((img) => img.isNotEmpty).toSet().toList();
  }
  
  // ✅ Tab 2: Sources with numbering
  Widget _buildSourcesTab(List<Map<String, dynamic>> sources) {
    if (sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No sources available',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...sources.asMap().entries.map((entry) {
          final index = entry.key;
          final source = entry.value;
          final title = source['title']?.toString() ?? 'Untitled Source';
          final link = source['link']?.toString() ?? source['url']?.toString() ?? '';
          
          if (link.isEmpty) return const SizedBox.shrink();
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: () => _openSource(link),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source number (as shown in image)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Source title and link
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatUrl(link),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // External link icon
                    Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
  
  // ✅ Tab 3: Images grid
  Widget _buildImagesTab(List<String> images) {
    if (images.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No images available',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final imageUrl = images[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppColors.surfaceVariant,
              child: Icon(
                Icons.broken_image,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFollowUps(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final session = widget.session;
        
        // ✅ PROFESSIONAL: Only show "Related" section if:
        // 1. Real follow-ups are available (from backend LLM generation)
        // 2. Streaming is complete (not still generating answer)
        // This prevents showing placeholder/fallback follow-ups that will change
        if (session.followUpSuggestions.isEmpty || session.isStreaming || session.isParsing) {
          return const SizedBox.shrink();
        }
        
        // ✅ Use real follow-ups directly (no fallback heuristics)
        final followUps = session.followUpSuggestions;
        if (followUps.isEmpty) return const SizedBox.shrink();
        
        final limited = followUps.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Related",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...limited.map((suggestion) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      // Handle follow-up tap
                      ref.read(followUpControllerProvider.notifier).handleFollowUp(
                        suggestion,
                        widget.session,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.expand_more,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildAnswerContent(String summary, List<Map<String, dynamic>>? sections) {
    final sources = widget.session.sources;
    final sourcesCount = sources.length;
    
    // ✅ PERPLEXITY-STYLE: Render structured sections if available
    if (sections != null && sections.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ 1. Initial Overview Paragraph (Perplexity-style)
          if (summary.isNotEmpty) ...[
            StreamingTextWidget(
              targetText: summary,
              enableAnimation: false,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
                height: 1.7,
                letterSpacing: -0.1,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // ✅ 2. Sources Indicator (Perplexity-style: "Reviewed X sources")
          if (sourcesCount > 0) ...[
            Row(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  sourcesCount == 1 
                    ? 'Reviewed 1 source'
                    : 'Reviewed $sourcesCount sources',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          
          // ✅ 3. Render each section with improved spacing
          ...sections.asMap().entries.map((entry) {
            final index = entry.key;
            final section = entry.value;
            final title = section['title']?.toString() ?? '';
            final content = section['content']?.toString() ?? '';
            
            // ✅ FIX: Skip sections with empty title or content
            if (title.isEmpty || content.isEmpty) return const SizedBox.shrink();
            
            // ✅ FIX: Skip "FOLLOW_UP_SUGGESTIONS:" section (it's metadata, not content)
            if (title.toUpperCase().contains('FOLLOW_UP_SUGGESTIONS')) {
              return const SizedBox.shrink();
            }
            
            // ✅ FIX: Skip "Overview" section if summary is already shown (prevents duplication)
            // But allow "Details" section even if summary exists (it contains additional content)
            if (title.toLowerCase() == 'overview' && summary.isNotEmpty) {
              return const SizedBox.shrink();
            }
            
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == sections.length - 1 ? 0 : 32, // ✅ More spacing between sections
                top: index == 0 ? 0 : 0, // First section already has spacing from sources indicator
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section title (Perplexity-style heading)
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Section content
                  StreamingTextWidget(
                    targetText: content,
                    enableAnimation: false,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      height: 1.65,
                      letterSpacing: -0.1,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    }

    // Fallback: Render summary text if no sections
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary text
        StreamingTextWidget(
          targetText: summary,
          enableAnimation: false,
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.textPrimary,
            height: 1.7,
            letterSpacing: -0.1,
            fontWeight: FontWeight.w400,
          ),
        ),
        // Sources indicator if available
        if (sourcesCount > 0) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(
                Icons.article_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                sourcesCount == 1 
                  ? 'Reviewed 1 source'
                  : 'Reviewed $sourcesCount sources',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }


  String _formatUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Remove protocol and www
      String display = uri.host;
      if (display.startsWith('www.')) {
        display = display.substring(4);
      }
      // Add path if short
      if (uri.path.isNotEmpty && uri.path.length < 30) {
        display += uri.path;
      }
      return display;
    } catch (e) {
      return url;
    }
  }

  Future<void> _openSource(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Handle error silently
      debugPrint('Error opening source: $e');
    }
  }
  
  // ✅ PERPLEXITY-STYLE: Check if cards should be displayed
  // ✅ PERPLEXITY-STYLE: Frontend UI gating based on actual data presence
  bool _shouldShowCards() {
    // Check if we have cards from backend (search-first)
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return false;
    
    final hasProducts = (cardsByDomain['products'] as List?)?.isNotEmpty ?? false;
    final hasHotels = (cardsByDomain['hotels'] as List?)?.isNotEmpty ?? false;
    final hasPlaces = (cardsByDomain['places'] as List?)?.isNotEmpty ?? false;
    final hasMovies = (cardsByDomain['movies'] as List?)?.isNotEmpty ?? false;
    
    return hasProducts || hasHotels || hasPlaces || hasMovies;
  }
  
  // ✅ Helper: Check if map should be shown
  // ✅ PERPLEXITY-STYLE: Frontend UI gating based on actual data presence
  bool _shouldShowMap() {
    // Check if we have map points from backend (search-first)
    if (widget.session.mapPoints != null && widget.session.mapPoints!.isNotEmpty) {
      return true;
    }
    
    // Check if we have location data from cards
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return false;
    
    // Collect all map points from hotels and places
    final mapPoints = <Map<String, dynamic>>[];
    
    // Hotels
    final hotels = (cardsByDomain['hotels'] as List?)?.whereType<Map>().toList() ?? [];
    for (final hotel in hotels) {
      final location = hotel['location'];
      if (location is Map && location['lat'] != null && location['lng'] != null) {
        mapPoints.add({
          'latitude': location['lat'],
          'longitude': location['lng'],
          'title': hotel['name'] ?? 'Hotel',
        });
      }
    }
    
    // Places
    final places = (cardsByDomain['places'] as List?)?.whereType<Map>().toList() ?? [];
    for (final place in places) {
      final location = place['location'];
      if (location is Map && location['lat'] != null && location['lng'] != null) {
        mapPoints.add({
          'latitude': location['lat'],
          'longitude': location['lng'],
          'title': place['name'] ?? 'Place',
        });
      }
    }
    
    return mapPoints.isNotEmpty;
  }
  
  // ✅ PERPLEXITY-STYLE: Build map section (styled like ShoppingResultsScreen)
  Widget _buildMapSection(BuildContext context) {
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return const SizedBox.shrink();
    
    // Collect all map points from hotels and places
    final mapPoints = <Map<String, dynamic>>[];
    
    // Hotels
    final hotels = (cardsByDomain['hotels'] as List?)?.whereType<Map>().toList() ?? [];
    for (final hotel in hotels) {
      final location = hotel['location'];
      if (location is Map && location['lat'] != null && location['lng'] != null) {
        mapPoints.add({
          'latitude': location['lat'],
          'longitude': location['lng'],
          'title': hotel['name'] ?? 'Hotel',
          'address': hotel['address'] ?? '',
        });
      }
    }
    
    // Places
    final places = (cardsByDomain['places'] as List?)?.whereType<Map>().toList() ?? [];
    for (final place in places) {
      final location = place['location'];
      if (location is Map && location['lat'] != null && location['lng'] != null) {
        mapPoints.add({
          'latitude': location['lat'],
          'longitude': location['lng'],
          'title': place['name'] ?? 'Place',
          'address': place['address'] ?? '',
        });
      }
    }
    
    if (mapPoints.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FullScreenMapScreen(
                points: mapPoints,
                title: widget.session.query,
              ),
            ),
          );
        },
        child: Stack(
          children: [
            HotelMapView(
              key: ValueKey('hotel-map-view-${mapPoints.length}'),
              points: mapPoints,
              height: MediaQuery.of(context).size.height * 0.65,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FullScreenMapScreen(
                      points: mapPoints,
                      title: widget.session.query,
                    ),
                  ),
                );
              },
            ),
            // Visual indicator at bottom (styled like ShoppingResultsScreen)
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
    );
  }
  
  // ✅ PERPLEXITY-STYLE: Build cards section
  Widget _buildCardsSection(BuildContext context) {
    final cardsByDomain = widget.session.cardsByDomain;
    if (cardsByDomain == null) return const SizedBox.shrink();
    
    final widgets = <Widget>[];
    
    // Products
    final products = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
    if (products.isNotEmpty) {
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Section header only if multiple products (Perplexity-style)
            if (products.length > 1) ...[
              const Text(
                'Products',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ...products.map((card) => _buildProductCard(context, card)),
          ],
        ),
      );
    }
    
    // Hotels
    final hotels = (cardsByDomain['hotels'] as List?)?.whereType<Map>().toList() ?? [];
    if (hotels.isNotEmpty) {
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hotels',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...hotels.map((card) => _buildHotelCard(context, card)),
          ],
        ),
      );
    }
    
    // Places
    final places = (cardsByDomain['places'] as List?)?.whereType<Map>().toList() ?? [];
    if (places.isNotEmpty) {
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Places',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...places.map((card) => _buildPlaceCard(context, card)),
          ],
        ),
      );
    }
    
    // Movies
    final movies = (cardsByDomain['movies'] as List?)?.whereType<Map>().toList() ?? [];
    if (movies.isNotEmpty) {
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Movies',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...movies.map((card) => _buildMovieCard(context, card)),
          ],
        ),
      );
    }
    
    if (widgets.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets.expand((w) => [w, const SizedBox(height: 24)]).toList()..removeLast(),
    );
  }
  
  // ✅ Shopping Product card (Perplexity-style: 2 side-by-side swipeable images, rating+price+retailer on same line, 2 buttons)
  Widget _buildProductCard(BuildContext context, Map<dynamic, dynamic> card) {
    final cardMap = Map<String, dynamic>.from(card);
    final product = cardToProduct(cardMap);
    final validImages = product.images.where((img) => img.trim().isNotEmpty).toList();
    final hasImage = validImages.isNotEmpty;
    final priceValid = product.price > 0;
    final sourceValid = product.source.isNotEmpty && product.source != "Unknown Source";
    final hasRating = product.rating > 0;
    final hasReviews = product.reviews != null && product.reviews! > 0;
    final hasLink = product.link != null && product.link!.isNotEmpty;
    
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
              // Title (Bold, larger)
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
              
              // Rating + Reviews + Price + Retailer (all on same line, Perplexity-style)
              // Format: ★ 4.8 (101) · $225.00 · Dillard's
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
                    if (hasReviews) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${product.reviews})',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (priceValid || sourceValid) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '·',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                  if (priceValid) ...[
                    Text(
                      '\$${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (sourceValid) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '·',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                  if (sourceValid)
                    Text(
                      product.source,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              // ✅ 2 side-by-side swipeable images (PageView)
              if (hasImage)
                _buildSwipeableProductImages(validImages)
              else
                _buildNoImagePlaceholder(height: 160),
              
              const SizedBox(height: 12),
              
              // ✅ 2 Action Buttons (always shown): "Learn more" and "Visit site"
              Row(
                children: [
                  // Learn more button (opens detail page)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProductDetailScreen(product: product),
                          ),
                        );
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Center(
                            child: Text(
                              'Learn more',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Visit site button (redirects to product link)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final link = hasLink ? product.link! : product.source;
                        try {
                          final url = Uri.parse(link);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        } catch (e) {
                          // If link is invalid, try source as URL
                          if (link != product.source) {
                            try {
                              final url = Uri.parse(product.source);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            } catch (e2) {
                              // Show error
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Unable to open link'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          }
                        }
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_new, size: 16, color: AppColors.textPrimary),
                              SizedBox(width: 6),
                              Text(
                                'Visit site',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
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
              
              const SizedBox(height: 12),
              
              // Description (below buttons)
              if (product.description.trim().isNotEmpty)
                Text(
                  product.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                )
              else
                const Text(
                  'No description available',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ✅ Build 2 side-by-side swipeable images (PageView for each)
  Widget _buildSwipeableProductImages(List<String> images) {
    // Always show exactly 2 images side-by-side
    // If only 1 image, duplicate it
    // If 3+ images, show first 2, but make them swipeable to see more
    final image1 = images.isNotEmpty ? images[0] : '';
    final image2 = images.length > 1 ? images[1] : (images.isNotEmpty ? images[0] : '');
    
    // Prepare image lists for PageView (include all images for swiping)
    final image1List = images.isNotEmpty ? images : [];
    final image2List = images.length > 1 ? images.sublist(1) : (images.isNotEmpty ? images : []);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left image (swipeable)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: image1List.length > 1
                  ? PageView.builder(
                      itemCount: image1List.length,
                      itemBuilder: (context, index) {
                        return CachedNetworkImage(
                          imageUrl: image1List[index],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                            ),
                          ),
                        );
                      },
                    )
                  : CachedNetworkImage(
                      imageUrl: image1,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      errorWidget: (context, url, error) => _buildNoImagePlaceholder(height: 0),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Right image (swipeable)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: image2List.length > 1
                  ? PageView.builder(
                      itemCount: image2List.length,
                      itemBuilder: (context, index) {
                        return CachedNetworkImage(
                          imageUrl: image2List[index],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                            ),
                          ),
                        );
                      },
                    )
                  : CachedNetworkImage(
                      imageUrl: image2,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      errorWidget: (context, url, error) => _buildNoImagePlaceholder(height: 0),
                    ),
            ),
          ),
        ),
      ],
    );
  }
  
  // ✅ Hotel card
  Widget _buildHotelCard(BuildContext context, Map<dynamic, dynamic> card) {
    final cardMap = Map<String, dynamic>.from(card);
    final name = cardMap['name']?.toString() ?? 'Unknown Hotel';
    final price = cardMap['price']?.toString() ?? '';
    final rating = cardMap['rating'];
    final thumbnail = cardMap['thumbnail']?.toString() ?? cardMap['image']?.toString() ?? '';
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HotelDetailScreen(hotel: cardMap),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_not_supported, size: 32),
                  ),
                ),
              ),
            if (thumbnail.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating.toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                  if (price.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
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
  
  // ✅ Place card
  Widget _buildPlaceCard(BuildContext context, Map<dynamic, dynamic> card) {
    final cardMap = Map<String, dynamic>.from(card);
    final name = cardMap['name']?.toString() ?? 'Unknown Place';
    final address = cardMap['address']?.toString() ?? cardMap['location']?.toString() ?? '';
    final rating = cardMap['rating'];
    final thumbnail = cardMap['thumbnail']?.toString() ?? cardMap['image']?.toString() ?? '';
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaceDetailScreen(place: cardMap),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_not_supported, size: 32),
                  ),
                ),
              ),
            if (thumbnail.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating.toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
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
  
  // ✅ Movie card
  Widget _buildMovieCard(BuildContext context, Map<dynamic, dynamic> card) {
    final cardMap = Map<String, dynamic>.from(card);
    final title = cardMap['title']?.toString() ?? 'Unknown Movie';
    final releaseDate = cardMap['releaseDate']?.toString() ?? '';
    final rating = cardMap['rating'];
    final thumbnail = cardMap['thumbnail']?.toString() ?? cardMap['poster']?.toString() ?? '';
    final movieId = cardToMovieId(cardMap);
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MovieDetailScreen(
              movieId: movieId,
              movieTitle: title,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: thumbnail,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_not_supported, size: 32),
                  ),
                ),
              ),
            if (thumbnail.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (releaseDate.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      releaseDate,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                  if (rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating.toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
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
  
  // ✅ Image helper methods (matching ShoppingResultsScreen)
  Widget _buildImage(String url, {double height = 160}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
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
  
  Widget _buildExtraImagesCard(List<String> extraImages, {double height = 160}) {
    if (extraImages.isEmpty) {
      return _buildNoImagePlaceholder(height: height);
    }
    
    if (extraImages.length == 1) {
      return _buildImage(extraImages[0], height: height);
    }
    
    final imagesToShow = extraImages.take(4).toList();
    final isTwoRows = imagesToShow.length > 2;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: height,
        child: isTwoRows
            ? Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildSmallImage(imagesToShow[0])),
                        const SizedBox(width: 2),
                        Expanded(child: _buildSmallImage(imagesToShow.length > 1 ? imagesToShow[1] : imagesToShow[0])),
                      ],
                    ),
                  ),
                  if (imagesToShow.length > 2) ...[
                    const SizedBox(height: 2),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildSmallImage(imagesToShow[2])),
                          if (imagesToShow.length > 3) ...[
                            const SizedBox(width: 2),
                            Expanded(child: _buildSmallImage(imagesToShow[3])),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              )
            : Row(
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
  
  Widget _buildSmallImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 1)),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 20),
        ),
      ),
    );
  }
  
  Widget _buildNoImagePlaceholder({double height = 160}) {
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
}


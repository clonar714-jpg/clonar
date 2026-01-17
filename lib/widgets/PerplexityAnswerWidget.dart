

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../theme/AppColors.dart';
import '../models/query_session_model.dart';
import '../providers/follow_up_controller_provider.dart';
import '../providers/session_phase_provider.dart';
import '../providers/session_stream_provider.dart';
import '../providers/session_history_provider.dart';
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


class PerplexityAnswerWidget extends ConsumerStatefulWidget {
  final String sessionId; 

  const PerplexityAnswerWidget({
    Key? key,
    required this.sessionId,
  }) : super(key: key);

  @override
  ConsumerState<PerplexityAnswerWidget> createState() => _PerplexityAnswerWidgetState();
}

class _PerplexityAnswerWidgetState extends ConsumerState<PerplexityAnswerWidget> {
  int _selectedTagIndex = 0; 

  @override
  Widget build(BuildContext context) {
    debugPrint('🧱 PerplexityAnswerWidget BUILD');
    
   
    final phase = ref.watch(sessionPhaseProvider(widget.sessionId));
    
    
    if (phase == QueryPhase.searching) {
      return _buildLoadingStatus();
    }
    
   
    QuerySession? session;
    if (phase == QueryPhase.done) {
      session = ref.read(sessionByIdProvider(widget.sessionId));
    }
    
    
    final allSections = session?.sections;
    
    final approachSection = allSections?.firstWhere(
      (s) {
        final title = s['title']?.toString().toLowerCase() ?? '';
        return title.contains('how i approached') || 
               title.contains('how this answer') ||
               s['kind']?.toString() == 'explanation';
      },
      orElse: () => <String, dynamic>{},
    );
    final sources = session?.sources ?? <Map<String, dynamic>>[];
    final images = session != null ? _getAllImages(session) : <String>[];

    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTag('Clonar', 0),
              _buildTag('Sources', 1),
              _buildTag('Media', 2), 
              
              if (phase == QueryPhase.done && session != null && _hasProductCards(session)) 
                _buildNavigationTag('Shopping', context, session),
              if (phase == QueryPhase.done && session != null && _hasHotelCards(session)) 
                _buildNavigationTag('Hotels', context, session),
            ],
          ),
        ),
        
        // Content based on selected tag
        // ✅ FIX: Remove Expanded/ConstrainedBox - let content size naturally like ChatGPT/Perplexity
        // Use IntrinsicHeight so IndexedStack sizes to the currently visible child
        IntrinsicHeight(
          child: IndexedStack(
            index: _selectedTagIndex,
            children: [
              // Tag 0: Clonar - Answer content
              // ✅ FIX: Remove SingleChildScrollView - parent CustomScrollView handles scrolling
              // Content should size naturally without scroll constraints
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    
                    if (phase == QueryPhase.answering && session?.researchStep != null) ...[
                      _buildResearchProgress(session!),
                      const SizedBox(height: 24),
                    ],
                    
                    if (session?.reasoningSteps.isNotEmpty ?? false) ...[
                      _buildReasoningSection(session!),
                      const SizedBox(height: 24),
                    ],
                    
                    if (phase == QueryPhase.answering && (session?.sources.isNotEmpty ?? false)) ...[
                      _buildRealTimeSources(session!),
                      const SizedBox(height: 24),
                    ],
                    
                    _buildAnswerContent(phase, session),
                    
                    if (phase == QueryPhase.done && session != null && _shouldShowMap(session)) ...[
                      const SizedBox(height: 32),
                      _buildMapSection(context, session),
                    ],
                    
                    if (phase == QueryPhase.done && session != null && _shouldShowCards(session)) ...[
                      const SizedBox(height: 32),
                      _buildCardsSection(context, session),
                    ],
                    
                    if (phase == QueryPhase.done && session != null && approachSection != null && approachSection.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildApproachCard(approachSection),
                    ],
                    if (phase == QueryPhase.done && session != null) _buildFollowUps(context, session),
                  ],
                ),
              ),
              
              // Tag 1: Sources - Numbered sources list
              // ✅ FIX: Remove SingleChildScrollView - parent handles scrolling
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildSourcesTab(sources),
              ),
              
              // Tag 2: Images - Image grid
              // ✅ FIX: Remove SingleChildScrollView - parent handles scrolling
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildImagesTab(images),
              ),
            ],
          ),
        ),
      ],
    );
  }
  

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
  
  
  Widget _buildNavigationTag(String label, BuildContext context, QuerySession session) {
    return GestureDetector(
      onTap: () {
        if (label == 'Shopping') {
          
          final products = _getProductsFromCards(session);
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
              builder: (context) => HotelResultsScreen(query: session.query),
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
  
 
  bool _hasProductCards(QuerySession session) {
    final cardsByDomain = session.cardsByDomain;
    if (cardsByDomain == null) return false;
    final products = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
    return products.isNotEmpty;
  }
  
  
  bool _hasHotelCards(QuerySession session) {
    final cardsByDomain = session.cardsByDomain;
    if (cardsByDomain == null) return false;
    final hotels = (cardsByDomain['hotels'] as List?)?.whereType<Map>().toList() ?? [];
    return hotels.isNotEmpty;
  }
  
  
  List<Product> _getProductsFromCards(QuerySession session) {
    final cardsByDomain = session.cardsByDomain;
    if (cardsByDomain == null) return [];
    
    final productCards = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
    return productCards.map((card) => cardToProduct(Map<String, dynamic>.from(card))).toList();
  }
  
  
  List<String> _getAllImages(QuerySession session) {
    final images = <String>[];
    

    if (session.destinationImages.isNotEmpty) {
      images.addAll(session.destinationImages);
    }
    
    
    if (session.allImages != null && session.allImages!.isNotEmpty) {
      images.addAll(session.allImages!);
    }
    
   
    final cardsByDomain = session.cardsByDomain;
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

  Widget _buildFollowUps(BuildContext context, QuerySession session) {
    
    if (session.followUpSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    
    
    final followUps = session.followUpSuggestions;
    if (followUps.isEmpty) return const SizedBox.shrink();
    
    final limited = followUps.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Follow-up questions",
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
                    session,
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
  }

  Widget _buildAnswerContent(QueryPhase phase, QuerySession? session) {
    
    if (phase == QueryPhase.answering) {
      
      final stream = ref.watch(sessionStreamFamilyProvider(widget.sessionId));
      
      return StreamBuilder<String>(
        stream: stream,
        initialData: '',
        builder: (context, snapshot) {
          final streamedText = snapshot.data ?? '';
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              if (streamedText.isNotEmpty) ...[
                Text(
                  streamedText,
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
            ],
          );
        },
      );
    } else {
      
      final answerText = session?.answer ?? session?.summary ?? '';
      final sourcesCount = session?.sources.length ?? 0;
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
         
          if (answerText.isNotEmpty) ...[
            Text(
              answerText,
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
          
          
          if (phase == QueryPhase.done && sourcesCount > 0) ...[
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
            const SizedBox(height: 16),
          ],
        ],
      );
    }
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
  
  
  bool _shouldShowCards(QuerySession session) {
    if (session.uiDecision == null) return false;
    
    final showCards = session.uiDecision!['showCards'];
    return showCards is bool ? showCards : false;
  }
  

  bool _shouldShowMap(QuerySession session) {
    if (session.uiDecision == null) return false;
    
    final showMap = session.uiDecision!['showMap'];
    return showMap is bool ? showMap : false;
  }
  
 
  Widget _buildMapSection(BuildContext context, QuerySession session) {
    final cardsByDomain = session.cardsByDomain;
    if (cardsByDomain == null) return const SizedBox.shrink();
    
    
    final mapPoints = <Map<String, dynamic>>[];
    
    
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
              height: MediaQuery.of(context).size.height * 0.65,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FullScreenMapScreen(
                      points: mapPoints,
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
    );
  }
  
  
  Widget _buildCardsSection(BuildContext context, QuerySession session) {
    final cardsByDomain = session.cardsByDomain;
    if (cardsByDomain == null) return const SizedBox.shrink();
    
    final widgets = <Widget>[];
    
    // Products
    final products = (cardsByDomain['products'] as List?)?.whereType<Map>().toList() ?? [];
    if (products.isNotEmpty) {
      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
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
  
  
  Widget _buildSwipeableProductImages(List<String> images) {
    
    final image1 = images.isNotEmpty ? images[0] : '';
    final image2 = images.length > 1 ? images[1] : (images.isNotEmpty ? images[0] : '');
    
    
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

  
  Widget _buildApproachCard(Map<String, dynamic> approachSection) {
    final content = approachSection['content']?.toString() ?? '';
    
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return StatefulBuilder(
      builder: (context, setState) {
        bool isExpanded = false; 
        
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.border.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (clickable to expand/collapse)
              InkWell(
                onTap: () {
                  setState(() {
                    isExpanded = !isExpanded;
                  });
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How this answer was generated',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              // Content (collapsible)
              if (isExpanded) ...[
                Divider(height: 1, color: AppColors.border.withOpacity(0.3)),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ✅ ENHANCEMENT 1: Build reasoning section (collapsible)
  Widget _buildReasoningSection(QuerySession session) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isExpanded = true; // Default to expanded
        
        return Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (clickable to expand/collapse)
              InkWell(
                onTap: () {
                  setState(() {
                    isExpanded = !isExpanded;
                  });
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Thinking Process',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              // Reasoning steps (collapsible)
              if (isExpanded) ...[
                Divider(height: 1, color: AppColors.primary.withOpacity(0.2)),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: session.reasoningSteps.asMap().entries.map((entry) {
                      final index = entry.key;
                      final reasoning = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(bottom: index < session.reasoningSteps.length - 1 ? 12 : 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                reasoning,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  
  Widget _buildRealTimeSources(QuerySession session) {
    final sources = session.sources;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sources Found (${sources.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sources.take(5).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final source = entry.value;
              final title = source['title']?.toString() ?? 'Untitled Source';
              final url = source['url']?.toString() ?? source['link']?.toString() ?? '';
              
              return Padding(
                padding: EdgeInsets.only(bottom: index < sources.length - 1 ? 8 : 0),
                child: InkWell(
                  onTap: url.isNotEmpty ? () => _openSource(url) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (url.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatUrl(url),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (url.isNotEmpty)
                          Icon(
                            Icons.open_in_new,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
            if (sources.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... and ${sources.length - 5} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  
  Widget _buildResearchProgress(QuerySession session) {
    final step = session.researchStep ?? 0;
    final maxSteps = session.maxResearchSteps ?? 1;
    final currentAction = session.currentAction ?? 'Researching...';
    final progress = maxSteps > 0 ? (step / maxSteps).clamp(0.0, 1.0) : 0.0;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Research Progress',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Step $step of $maxSteps',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (currentAction.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Current: $currentAction',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  
  Widget _buildLoadingStatus() {
    // Read session lazily for query text
    final session = ref.read(sessionByIdProvider(widget.sessionId));
    final query = session?.query.toLowerCase() ?? '';
    String loadingText = 'Working…';
    
    
    if (query.contains('hotel') || query.contains('hotels')) {
      // Try to extract location
      final locationMatch = RegExp(r'(?:hotels?|hotel)\s+(?:in|near|at|for)\s+([^,]+)').firstMatch(query);
      if (locationMatch != null) {
        final location = locationMatch.group(1)?.trim() ?? '';
        if (location.isNotEmpty) {
          loadingText = 'Searching for hotels in $location';
        } else {
          loadingText = 'Searching for hotels…';
        }
      } else {
        loadingText = 'Searching for hotels…';
      }
    } else if (query.contains('product') || query.contains('buy') || query.contains('shop') || query.contains('shopping')) {
      // Extract product keywords
      final productMatch = RegExp(r'(?:product|buy|shop|shopping|find)\s+(.+?)(?:\s+(?:in|near|at|for|under|below|above|over))').firstMatch(query);
      if (productMatch != null) {
        final product = productMatch.group(1)?.trim() ?? '';
        if (product.isNotEmpty && product.length < 50) {
          loadingText = 'Searching for $product…';
        } else {
          loadingText = 'Searching for products…';
        }
      } else {
        loadingText = 'Searching for products…';
      }
    } else if (query.contains('place') || query.contains('places') || query.contains('restaurant') || query.contains('restaurants')) {
      // Extract location for places
      final locationMatch = RegExp(r'(?:place|places|restaurant|restaurants)\s+(?:in|near|at|for)\s+([^,]+)').firstMatch(query);
      if (locationMatch != null) {
        final location = locationMatch.group(1)?.trim() ?? '';
        if (location.isNotEmpty) {
          loadingText = 'Searching for places in $location';
        } else {
          loadingText = 'Searching for places…';
        }
      } else {
        loadingText = 'Searching for places…';
      }
    } else if (query.contains('movie') || query.contains('movies') || query.contains('film') || query.contains('films')) {
      loadingText = 'Searching for movies…';
    } else {
      // Generic loading message
      loadingText = 'Working…';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loadingText,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

}


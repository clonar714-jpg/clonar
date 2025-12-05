import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class HotelPhotoGalleryScreen extends StatefulWidget {
  final Map<String, dynamic> hotel;

  const HotelPhotoGalleryScreen({Key? key, required this.hotel}) : super(key: key);

  @override
  State<HotelPhotoGalleryScreen> createState() => _HotelPhotoGalleryScreenState();
}

class _HotelPhotoGalleryScreenState extends State<HotelPhotoGalleryScreen> {
  String _selectedCategory = 'All photos';

  // Photo categories - ready for future affiliate APIs
  final List<String> _categories = [
    'All photos',
    'Guest photos',
    'Rooms',
    'Bathroom',
    'Exterior',
    'Amenities',
    'Common areas',
    'Dining',
    'Other',
  ];

  // Get all images from hotel data
  List<String> _getAllImages() {
    final dynamic imagesData = widget.hotel['images'];
    List<String> images = [];
    
    if (imagesData != null && imagesData is List) {
      for (final img in imagesData) {
        if (img is String && img.isNotEmpty) {
          images.add(img);
        } else if (img is Map && img['thumbnail'] != null) {
          final thumbnail = img['thumbnail'].toString();
          if (thumbnail.isNotEmpty) {
            images.add(thumbnail);
          }
        }
      }
    }
    
    // Fallback to thumbnail if available
    if (images.isEmpty) {
      final thumbnail = widget.hotel['thumbnail'];
      if (thumbnail != null && thumbnail.toString().isNotEmpty) {
        images = [thumbnail.toString()];
      }
    }
    
    return images;
  }

  // ============================================================================
  // MULTI-PHASE IMAGE CLASSIFICATION SYSTEM
  // ============================================================================
  // Phase 1: URL/Filename keyword analysis (ACTIVE)
  // Phase 2: Image content analysis via Google Cloud Vision API (READY)
  // Phase 3: Affiliate API metadata (READY)
  // Phase 4: Fallback to "All photos" and "Other" (ACTIVE)
  // ============================================================================

  // Main categorization method - orchestrates all phases
  Map<String, List<String>> _getCategorizedImages() {
    final allImages = _getAllImages();
    final categorized = <String, List<String>>{};
    
    // Initialize all categories with empty lists
    for (final category in _categories) {
      categorized[category] = [];
    }
    
    // Classify each image through all phases
    final classifiedImages = <String, String>{}; // imageUrl -> category
    final unclassifiedImages = <String>[];
    
    for (final imageUrl in allImages) {
      String? category = _classifyImage(imageUrl);
      
      if (category != null && category != 'Other') {
        classifiedImages[imageUrl] = category;
        categorized[category]!.add(imageUrl);
      } else {
        unclassifiedImages.add(imageUrl);
      }
    }
    
    // Phase 4: Fallback - add unclassified images to "All photos" and "Other"
    categorized['All photos'] = allImages; // Always show all images
    categorized['Other'] = unclassifiedImages;
    
    return categorized;
  }

  // Main classification method - tries all phases in order
  String? _classifyImage(String imageUrl) {
    // Phase 3: Check affiliate API metadata (highest priority)
    final affiliateCategory = _classifyFromAffiliateAPI(imageUrl);
    if (affiliateCategory != null) return affiliateCategory;
    
    // Phase 2: Check image content analysis cache/result
    final visionCategory = _classifyFromImageAnalysis(imageUrl);
    if (visionCategory != null) return visionCategory;
    
    // Phase 1: URL/Filename keyword analysis (active now)
    final urlCategory = _classifyFromURL(imageUrl);
    if (urlCategory != null) return urlCategory;
    
    // Phase 4: Return null (will be handled by fallback)
    return null;
  }

  // ============================================================================
  // PHASE 1: URL/FILENAME KEYWORD ANALYSIS (ACTIVE)
  // ============================================================================
  String? _classifyFromURL(String imageUrl) {
    if (imageUrl.isEmpty) return null;
    
    final urlLower = imageUrl.toLowerCase();
    
    // Guest photos keywords
    if (_containsAny(urlLower, ['guest', 'user', 'review', 'traveler', 'visitor'])) {
      return 'Guest photos';
    }
    
    // Rooms keywords
    if (_containsAny(urlLower, ['room', 'bedroom', 'suite', 'accommodation', 'sleeping'])) {
      return 'Rooms';
    }
    
    // Bathroom keywords
    if (_containsAny(urlLower, ['bathroom', 'bath', 'toilet', 'restroom', 'washroom', 'shower'])) {
      return 'Bathroom';
    }
    
    // Exterior keywords
    if (_containsAny(urlLower, ['exterior', 'outside', 'facade', 'building', 'outside', 'outdoor', 'entrance', 'front'])) {
      return 'Exterior';
    }
    
    // Amenities keywords
    if (_containsAny(urlLower, ['pool', 'gym', 'fitness', 'spa', 'amenity', 'amenities', 'facility', 'facilities', 'recreation'])) {
      return 'Amenities';
    }
    
    // Common areas keywords
    if (_containsAny(urlLower, ['lobby', 'reception', 'hall', 'common', 'corridor', 'hallway', 'lounge', 'foyer'])) {
      return 'Common areas';
    }
    
    // Dining keywords
    if (_containsAny(urlLower, ['dining', 'restaurant', 'food', 'meal', 'cafe', 'bar', 'breakfast', 'dinner', 'lunch', 'kitchen'])) {
      return 'Dining';
    }
    
    return null; // Not classified by URL
  }

  // Helper to check if string contains any of the keywords
  bool _containsAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  // ============================================================================
  // PHASE 2: IMAGE CONTENT ANALYSIS (READY FOR IMPLEMENTATION)
  // ============================================================================
  // Cache for image analysis results to avoid re-analyzing
  static final Map<String, String> _imageAnalysisCache = {};
  
  String? _classifyFromImageAnalysis(String imageUrl) {
    // Check cache first
    if (_imageAnalysisCache.containsKey(imageUrl)) {
      return _imageAnalysisCache[imageUrl];
    }
    
    // TODO: Phase 2 Implementation
    // When Google Cloud Vision API is integrated:
    // 1. Call Google Cloud Vision API to analyze image
    // 2. Get labels/annotations (e.g., "bed", "swimming pool", "restaurant")
    // 3. Map labels to categories using _mapVisionLabelsToCategory()
    // 4. Cache the result in _imageAnalysisCache
    // 5. Return the category
    
    // Example implementation structure:
    // try {
    //   final visionResult = await GoogleVisionAPI.analyzeImage(imageUrl);
    //   final labels = visionResult.labels; // e.g., ["bed", "furniture", "room"]
    //   final category = _mapVisionLabelsToCategory(labels);
    //   _imageAnalysisCache[imageUrl] = category;
    //   return category;
    // } catch (e) {
    //   print('Error analyzing image: $e');
    //   return null;
    // }
    
    return null; // Not implemented yet
  }

  // Helper to map Google Vision API labels to categories
  String? _mapVisionLabelsToCategory(List<String> labels) {
    final labelsLower = labels.map((l) => l.toLowerCase()).toList();
    
    // Guest photos - look for people, travelers, reviews
    if (_containsAnyInList(labelsLower, ['person', 'people', 'traveler', 'guest', 'tourist'])) {
      return 'Guest photos';
    }
    
    // Rooms - look for bed, bedroom, furniture
    if (_containsAnyInList(labelsLower, ['bed', 'bedroom', 'mattress', 'pillow', 'suite'])) {
      return 'Rooms';
    }
    
    // Bathroom - look for bathroom fixtures
    if (_containsAnyInList(labelsLower, ['bathroom', 'toilet', 'sink', 'shower', 'bathtub', 'bath'])) {
      return 'Bathroom';
    }
    
    // Exterior - look for building, architecture, outdoor
    if (_containsAnyInList(labelsLower, ['building', 'architecture', 'facade', 'exterior', 'outdoor', 'landscape'])) {
      return 'Exterior';
    }
    
    // Amenities - look for pool, gym, spa
    if (_containsAnyInList(labelsLower, ['swimming pool', 'pool', 'gym', 'fitness', 'spa', 'recreation'])) {
      return 'Amenities';
    }
    
    // Common areas - look for lobby, hall, corridor
    if (_containsAnyInList(labelsLower, ['lobby', 'hall', 'corridor', 'lounge', 'foyer', 'reception'])) {
      return 'Common areas';
    }
    
    // Dining - look for restaurant, food, dining table
    if (_containsAnyInList(labelsLower, ['restaurant', 'dining', 'food', 'table', 'cafe', 'bar', 'kitchen'])) {
      return 'Dining';
    }
    
    return null;
  }

  bool _containsAnyInList(List<String> list, List<String> keywords) {
    for (final keyword in keywords) {
      if (list.any((item) => item.contains(keyword))) return true;
    }
    return false;
  }

  // ============================================================================
  // PHASE 3: AFFILIATE API METADATA (READY FOR IMPLEMENTATION)
  // ============================================================================
  String? _classifyFromAffiliateAPI(String imageUrl) {
    // Get image metadata from hotel data structure
    final imageData = _getImageDataFromHotel(imageUrl);
    if (imageData == null) return null;
    
    // Check for direct category field (highest priority)
    final category = imageData['category']?.toString().toLowerCase();
    if (category != null && category.isNotEmpty) {
      return _normalizeCategory(category);
    }
    
    // Check for type field
    final type = imageData['type']?.toString().toLowerCase();
    if (type != null && type.isNotEmpty) {
      return _normalizeCategory(type);
    }
    
    // Check for tags array
    final tags = imageData['tags'];
    if (tags != null && tags is List) {
      final tagList = tags.map((t) => t.toString().toLowerCase()).toList();
      return _classifyFromTags(tagList);
    }
    
    return null;
  }

  // Get image metadata from hotel data structure
  Map<String, dynamic>? _getImageDataFromHotel(String imageUrl) {
    final dynamic imagesData = widget.hotel['images'];
    
    if (imagesData != null && imagesData is List) {
      for (final img in imagesData) {
        if (img is Map) {
          // Check if this image matches the URL
          final thumbnail = img['thumbnail']?.toString();
          final original = img['original_image']?.toString();
          
          if (thumbnail == imageUrl || original == imageUrl) {
            // Return the full image metadata object
            return Map<String, dynamic>.from(img);
          }
        }
      }
    }
    
    return null;
  }

  // Classify from tags array
  String? _classifyFromTags(List<String> tags) {
    for (final tag in tags) {
      final category = _classifyFromURL(tag); // Reuse URL classification logic
      if (category != null) return category;
    }
    return null;
  }

  // Normalize category name from API to our category names
  String? _normalizeCategory(String category) {
    final catLower = category.toLowerCase();
    
    if (_containsAny(catLower, ['guest', 'user', 'review'])) return 'Guest photos';
    if (_containsAny(catLower, ['room', 'bedroom', 'suite'])) return 'Rooms';
    if (_containsAny(catLower, ['bathroom', 'bath', 'toilet'])) return 'Bathroom';
    if (_containsAny(catLower, ['exterior', 'outside', 'facade', 'building'])) return 'Exterior';
    if (_containsAny(catLower, ['amenity', 'amenities', 'pool', 'gym', 'spa'])) return 'Amenities';
    if (_containsAny(catLower, ['lobby', 'common', 'hall', 'lounge'])) return 'Common areas';
    if (_containsAny(catLower, ['dining', 'restaurant', 'food', 'cafe'])) return 'Dining';
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final categorizedImages = _getCategorizedImages();
    final currentImages = categorizedImages[_selectedCategory] ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.hotel['name']?.toString() ?? 'Hotel Photos',
          style: AppTypography.title1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              // Menu action (if needed)
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Category tabs (horizontal scrollable)
          _buildCategoryTabs(categorizedImages),
          
          // Photo grid
          Expanded(
            child: currentImages.isEmpty
                ? Center(
                    child: Text(
                      'No photos available',
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : _buildPhotoGrid(currentImages),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(Map<String, List<String>> categorizedImages) {
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final count = categorizedImages[category]?.length ?? 0;
          final isSelected = _selectedCategory == category;
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = category;
              });
            },
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category preview image
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                        image: count > 0
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(
                                  categorizedImages[category]![0],
                                ),
                                fit: BoxFit.cover,
                                onError: (_, __) {},
                              )
                            : null,
                        color: count == 0 ? AppColors.surfaceVariant : null,
                      ),
                      child: count == 0
                          ? const Icon(
                              Icons.image_not_supported,
                              color: AppColors.textSecondary,
                              size: 32,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Category name
                  Text(
                    category,
                    style: AppTypography.caption.copyWith(
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoGrid(List<String> images) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            _openFullScreenViewer(images, index);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: images[index],
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: AppColors.surfaceVariant,
                child: const Icon(
                  Icons.broken_image,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFullScreenViewer(List<String> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenPhotoViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// Full screen photo viewer
class _FullScreenPhotoViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenPhotoViewer({
    Key? key,
    required this.images,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<_FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<_FullScreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

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
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        child: Stack(
          children: [
            // Photo viewer
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.images[index],
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            
            // Controls (top bar)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          '${_currentIndex + 1} / ${widget.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 48), // Balance the close button
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


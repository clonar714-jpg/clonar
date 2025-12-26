/**
 * ✅ PERPLEXITY-STYLE: Place Detail Screen
 * 
 * Displays detailed information about a place (attraction, destination, etc.)
 * Similar structure to ProductDetailScreen but adapted for places
 */

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../services/AgentService.dart';
import '../services/CacheService.dart';
import '../widgets/GoogleMapWidget.dart';

class PlaceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> place;

  const PlaceDetailScreen({
    super.key,
    required this.place,
  });

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  int _currentImageIndex = 0;
  
  // Dynamic place content
  String _whatPeopleSay = '';
  String _visitThisIf = '';
  List<String> _keyFeatures = [];
  List<String> _images = [];
  bool _isLoadingDetails = true;
  
  // Map coordinates
  double? _placeLatitude;
  double? _placeLongitude;

  @override
  void initState() {
    super.initState();
    _initializeImages();
    _loadPlaceDetails();
    _extractCoordinates();
  }
  
  void _initializeImages() {
    final imagesData = widget.place['images'];
    if (imagesData != null && imagesData is List) {
      _images = imagesData.map((img) => img.toString()).where((img) => img.isNotEmpty).toList();
    } else if (widget.place['thumbnail'] != null) {
      _images = [widget.place['thumbnail'].toString()];
    }
  }
  
  void _extractCoordinates() {
    final location = widget.place['location'];
    if (location is Map) {
      _placeLatitude = (location['lat'] as num?)?.toDouble();
      _placeLongitude = (location['lng'] as num?)?.toDouble();
    } else if (widget.place['latitude'] != null && widget.place['longitude'] != null) {
      _placeLatitude = (widget.place['latitude'] as num?)?.toDouble();
      _placeLongitude = (widget.place['longitude'] as num?)?.toDouble();
    }
  }
  
  Future<void> _loadPlaceDetails() async {
    try {
      setState(() {
        _isLoadingDetails = true;
      });
      
      // ✅ CACHE: Generate cache key from place name and address
      final placeName = widget.place['name']?.toString() ?? '';
      final placeAddress = widget.place['address']?.toString() ?? widget.place['location']?.toString() ?? '';
      final cacheKey = CacheService.generateCacheKey(
        'place-details-$placeName-$placeAddress',
      );
      
      // ✅ CACHE: Check cache first (place details change slowly, cache for 7 days)
      final cachedData = await CacheService.get(cacheKey);
      if (cachedData != null) {
        print('✅ Place details cache HIT for: $placeName');
        setState(() {
          _whatPeopleSay = cachedData['whatPeopleSay'] ?? 'Visitors appreciate this place for its unique characteristics and atmosphere.';
          _visitThisIf = cachedData['visitThisIf'] ?? 'This place is ideal for those seeking a memorable experience.';
          _keyFeatures = List<String>.from(cachedData['keyFeatures'] ?? []);
          if (cachedData['images'] != null) {
            _images = List<String>.from(cachedData['images'] ?? []);
          }
          _isLoadingDetails = false;
        });
        return;
      }
      
      print('❌ Place details cache MISS for: $placeName (fetching from API)');
      
      final url = Uri.parse('${AgentService.baseUrl}/api/product-details');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'domain': 'place', // ✅ NEW: Specify domain
          'id': widget.place['id']?.toString() ?? '',
          'title': widget.place['name']?.toString() ?? '',
          'description': widget.place['description']?.toString() ?? '',
          'address': widget.place['address']?.toString() ?? widget.place['location']?.toString() ?? '',
          'rating': widget.place['rating'],
          'link': widget.place['link']?.toString() ?? '',
          'location': widget.place['location'],
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // ✅ CACHE: Store response in cache (7 days expiry for place details)
        await CacheService.set(
          cacheKey,
          data,
          expiry: const Duration(days: 7),
          query: 'place-details',
        );
        print('💾 Cached place details for: $placeName');
        
        setState(() {
          _whatPeopleSay = data['whatPeopleSay'] ?? 'Visitors appreciate this place for its unique characteristics and atmosphere.';
          _visitThisIf = data['visitThisIf'] ?? 'This place is ideal for those seeking a memorable experience.';
          _keyFeatures = List<String>.from(data['keyFeatures'] ?? []);
          if (data['images'] != null) {
            final additionalImages = List<String>.from(data['images'] ?? []);
            _images = [..._images, ...additionalImages].toSet().toList(); // Merge and deduplicate
          }
          _isLoadingDetails = false;
        });
      } else {
        _setFallbackContent();
      }
    } catch (e) {
      print('Error loading place details: $e');
      _setFallbackContent();
    }
  }
  
  void _setFallbackContent() {
    setState(() {
      _whatPeopleSay = 'Visitors appreciate this place for its unique characteristics and atmosphere. Many reviewers mention the beautiful setting and memorable experience.';
      _visitThisIf = 'You want to experience a unique and memorable destination. Ideal for those seeking adventure, culture, or natural beauty.';
      _keyFeatures = ['Unique atmosphere', 'Memorable experience', 'Beautiful setting', 'Worth visiting'];
      _isLoadingDetails = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Main content
          CustomScrollView(
            slivers: [
              // Image carousel
              SliverToBoxAdapter(
                child: _buildImageCarousel(),
              ),
              
              // Place info
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPlaceInfo(),
                      const SizedBox(height: 24),
                      
                      // "Visit this if" section
                      if (!_isLoadingDetails) _buildVisitThisIfSection(),
                      if (!_isLoadingDetails) const SizedBox(height: 24),
                      
                      // "What people say" section
                      if (!_isLoadingDetails) _buildWhatPeopleSaySection(),
                      if (!_isLoadingDetails) const SizedBox(height: 24),
                      
                      // Key features
                      if (!_isLoadingDetails) _buildKeyFeatures(),
                      
                      // Map view (if coordinates available)
                      if (_placeLatitude != null && _placeLongitude != null) ...[
                        const SizedBox(height: 24),
                        _buildMapView(),
                      ],
                      
                      const SizedBox(height: 100), // Space for fixed bottom buttons
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Fixed close button at the top
          _buildFixedTopButtons(),
        ],
      ),
      bottomNavigationBar: _buildBottomButtons(),
    );
  }

  Widget _buildFixedTopButtons() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 24),
                  onPressed: () => Navigator.pop(context),
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageCarousel() {
    if (_images.isEmpty) {
      return SizedBox(
        height: 300,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surfaceVariant,
          ),
          child: const Center(
            child: Icon(
              Icons.image_not_supported,
              color: AppColors.textSecondary,
              size: 60,
            ),
          ),
        ),
      );
    }

    final hasMultipleImages = _images.length > 1;

    return Stack(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: PageController(),
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceVariant,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: _images[index],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(
                        Icons.image,
                        color: AppColors.textSecondary,
                        size: 60,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Page indicator
        if (hasMultipleImages)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _images.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceInfo() {
    final name = widget.place['name']?.toString() ?? 'Unknown Place';
    final address = widget.place['address']?.toString() ?? widget.place['location']?.toString() ?? '';
    final rating = widget.place['rating'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: AppTypography.title1.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  address,
                  style: AppTypography.body1.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (rating != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 4),
              Text(
                rating.toString(),
                style: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVisitThisIfSection() {
    if (_visitThisIf.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visit this if',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _visitThisIf,
          style: AppTypography.body1.copyWith(
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildWhatPeopleSaySection() {
    if (_whatPeopleSay.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What people say',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _whatPeopleSay,
          style: AppTypography.body1.copyWith(
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildKeyFeatures() {
    if (_keyFeatures.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key features',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _keyFeatures.map((feature) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.surfaceVariant, width: 1),
              ),
              child: Text(
                feature,
                style: AppTypography.body2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMapView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GoogleMapWidget(
              latitude: _placeLatitude!,
              longitude: _placeLongitude!,
              title: widget.place['name']?.toString() ?? 'Place',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  // Open in maps app
                  final link = widget.place['link']?.toString() ?? '';
                  if (link.isNotEmpty) {
                    // Launch URL
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Get Directions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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


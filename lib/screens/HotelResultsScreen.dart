import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../services/ApiService.dart';
import 'HotelDetailScreen.dart';

class HotelResultsScreen extends StatefulWidget {
  final String query;

  const HotelResultsScreen({
    Key? key,
    required this.query,
  }) : super(key: key);

  @override
  State<HotelResultsScreen> createState() => _HotelResultsScreenState();
}

class _HotelResultsScreenState extends State<HotelResultsScreen> {
  List<Map<String, dynamic>> _hotels = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHotels();
  }

  Future<void> _loadHotels() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Call the real API
      final apiResponse = await ApiService.search(widget.query);
      final resultType = apiResponse['type'] ?? 'hotel';
      final results = apiResponse['results'] ?? [];

      if (resultType == 'hotel') {
        final List<Map<String, dynamic>> hotelResults = results.cast<Map<String, dynamic>>();
        setState(() {
          _hotels = hotelResults;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hotels = [];
          _isLoading = false;
          _error = 'No hotel results found';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load hotels: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          'Hotels',
          style: AppTypography.title1.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: AppTypography.body1.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadHotels,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _hotels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.hotel_outlined,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No hotels found',
                            style: AppTypography.title2.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: AppTypography.body1.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _hotels.length,
                      itemBuilder: (context, index) {
                        final hotel = _hotels[index];
                        return _buildHotelCard(hotel, index);
                      },
                    ),
    );
  }

  Widget _buildHotelCard(Map<String, dynamic> hotel, int index) {
    // Safe data extraction
    String safeString(dynamic value, String fallback) {
      if (value == null) return fallback;
      final str = value.toString().trim();
      return str.isEmpty ? fallback : str;
    }

    double safeNumber(dynamic value, double fallback) {
      if (value == null) return fallback;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      final str = value.toString().trim();
      if (str.isEmpty) return fallback;
      return double.tryParse(str) ?? fallback;
    }

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

    // Handle images - properly extract from images array
    List<String> getImages() {
      final images = hotel['images'];
      if (images != null && images is List && images.isNotEmpty) {
        // Extract all image URLs from the images array
        final imageUrls = <String>[];
        for (final img in images) {
          if (img is String && img.isNotEmpty) {
            imageUrls.add(img);
          } else if (img is Map && img['thumbnail'] != null) {
            final thumbnail = img['thumbnail'].toString();
            if (thumbnail.isNotEmpty) {
              imageUrls.add(thumbnail);
            }
          }
        }
        if (imageUrls.isNotEmpty) {
          return imageUrls;
        }
      }
      
      // Fallback to thumbnail if available
      final thumbnail = hotel['thumbnail'];
      if (thumbnail != null && thumbnail.toString().isNotEmpty) {
        return [thumbnail.toString()];
      }
      return <String>[];
    }

    final name = safeString(hotel['name'], 'Unknown Hotel');
    final location = safeString(hotel['address'], 'Location not specified');
    final rating = safeNumber(hotel['rating'], 0.0);
    final reviewCount = safeInt(hotel['reviews'], 0);
    final price = safeNumber(hotel['price'], 0.0);
    final description = safeString(hotel['description'], 'No description available');
    final amenities = safeAmenities(hotel['amenities']);
    final images = getImages();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.surfaceVariant,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToHotelDetail(hotel),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hotel Image
            ...(images.isNotEmpty ? [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  images[0],
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: Icon(
                          Icons.hotel,
                          color: AppColors.textSecondary,
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] : [
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
            ]),
            
            // Hotel Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hotel name and location
                  Text(
                    name,
                    style: AppTypography.title1.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location,
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Rating and price
                  Row(
                    children: [
                      if (rating > 0) ...[
                        const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$rating',
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
                  
                  const SizedBox(height: 8),
                  
                  // Description or Amenities
                  if (description != 'No description available')
                    Text(
                      description,
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (amenities.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Amenities:',
                          style: AppTypography.body1.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: amenities.take(4).map<Widget>((amenity) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                amenity,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    )
                  else
                    Text(
                      'No additional information available',
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
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

  void _navigateToHotelDetail(Map<String, dynamic> hotel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HotelDetailScreen(hotel: hotel),
      ),
    );
  }
}
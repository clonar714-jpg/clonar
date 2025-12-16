import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import 'RoomDetailsScreen.dart';
import 'rooms_page.dart';
import '../services/AgentService.dart';
import '../widgets/GoogleMapWidget.dart';
import '../services/GeocodingService.dart';
import '../services/CacheService.dart';
import 'FullScreenMapScreen.dart';
import 'HotelPhotoGalleryScreen.dart';

// ✅ FIX 1: Isolate function for JSON decoding (must be top-level for compute())
Map<String, dynamic> _jsonDecodeIsolate(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

class HotelDetailScreen extends StatefulWidget {
  final Map<String, dynamic> hotel;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final int? guestCount;
  final int? roomCount;

  const HotelDetailScreen({
    Key? key,
    required this.hotel,
    this.checkInDate,
    this.checkOutDate,
    this.guestCount,
    this.roomCount,
  }) : super(key: key);

  @override
  State<HotelDetailScreen> createState() => _HotelDetailScreenState();
}

class _HotelDetailScreenState extends State<HotelDetailScreen> {
  late PageController _imagePageController;
  int _currentImageIndex = 0;
  final ScrollController _scrollController = ScrollController();
  bool _showBottomButton = true;
  String _selectedCheckIn = '';
  String _selectedCheckOut = '';
  int _adultCount = 2;
  int _kidsCount = 0;
  final GlobalKey _roomsSectionKey = GlobalKey();
  bool _isDescriptionExpanded = false;

  // Dynamic hotel content
  String _whatPeopleSay = '';
  String _reviewSummary = '';
  String _chooseThisIf = '';
  String _about = '';
  String _locationSummary = '';
  String _ratingInsights = '';
  List<String> _amenitiesClean = [];
  bool _isLoadingContent = true;
  
  // Map coordinates
  double? _hotelLatitude;
  double? _hotelLongitude;
  bool _isLoadingCoordinates = false;
  
  // ✅ FIX 3: Cache hotel images once in initState (prevents rebuild cost)
  late final List<String> _hotelImages;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _scrollController.addListener(_onScroll);
    
    // ✅ FIX 3: Extract hotel images once in initState (prevents rebuild cost)
    _hotelImages = _extractHotelImages();
    
    // Initialize with dates and travelers from TravelScreen if provided, otherwise use defaults
    if (widget.checkInDate != null && widget.checkOutDate != null) {
      _selectedCheckIn = '${_getMonthName(widget.checkInDate!.month)} ${widget.checkInDate!.day}';
      _selectedCheckOut = '${_getMonthName(widget.checkOutDate!.month)} ${widget.checkOutDate!.day}';
    } else {
      // Initialize with today's date and tomorrow's date
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      
      _selectedCheckIn = '${_getMonthName(today.month)} ${today.day}';
      _selectedCheckOut = '${_getMonthName(tomorrow.month)} ${tomorrow.day}';
    }
    
    // Set guest count if provided
    if (widget.guestCount != null) {
      _adultCount = widget.guestCount!;
      _kidsCount = 0; // Default to 0 kids if not specified
    }
    
    // Load dynamic "What people say" content
    _loadHotelDetails();
    _loadHotelCoordinates();
  }
  
  // ✅ FIX 3: Extract hotel images once (called from initState)
  List<String> _extractHotelImages() {
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
  
  Future<void> _loadHotelDetails() async {
    try {
      if (!mounted) return; // ✅ PRODUCTION: Check mounted before setState
      setState(() {
        _isLoadingContent = true;
      });
      
      // ✅ CACHE: Generate cache key from hotel name and location
      final hotelName = widget.hotel['name']?.toString() ?? '';
      final hotelLocation = widget.hotel['location']?.toString() ?? widget.hotel['address']?.toString() ?? '';
      final cacheKey = CacheService.generateCacheKey(
        'hotel-details-$hotelName-$hotelLocation',
      );
      
      // ✅ CACHE: Check cache first (hotel details change slowly, cache for 7 days)
      final cachedData = await CacheService.get(cacheKey);
      if (cachedData != null) {
        print('✅ Hotel details cache HIT for: $hotelName');
        
        // ✅ FIX 2: Process amenities BEFORE setState (prevents blocking rebuild)
        final amenities = (cachedData['amenitiesClean'] as List<dynamic>?)
            ?.map((a) => a.toString())
            .toList() ?? 
            (widget.hotel['amenities'] as List<dynamic>?)
                ?.map((a) => a.toString())
                .toList() ?? [];
        
        if (!mounted) return; // ✅ PRODUCTION: Check mounted before setState
        setState(() {
          _whatPeopleSay = cachedData['whatPeopleSay'] ?? _getFallbackWhatPeopleSay();
          _reviewSummary = cachedData['reviewSummary'] ?? '';
          _chooseThisIf = cachedData['chooseThisIf'] ?? _getChooseThisIfText();
          _about = cachedData['about'] ?? _getAboutText();
          _locationSummary = cachedData['locationSummary'] ?? '';
          _ratingInsights = cachedData['ratingInsights'] ?? '';
          _amenitiesClean = amenities; // ✅ FIX 2: Use pre-processed amenities
          _isLoadingContent = false;
        });
        return; // Use cached data, skip API call
      }
      
      print('❌ Hotel details cache MISS for: $hotelName (fetching from API)');
      
      final url = Uri.parse('${AgentService.baseUrl}/api/hotel-details');
      
      // Build comprehensive hotel data object - auto-adapts to any fields present
      // This works with minimal SerpAPI data and automatically uses richer data when available
      final Map<String, dynamic> hotelData = {
        'name': widget.hotel['name'] ?? '',
        'location': widget.hotel['location'],
        'address': widget.hotel['address'],
        'rating': widget.hotel['rating'],
        'reviewCount': widget.hotel['reviewCount'],
        'description': widget.hotel['description'],
        'amenities': widget.hotel['amenities'],
        'nearby': widget.hotel['nearby'],
        // Rating breakdowns (if available from any source)
        'cleanliness': widget.hotel['cleanliness'] ?? widget.hotel['cleanliness_rating'],
        'rooms': widget.hotel['rooms'] ?? widget.hotel['rooms_rating'],
        'service': widget.hotel['service'] ?? widget.hotel['service_rating'],
        'sleepQuality': widget.hotel['sleepQuality'] ?? widget.hotel['sleep_quality'],
        'value': widget.hotel['value'] ?? widget.hotel['value_rating'],
        'locationRating': widget.hotel['locationRating'] ?? widget.hotel['location_rating'],
        // Future-proof: Include any additional fields that might be present
        // The AI will automatically use them if they appear
        if (widget.hotel['reviews'] != null) 'reviews': widget.hotel['reviews'],
        if (widget.hotel['review_snippets'] != null) 'review_snippets': widget.hotel['review_snippets'],
        if (widget.hotel['ratings_breakdown'] != null) 'ratings_breakdown': widget.hotel['ratings_breakdown'],
        if (widget.hotel['airport_distance'] != null) 'airport_distance': widget.hotel['airport_distance'],
        if (widget.hotel['nearby_places'] != null) 'nearby_places': widget.hotel['nearby_places'],
        if (widget.hotel['hotel_class'] != null) 'hotel_class': widget.hotel['hotel_class'],
        if (widget.hotel['tags'] != null) 'tags': widget.hotel['tags'],
        if (widget.hotel['geo'] != null) 'geo': widget.hotel['geo'],
        if (widget.hotel['gps_coordinates'] != null) 'gps_coordinates': widget.hotel['gps_coordinates'],
        if (widget.hotel['latitude'] != null) 'latitude': widget.hotel['latitude'],
        if (widget.hotel['longitude'] != null) 'longitude': widget.hotel['longitude'],
      };
      
      // Remove null/empty values to keep payload clean
      hotelData.removeWhere((key, value) => value == null || value == '' || (value is List && value.isEmpty));
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(hotelData),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        // ✅ FIX 1: Move JSON parsing to isolate (prevents 300-800ms UI freeze)
        final data = await compute(_jsonDecodeIsolate, response.body);
        
        // ✅ CACHE: Store response in cache (7 days expiry for hotel details)
        await CacheService.set(
          cacheKey,
          data,
          expiry: const Duration(days: 7),
          query: 'hotel-details', // Mark as hotel details for logging
        );
        print('💾 Cached hotel details for: $hotelName');
        
        // ✅ FIX 2: Process amenities BEFORE setState (prevents blocking rebuild)
        final amenities = (data['amenitiesClean'] as List<dynamic>?)
            ?.map((a) => a.toString())
            .toList() ?? 
            (widget.hotel['amenities'] as List<dynamic>?)
                ?.map((a) => a.toString())
                .toList() ?? [];
        
        if (!mounted) return; // ✅ PRODUCTION: Check mounted before setState
        setState(() {
          _whatPeopleSay = data['whatPeopleSay'] ?? _getFallbackWhatPeopleSay();
          _reviewSummary = data['reviewSummary'] ?? '';
          _chooseThisIf = data['chooseThisIf'] ?? _getChooseThisIfText();
          _about = data['about'] ?? _getAboutText();
          _locationSummary = data['locationSummary'] ?? '';
          _ratingInsights = data['ratingInsights'] ?? '';
          _amenitiesClean = amenities; // ✅ FIX 2: Use pre-processed amenities
          _isLoadingContent = false;
        });
      } else {
        _setFallbackContent();
      }
    } catch (e) {
      print('Error loading hotel details: $e');
      _setFallbackContent();
    }
  }
  
  void _setFallbackContent() {
    // ✅ FIX 2: Process amenities BEFORE setState (prevents blocking rebuild)
    final amenities = (widget.hotel['amenities'] as List<dynamic>?)
        ?.map((a) => a.toString())
        .toList() ?? [];
    
    if (!mounted) return; // ✅ PRODUCTION: Check mounted before setState
    setState(() {
      _whatPeopleSay = _getFallbackWhatPeopleSay();
      _reviewSummary = '';
      _chooseThisIf = _getChooseThisIfText();
      _about = _getAboutText();
      _locationSummary = '';
      _ratingInsights = '';
      _amenitiesClean = amenities; // ✅ FIX 2: Use pre-processed amenities
      _isLoadingContent = false;
    });
  }
  
  String _getFallbackWhatPeopleSay() {
    final name = widget.hotel['name'] ?? 'this hotel';
    final location = widget.hotel['location'] ?? '';
    final rating = _safeDouble(widget.hotel['rating'], 0.0);
    
    final locationText = location.isNotEmpty && location != 'Location not specified' ? ' in $location' : '';
    final ratingText = rating >= 4.5 
        ? "highly rated" 
        : rating >= 4.0 
        ? "well-rated" 
        : "popular";
    
    return '$name$locationText is $ratingText among guests, with many reviewers praising the comfortable accommodations, convenient location, and quality service. Guests appreciate the modern amenities and friendly staff. Some visitors mention minor areas for improvement, but overall satisfaction remains high.';
  }

  // Helper function to safely convert dynamic values to double
  double _safeDouble(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    final str = value.toString().trim();
    if (str.isEmpty) return fallback;
    return double.tryParse(str) ?? fallback;
  }

  // Helper function to safely convert dynamic values to int
  int _safeInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    final str = value.toString().trim();
    if (str.isEmpty) return fallback;
    return int.tryParse(str) ?? fallback;
  }

  void _onScroll() {
    // Hide button when scrolling to rooms section
    final RenderBox? roomsBox = _roomsSectionKey.currentContext?.findRenderObject() as RenderBox?;
    if (roomsBox != null) {
      final roomsPosition = roomsBox.localToGlobal(Offset.zero).dy;
      final screenHeight = MediaQuery.of(context).size.height;
      
      final shouldShowButton = roomsPosition > screenHeight * 0.3;
      
      if (shouldShowButton != _showBottomButton) {
        setState(() {
          _showBottomButton = shouldShowButton;
        });
      }
    }
  }

  // Helper method to get rating from hotel data
  double _getRating(String category) {
    // Try to get specific rating from hotel data
    final rating = widget.hotel[category] ?? widget.hotel['${category}_rating']; // ✅ null-safe
    if (rating != null) {
      if (rating is double) return rating;
      if (rating is int) return rating.toDouble();
      final parsed = double.tryParse(rating.toString());
      if (parsed != null) return parsed;
    }
    
    // Fallback to overall rating with slight variation
    final overallRating = widget.hotel['rating'] ?? widget.hotel['overall_rating'];
    if (overallRating != null) {
      final baseRating = overallRating is double ? overallRating : 
                        overallRating is int ? overallRating.toDouble() : 
                        double.tryParse(overallRating.toString()) ?? 4.0;
      // Add slight variation based on category
      final variations = {
        'cleanliness': 0.1,
        'location': 0.0,
        'service': -0.1,
        'sleep_quality': 0.2,
        'rooms': -0.2,
        'value': -0.3,
      };
      return (baseRating + (variations[category] ?? 0.0)).clamp(1.0, 5.0);
    }
    
    // Default fallback
    return 4.0;
  }

  // Helper methods for room data
  String _getRoomName() {
    // Try to get room type from hotel data
    final roomType = widget.hotel['room_type'] ?? widget.hotel['room_name'];
    if (roomType != null && roomType.toString().isNotEmpty) {
      return roomType.toString();
    }
    
    // Try to extract from amenities or features
    final amenities = widget.hotel['amenities'] ?? [];
    if (amenities is List) {
      for (final amenity in amenities) {
        final amenityStr = amenity.toString().toLowerCase();
        if (amenityStr.contains('king') || amenityStr.contains('queen') || 
            amenityStr.contains('double') || amenityStr.contains('twin')) {
          return '${amenityStr.split(' ').first.toUpperCase()}${amenityStr.split(' ').skip(1).join(' ')} Room'; // ✅ null-safe
        }
      }
    }
    
    return 'Standard Room';
  }

  String _getRoomPrice() {
    final price = widget.hotel['price'] ?? widget.hotel['rate_per_night'];
    if (price != null) {
      final priceValue = price is double ? price : 
                        price is int ? price.toDouble() : 
                        double.tryParse(price.toString());
      if (priceValue != null) {
        return '\$${priceValue.toStringAsFixed(0)} per night'; // ✅ null-safe
      }
    }
    return '\$169 per night';
  }

  String _getTotalPrice() {
    final price = widget.hotel['price'] ?? widget.hotel['rate_per_night'];
    if (price != null) {
      final priceValue = price is double ? price : 
                        price is int ? price.toDouble() : 
                        double.tryParse(price.toString());
      if (priceValue != null) {
        final totalWithTaxes = (priceValue * 1.15).toStringAsFixed(2);
        return '\$$totalWithTaxes including taxes + fees';
      }
    }
    return '\$195.40 including taxes + fees';
  }

  String _getBedType() {
    // Try to get bed type from amenities
    final amenities = widget.hotel['amenities'] ?? [];
    if (amenities is List) {
      for (final amenity in amenities) {
        final amenityStr = amenity.toString().toLowerCase();
        if (amenityStr.contains('king bed')) return '1 King Bed';
        if (amenityStr.contains('queen bed')) return '1 Queen Bed';
        if (amenityStr.contains('double bed')) return '1 Double Bed';
        if (amenityStr.contains('twin bed')) return '2 Twin Beds';
      }
    }
    
    // Try to get from room features
    final features = widget.hotel['features'] ?? [];
    if (features is List) {
      for (final feature in features) {
        final featureStr = feature.toString().toLowerCase();
        if (featureStr.contains('king') || featureStr.contains('queen') || 
            featureStr.contains('double') || featureStr.contains('twin')) {
          return featureStr;
        }
      }
    }
    
    return '1 King Bed';
  }

  // Helper method to get room price as a number
  double _getRoomPriceValue() {
    final price = widget.hotel['price'] ?? widget.hotel['rate_per_night'];
    if (price != null) {
      final priceValue = price is double ? price : 
                        price is int ? price.toDouble() : 
                        double.tryParse(price.toString());
      if (priceValue != null) {
        return priceValue;
      }
    }
    return 169.0;
  }

  // Helper method to get month name
  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  void _showDateGuestModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DateGuestModal(
        selectedCheckIn: _selectedCheckIn,
        selectedCheckOut: _selectedCheckOut,
        adultCount: _adultCount,
        kidsCount: _kidsCount,
        onCheckInChanged: (value) => setState(() => _selectedCheckIn = value),
        onCheckOutChanged: (value) => setState(() => _selectedCheckOut = value),
        onAdultCountChanged: (value) => setState(() => _adultCount = value),
        onKidsCountChanged: (value) => setState(() => _kidsCount = value),
      ),
    );
  }




  void _navigateToRoomDetails(Map<String, dynamic> room) {
    // Use the room data passed from the room card
    final roomData = {
      'name': room['name'],
      'price': room['price'],
      'images': [room['image']], // Use the specific room image
      'features': room['features'],
    };
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RoomDetailsScreen(
          room: roomData,
          hotel: widget.hotel,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background like Perplexity
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 80), // Add padding for fixed button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hotel image carousel (larger, takes up more space)
                _buildImageCarousel(),
                
                // Hotel basic info (on dark background)
                _buildHotelInfo(),
                
                // Action buttons
                _buildActionButtons(),
                
                // What people say (Reviews)
                _buildWhatPeopleSay(),
                
                // Review Summary (if available)
                if (_reviewSummary.isNotEmpty) _buildReviewSummary(),
                
                // Choose this if
                _buildChooseThisIf(),
                
                // About
                _buildAbout(),
                
                // Amenities
                _buildAmenities(),
                
                // Location
                _buildLocation(),
                
                // Location Summary (if available)
                if (_locationSummary.isNotEmpty) _buildLocationSummary(),
                
                // Traveler insights
                _buildTravelerInsights(),
                
                // Rating Insights (if available)
                if (_ratingInsights.isNotEmpty) _buildRatingInsights(),
                
                // Rooms section
                _buildRoomsSection(),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Back button (always visible, matches original close button style)
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildSimpleActionButton('Call', Icons.phone, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Calling hotel...')),
              );
            }),
          ),
          const SizedBox(width: 10), // Tighter spacing like Perplexity
          Expanded(
            child: _buildSimpleActionButton('Website', Icons.language, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening hotel website...')),
              );
            }),
          ),
          const SizedBox(width: 10), // Tighter spacing like Perplexity
          Expanded(
            child: _buildSimpleActionButton('Directions', Icons.directions, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening directions...')),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[850], // Slightly lighter for better contrast (Perplexity style)
          borderRadius: BorderRadius.circular(12), // More rounded like Perplexity
          border: Border.all(
            color: Colors.grey[700]!.withOpacity(0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18, // Slightly smaller icon to save space
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
              label,
                style: const TextStyle(
                  color: Colors.white,
                fontWeight: FontWeight.w500,
                  fontSize: 14, // Slightly smaller text
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    Color textColor = AppColors.textPrimary,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          splashFactory: InkRipple.splashFactory,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceVariant),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: Add to Wishlist and Add to Groups
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.favorite_border,
                      label: 'Add to Wishlist',
                      backgroundColor: AppColors.surfaceVariant,
                      textColor: AppColors.textPrimary,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Added to Wishlist!')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.group_add,
                      label: 'Add to Groups',
                      backgroundColor: AppColors.surfaceVariant,
                      textColor: AppColors.textPrimary,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Added to Groups!')),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row 2: Find a room and In-App Reviews
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.bed,
                      label: 'Find a room',
                      backgroundColor: AppColors.accent,
                      textColor: Colors.white,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Redirecting to booking...')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.rate_review,
                      label: 'In-App Reviews',
                      backgroundColor: AppColors.surfaceVariant,
                      textColor: AppColors.textPrimary,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reviews opened!')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPhotoGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HotelPhotoGalleryScreen(hotel: widget.hotel),
      ),
    );
  }

  Widget _buildImageCarousel() {
    // ✅ FIX 3: Use cached images from initState (zero rebuild cost)
    final images = _hotelImages;
    
    // If no images, show a placeholder
    if (images.isEmpty) {
      return SizedBox(
        height: 400, // Larger height like Perplexity
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[900],
          ),
          child: const Icon(
            Icons.hotel,
            color: Colors.white70,
            size: 64,
          ),
        ),
      );
    }
    
    return SizedBox(
      height: 400, // Larger height like Perplexity (was 250)
      child: Stack(
        children: [
          PageView.builder(
            controller: _imagePageController,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemCount: images.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  _openPhotoGallery();
                },
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: images[index],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.hotel,
                          color: AppColors.textSecondary,
                          size: 64,
                        ),
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Image indicators at bottom center
          if (images.length > 1)
            Positioned(
              bottom: 60, // Position above the photo count badge
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentImageIndex == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
          
          // Photo count badge at bottom right (like reference screenshot)
          Positioned(
            bottom: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _openPhotoGallery();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B4513), // Brown color like in screenshot
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
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
    );
  }

  Widget _buildHotelInfo() {
    // Pre-calculate values safely to avoid type cast errors
    final rating = _safeDouble(widget.hotel['rating'], 0.0);
    final reviewCount = _safeInt(widget.hotel['reviewCount'], 0);
    final originalPrice = _safeDouble(widget.hotel['originalPrice'], 0.0);
    final price = _safeDouble(widget.hotel['price'], 0.0);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hotel name (white text on dark background)
          Text(
            widget.hotel['name'] ?? 'Hotel Name',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          
          // Rating and reviews (white text on dark background)
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                '${rating.toStringAsFixed(1)}',
                style: const TextStyle(
                          fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                '($reviewCount reviews)',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // TripAdvisor icon
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Icon(
                          Icons.pets,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTravelerInsights() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Traveler insights',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Overall rating
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${_safeDouble(widget.hotel['rating'], 0.0).toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 32,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Good',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_safeInt(widget.hotel['reviewCount'], 0)} reviews',
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        decoration: TextDecoration.underline,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      Icons.star,
                      color: index < _safeDouble(widget.hotel['rating'], 0.0).floor()
                          ? Colors.tealAccent
                          : Colors.grey[700]!,
                      size: 20,
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Individual ratings - use real data from hotel
          _buildRatingBar('Cleanliness', _getRating('cleanliness')),
          _buildRatingBar('Location', _getRating('location')),
          _buildRatingBar('Service', _getRating('service')),
          _buildRatingBar('Sleep Quality', _getRating('sleep_quality')),
          _buildRatingBar('Rooms', _getRating('rooms')),
          _buildRatingBar('Value', _getRating('value')),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRatingBar(String label, double rating) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: rating / 5.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.tealAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsSection() {
    // ✅ Generate hotel ID from hotel data
    final hotelId = widget.hotel['id']?.toString() ?? 
                    widget.hotel['property_token']?.toString() ??
                    widget.hotel['name']?.toString().replaceAll(' ', '-').toLowerCase() ??
                    'hotel';
    final hotelName = widget.hotel['name']?.toString() ?? 'Hotel';

    // Parse dates from selected strings (format: "MMM d")
    DateTime? checkInDate;
    DateTime? checkOutDate;
    try {
      final today = DateTime.now();
      final checkInParts = _selectedCheckIn.split(' ');
      if (checkInParts.length >= 2) {
        final monthName = checkInParts[0];
        final day = int.tryParse(checkInParts[1]) ?? today.day;
        final month = _getMonthNumber(monthName);
        if (month > 0) {
          checkInDate = DateTime(today.year, month, day);
          // Ensure check-in is not in the past
          if (checkInDate.isBefore(today)) {
            checkInDate = today;
          }
          checkOutDate = checkInDate.add(const Duration(days: 1));
        } else {
          checkInDate = today;
          checkOutDate = checkInDate.add(const Duration(days: 1));
        }
      } else {
        checkInDate = today;
        checkOutDate = checkInDate.add(const Duration(days: 1));
      }
    } catch (e) {
      checkInDate = DateTime.now();
      checkOutDate = checkInDate.add(const Duration(days: 1));
    }

    return Padding(
      key: _roomsSectionKey,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Rooms',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // ✅ Date and guest selector (navigates to RoomsPage)
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RoomsPage(
                    hotelId: hotelId,
                    hotelName: hotelName,
                    initialCheckIn: checkInDate,
                    initialCheckOut: checkOutDate,
                    initialGuests: _adultCount + _kidsCount,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    '$_selectedCheckIn - $_selectedCheckOut',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.people, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    _buildGuestText(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'powered by Selfbook',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _buildGuestText() {
    final totalGuests = _adultCount + _kidsCount;
    if (widget.roomCount != null && widget.roomCount! > 1) {
      return '$totalGuests guests, ${widget.roomCount} rooms';
    } else if (totalGuests == 1) {
      return '1 guest';
    } else {
      return '$totalGuests guests';
    }
  }

  int _getMonthNumber(String monthName) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months.indexWhere((m) => m.toLowerCase() == monthName.toLowerCase()) + 1;
  }

  Widget _buildAvailableRooms() {
    // Generate different room types based on hotel data
    final List<Map<String, dynamic>> availableRooms = _getAvailableRoomTypes();
    
    return Column(
      children: availableRooms.map((room) => _buildRoomCard(room)).toList(),
    );
  }

  List<Map<String, dynamic>> _getAvailableRoomTypes() {
    // Use real room data from the hotel API response
    final basePrice = _getRoomPriceValue();
    final roomInteriorImages = _getRoomInteriorImages();
    final dynamic roomTypesData = widget.hotel['room_types'];
    
    List<Map<String, dynamic>> rooms = [];
    
    if (roomTypesData != null && roomTypesData is List && roomTypesData.isNotEmpty) {
      // Use real room data from API
      for (int i = 0; i < roomTypesData.length; i++) {
        final roomData = roomTypesData[i];
        final roomType = roomData['room_type'] ?? 'Room';
        final bedCount = roomData['bed_count'] ?? '';
        final sleeps = roomData['sleeps'] ?? '';
        final bathrooms = roomData['bathrooms'] ?? '';
        final size = roomData['size'] ?? '';
        
        // Create room name from available data
        String roomName = roomType;
        if (bedCount.isNotEmpty) {
          roomName += ' - $bedCount';
        }
        
        // Create bed type description
        String bedType = bedCount.isNotEmpty ? bedCount : 'Standard bed';
        if (sleeps.isNotEmpty) {
          bedType += ' ($sleeps)';
        }
        
        // Create features list from room data
        List<String> features = [];
        if (bathrooms.isNotEmpty) features.add(bathrooms);
        if (size.isNotEmpty) features.add(size);
        features.addAll(['Air conditioning', 'TV', 'Free WiFi', 'Private bathroom']);
        
        // Use appropriate room interior image based on room type
        String roomImage;
        if (roomInteriorImages.isNotEmpty) {
          // Select image based on room characteristics
          if (bedType.toLowerCase().contains('king') || roomType.toLowerCase().contains('suite')) {
            roomImage = roomInteriorImages[0]; // King bed room
          } else if (bedType.toLowerCase().contains('queen') || bedType.toLowerCase().contains('double')) {
            roomImage = roomInteriorImages[1]; // Queen bed room
          } else if (roomType.toLowerCase().contains('apartment') || roomType.toLowerCase().contains('entire')) {
            roomImage = roomInteriorImages[2]; // Suite/apartment
          } else {
            roomImage = roomInteriorImages[i % roomInteriorImages.length];
          }
        } else {
          roomImage = 'https://images.unsplash.com/photo-1566665797739-1674de7a421a?w=400&h=200&fit=crop&q=80';
        }
        
        rooms.add({
          'name': roomName,
          'bedType': bedType,
          'price': basePrice * (1.0 + (i * 0.1)), // Slight price variation
          'image': roomImage,
          'features': features,
        });
      }
    } else {
      // Fallback to generic room types if no real data available
      // Always use proper room interior images, never hotel exterior images
      rooms.add({
        'name': 'Standard Room',
        'bedType': '1 King Bed',
        'price': basePrice,
        'image': 'https://images.unsplash.com/photo-1566665797739-1674de7a421a?w=400&h=200&fit=crop&q=80', // King bed room interior
        'features': ['King bed', 'Private bathroom', 'Air conditioning', 'TV', 'Free WiFi', 'Desk', 'Safe', 'Coffee maker'],
      });
    }
    
    return rooms;
  }

  List<String> _getRoomInteriorImages() {
    // SerpAPI does NOT provide room-specific interior images
    // It only provides hotel exterior/lobby images which are NOT suitable for room cards
    // Always use proper room interior placeholder images
    
    return [
      'https://images.unsplash.com/photo-1566665797739-1674de7a421a?w=400&h=200&fit=crop&q=80', // King bed room interior
      'https://images.unsplash.com/photo-1564013799919-ab600027ffc6?w=400&h=200&fit=crop&q=80', // Queen bed room interior  
      'https://images.unsplash.com/photo-1578662996442-48f60103fc96?w=400&h=200&fit=crop&q=80', // Suite room interior
      'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=400&h=200&fit=crop&q=80', // Modern room interior
      'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=400&h=200&fit=crop&q=80', // Luxury room interior
    ];
  }

  List<String> _getHotelImages() {
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
    
    // Fallback to hotel thumbnail if available
    if (images.isEmpty) {
      final thumbnail = widget.hotel['thumbnail'];
      if (thumbnail != null && thumbnail.toString().isNotEmpty) {
        images = [thumbnail.toString()];
      }
    }
    
    return images;
  }

  List<String> _getHotelAmenities() {
    final dynamic amenitiesData = widget.hotel['amenities'];
    List<String> amenities = [];
    
    if (amenitiesData != null && amenitiesData is List) {
      amenities = amenitiesData.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
    }
    
    // Fallback to default amenities if none available
    if (amenities.isEmpty) {
      amenities = [
        'Free WiFi',
        'Pool',
        'Spa',
        'Restaurant',
        'Fitness Center',
        'Air conditioning',
        'Paid private parking on-site',
        'Room service',
        'Concierge',
        'Business center',
        'Laundry service',
        'Pet friendly',
      ];
    }
    
    return amenities;
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room image (tappable)
          GestureDetector(
            onTap: () => _navigateToRoomDetails(room),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: CachedNetworkImage(
                  imageUrl: room['image'],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  placeholder: (context, url) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                        Icons.bed,
                        color: AppColors.textSecondary,
                        size: 48,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Room image unavailable',
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
              ),
            ),
          ),
          
          // Room details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${_safeDouble(room['price'], 0.0).toStringAsFixed(0)} per night',
                  style: const TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${(_safeDouble(room['price'], 0.0) * 1.15).toStringAsFixed(2)} including taxes + fees',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    room['bedType'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Reserve button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Reserving ${(room['name'] as String?) ?? 'Room'}...')), // ✅ null-safe
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Reserve',
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatPeopleSay() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.star, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'What people say',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _isLoadingContent
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  ),
                )
              : Text(
                  _whatPeopleSay.isNotEmpty
                      ? _whatPeopleSay
                      : _getFallbackWhatPeopleSay(),
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.white,
                  ),
                ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildReviewSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Review summary',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This summary was created by AI, based on recent reviews.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white60,
              fontStyle: FontStyle.italic,
            ),
            ),
          const SizedBox(height: 12),
          Text(
            _reviewSummary,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLocationSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            _locationSummary,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRatingInsights() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            _ratingInsights,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.white,
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _getChooseThisIfText() {
    final hotel = widget.hotel;
    final name = hotel['name']?.toString() ?? 'this hotel';
    final location = hotel['location']?.toString() ?? '';
    final amenities = hotel['amenities'] as List<dynamic>? ?? [];
    
    // Create dynamic recommendation based on hotel data
    String baseText = 'You want a comfortable stay at $name';
    
    if (location.isNotEmpty) {
      baseText += ' in $location';
    }
    
    if (amenities.isNotEmpty) {
      final keyAmenities = amenities.take(3).join(', ');
      baseText += ' with $keyAmenities';
    }
    
    baseText += ' and convenient amenities for your needs.';
    
    return baseText;
  }

  String _getAboutText({bool isExpanded = false}) {
    final hotel = widget.hotel;
    final name = hotel['name']?.toString() ?? 'this hotel';
    final location = hotel['location']?.toString() ?? '';
    final description = hotel['description']?.toString() ?? '';
    final amenities = hotel['amenities'] as List<dynamic>? ?? [];
    
    // Use description if available
    if (description.isNotEmpty && description != 'No description available') {
      if (isExpanded) {
        return description;
      } else {
        // Show first 150 characters for short version
        return description.length > 150 
            ? '${description.substring(0, 150)}...' // ✅ null-safe
            : description;
      }
    }
    
    // Create dynamic about text
    String baseText = 'Experience $name';
    
    if (location.isNotEmpty) {
      baseText += ' in $location';
    }
    
    baseText += '. This hotel offers comfortable accommodations';
    
    if (amenities.isNotEmpty) {
      final keyAmenities = amenities.take(3).join(', ');
      baseText += ' with $keyAmenities';
    }
    
    if (isExpanded) {
      baseText += ' and modern amenities for a pleasant stay.';
      if (amenities.length > 3) {
        final additionalAmenities = amenities.skip(3).take(5).join(', ');
        baseText += ' Additional features include $additionalAmenities.';
      }
      baseText += ' Perfect for both business and leisure travelers seeking comfort and convenience.';
    } else {
      baseText += ' and modern amenities for a pleasant stay.';
    }
    
    return baseText;
  }

  Widget _buildChooseThisIf() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Choose this if',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _chooseThisIf.isNotEmpty ? _chooseThisIf : _getChooseThisIfText(),
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.white,
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAbout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'About',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _about.isNotEmpty 
                ? (_isDescriptionExpanded ? _about : (_about.length > 150 ? '${_about.substring(0, 150)}...' : _about))
                : _getAboutText(isExpanded: _isDescriptionExpanded),
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _isDescriptionExpanded = !_isDescriptionExpanded;
              });
            },
            child: Text(
              _isDescriptionExpanded ? 'Read less' : 'Read more',
              style: const TextStyle(
                color: Colors.tealAccent,
                decoration: TextDecoration.underline,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAmenities() {
    // Use cleaned amenities from API if available, otherwise use hotel data
    List<String> amenities = _amenitiesClean.isNotEmpty 
        ? _amenitiesClean 
        : (widget.hotel['amenities'] as List<dynamic>?)
            ?.map((item) => item?.toString() ?? '')
            .where((item) => item.isNotEmpty)
            .toList() ?? [];
    
    // Fallback to default amenities if none available
    if (amenities.isEmpty) {
      amenities = [
      'Free WiFi',
      'Pool',
      'Spa',
      'Restaurant',
      'Fitness Center',
      'Air conditioning',
      'Paid private parking on-site',
    ];
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Amenities',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: amenities.take(8).map((amenity) => _buildAmenityChip(amenity)).toList(), // ✅ Limit to 8 amenities (Perplexity-style)
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAmenityChip(String amenity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F), // Perplexity-style dark grey
        borderRadius: BorderRadius.circular(20), // More rounded like Perplexity
      ),
      child: Text(
        amenity,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13, // Perplexity uses 13px
          fontWeight: FontWeight.normal, // Perplexity uses normal weight
        ),
      ),
    );
  }

  Future<void> _loadHotelCoordinates() async {
    print('🗺️ HotelDetailScreen: Loading coordinates for hotel: ${widget.hotel['name'] ?? widget.hotel['title']}');
    print('🗺️ HotelDetailScreen: Hotel data keys: ${widget.hotel.keys.toList()}');
    
    // First try to extract from hotel data
    final coords = GeocodingService.extractCoordinates(widget.hotel);
    print('🗺️ HotelDetailScreen: Extracted coordinates: $coords');
    
    if (coords != null && coords['latitude'] != null && coords['longitude'] != null) {
      final lat = coords['latitude']!;
      final lng = coords['longitude']!;
      
      // Validate coordinates (not 0,0)
      if (lat != 0.0 && lng != 0.0) {
        print('✅ HotelDetailScreen: Using coordinates from hotel data: $lat, $lng');
        setState(() {
          _hotelLatitude = lat;
          _hotelLongitude = lng;
        });
        return;
      } else {
        print('⚠️ HotelDetailScreen: Coordinates are 0,0 - invalid, will geocode');
      }
    }

    // If no coordinates, try to geocode the address
    final location = widget.hotel['location'] ?? 
                    widget.hotel['address'] ?? 
                    widget.hotel['address_line'] ?? '';
    
    print('🗺️ HotelDetailScreen: No valid coordinates found, geocoding address: $location');
    
    if (location.isNotEmpty && location != 'Location not available') {
      setState(() {
        _isLoadingCoordinates = true;
      });
      
      try {
        final geocoded = await GeocodingService.geocodeAddress(location)
            .timeout(const Duration(seconds: 10));
        
        if (geocoded != null && mounted) {
          final lat = geocoded['latitude']!;
          final lng = geocoded['longitude']!;
          
          if (lat != 0.0 && lng != 0.0) {
            print('✅ HotelDetailScreen: Geocoded successfully: $lat, $lng');
            setState(() {
              _hotelLatitude = lat;
              _hotelLongitude = lng;
              _isLoadingCoordinates = false;
            });
          } else {
            print('⚠️ HotelDetailScreen: Geocoded coordinates are 0,0');
            if (mounted) {
              setState(() {
                _isLoadingCoordinates = false;
              });
            }
          }
        } else if (mounted) {
          print('❌ HotelDetailScreen: Geocoding returned null');
          setState(() {
            _isLoadingCoordinates = false;
          });
        }
      } catch (e) {
        print('❌ HotelDetailScreen: Geocoding error: $e');
        if (mounted) {
          setState(() {
            _isLoadingCoordinates = false;
          });
        }
      }
    } else {
      print('⚠️ HotelDetailScreen: No location/address available for geocoding');
      if (mounted) {
        setState(() {
          _isLoadingCoordinates = false;
        });
      }
    }
  }

  Widget _buildLocation() {
    final hotelName = widget.hotel['name'] ?? widget.hotel['title'] ?? 'Hotel';
    final location = widget.hotel['location'] ?? 
                    widget.hotel['address'] ?? 
                    'Location not available';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Location',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoadingCoordinates)
          Container(
            height: 200,
            decoration: BoxDecoration(
                color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
            ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white70,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () {
                // Only open full screen if we have valid coordinates
                if (_hotelLatitude != null && _hotelLongitude != null && 
                    _hotelLatitude != 0.0 && _hotelLongitude != 0.0) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapScreen(
                        points: [
                          {
                            'name': hotelName,
                            'lat': _hotelLatitude,
                            'latitude': _hotelLatitude,
                            'lng': _hotelLongitude,
                            'longitude': _hotelLongitude,
                            'rating': widget.hotel['rating'] ?? widget.hotel['overall_rating'] ?? '0',
                          }
                        ],
                        title: hotelName,
                      ),
                    ),
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GoogleMapWidget(
                  latitude: _hotelLatitude ?? 0.0,
                  longitude: _hotelLongitude ?? 0.0,
                  address: location,
                  title: hotelName,
                  height: 200,
                  showMarker: true,
                  interactive: false, // ✅ FIX 4: Disable map interaction, use tap on container instead
                  ),
              ),
            ),
          if (location.isNotEmpty && location != 'Location not available') ...[
            const SizedBox(height: 12),
                  Text(
              location,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                    ),
                  ),
                ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _DateGuestModal extends StatefulWidget {
  final String selectedCheckIn;
  final String selectedCheckOut;
  final int adultCount;
  final int kidsCount;
  final Function(String) onCheckInChanged;
  final Function(String) onCheckOutChanged;
  final Function(int) onAdultCountChanged;
  final Function(int) onKidsCountChanged;

  const _DateGuestModal({
    required this.selectedCheckIn,
    required this.selectedCheckOut,
    required this.adultCount,
    required this.kidsCount,
    required this.onCheckInChanged,
    required this.onCheckOutChanged,
    required this.onAdultCountChanged,
    required this.onKidsCountChanged,
  });

  @override
  State<_DateGuestModal> createState() => _DateGuestModalState();
}

class _DateGuestModalState extends State<_DateGuestModal> {
  late String _localCheckIn;
  late String _localCheckOut;
  late int _localAdultCount;
  late int _localKidsCount;
  
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedCheckInDate;
  DateTime? _selectedCheckOutDate;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _localCheckIn = widget.selectedCheckIn;
    _localCheckOut = widget.selectedCheckOut;
    _localAdultCount = widget.adultCount;
    _localKidsCount = widget.kidsCount;
    
    // Initialize with today's date and tomorrow's date
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    
    _selectedCheckInDate = today;
    _selectedCheckOutDate = tomorrow;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Select dates',
                  style: AppTypography.title1.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          
          // Calendar
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Calendar
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TableCalendar<dynamic>(
                      firstDay: DateTime.now().subtract(const Duration(days: 1)),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      eventLoader: (day) => [],
                      startingDayOfWeek: StartingDayOfWeek.sunday,
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        weekendTextStyle: AppTypography.body1.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        defaultTextStyle: AppTypography.body1.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        selectedTextStyle: AppTypography.body1.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        todayTextStyle: AppTypography.body1.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        defaultDecoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        weekendDecoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        markersMaxCount: 0,
                      ),
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: AppTypography.title2.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        leftChevronIcon: Icon(
                          Icons.chevron_left,
                          color: AppColors.textPrimary,
                        ),
                        rightChevronIcon: Icon(
                          Icons.chevron_right,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        weekendStyle: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      enabledDayPredicate: (day) {
                        // Only allow today and future dates
                        return day.isAfter(DateTime.now().subtract(const Duration(days: 1)));
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        // Only allow selection of today or future dates
                        if (selectedDay.isBefore(DateTime.now())) {
                          return;
                        }
                        
                        if (!isSameDay(_selectedCheckInDate, selectedDay) &&
                            !isSameDay(_selectedCheckOutDate, selectedDay)) {
                          if (_selectedCheckInDate == null ||
                              (_selectedCheckInDate != null &&
                                  _selectedCheckOutDate != null)) {
                            setState(() {
                              _selectedCheckInDate = selectedDay;
                              _selectedCheckOutDate = null;
                              _localCheckIn = '${_getMonthName(selectedDay.month)} ${selectedDay.day}';
                            });
                            widget.onCheckInChanged(_localCheckIn);
                          } else if (_selectedCheckInDate != null &&
                              _selectedCheckOutDate == null) {
                            if (selectedDay.isAfter(_selectedCheckInDate!)) {
                              setState(() {
                                _selectedCheckOutDate = selectedDay;
                                _localCheckOut = '${_getMonthName(selectedDay.month)} ${selectedDay.day}';
                              });
                              widget.onCheckOutChanged(_localCheckOut);
                            } else {
                              setState(() {
                                _selectedCheckInDate = selectedDay;
                                _selectedCheckOutDate = null;
                                _localCheckIn = '${_getMonthName(selectedDay.month)} ${selectedDay.day}';
                              });
                              widget.onCheckInChanged(_localCheckIn);
                            }
                          }
                        }
                      },
                      selectedDayPredicate: (day) {
                        return isSameDay(_selectedCheckInDate, day) ||
                               isSameDay(_selectedCheckOutDate, day);
                      },
                      onPageChanged: (focusedDay) {
                        setState(() {
                          _focusedDay = focusedDay;
                        });
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Guest counters
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _buildGuestCounter('Adults', _localAdultCount, (value) {
                          setState(() {
                            _localAdultCount = value;
                          });
                          widget.onAdultCountChanged(value);
                        }),
                        const SizedBox(height: 16),
                        _buildGuestCounter('Kids (0-13)', _localKidsCount, (value) {
                          setState(() {
                            _localKidsCount = value;
                          });
                          widget.onKidsCountChanged(value);
                        }),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Check Availability button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Checking availability...')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Check Availability',
                          style: AppTypography.body1.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildGuestCounter(String label, int count, Function(int) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body1.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: count > 0 ? () {
                  onChanged(count - 1);
                } : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: count > 0 ? AppColors.surfaceVariant : AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: count > 0 ? AppColors.surfaceVariant : AppColors.textSecondary,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.remove,
                    size: 18,
                    color: count > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Container(
                width: 40,
                child: Text(
                  count.toString(),
                  style: AppTypography.title2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () {
                  onChanged(count + 1);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

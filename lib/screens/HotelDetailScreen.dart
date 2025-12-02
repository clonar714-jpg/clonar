import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import 'RoomDetailsScreen.dart';

class HotelDetailScreen extends StatefulWidget {
  final Map<String, dynamic> hotel;

  const HotelDetailScreen({
    Key? key,
    required this.hotel,
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

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _scrollController.addListener(_onScroll);
    
    // Initialize with today's date and tomorrow's date
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    
    _selectedCheckIn = '${_getMonthName(today.month)} ${today.day}';
    _selectedCheckOut = '${_getMonthName(tomorrow.month)} ${tomorrow.day}';
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
    final rating = widget.hotel[category] ?? widget.hotel['${category}_rating'];
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
          return '${amenityStr.split(' ').first.toUpperCase()}${amenityStr.split(' ').skip(1).join(' ')} Room';
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
        return '\$${priceValue.toStringAsFixed(0)} per night';
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          widget.hotel['name'] ?? 'Hotel Details',
          style: AppTypography.title1.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 80), // Add padding for fixed button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hotel image carousel
                _buildImageCarousel(),
                
                // Hotel basic info
                _buildHotelInfo(),
                
                // Action buttons
                _buildActionButtons(),
                
                // What people say (Reviews)
                _buildWhatPeopleSay(),
                
                // Choose this if
                _buildChooseThisIf(),
                
                // About
                _buildAbout(),
                
                // Amenities
                _buildAmenities(),
                
                // Location
                _buildLocation(),
                
                // Traveler insights
                _buildTravelerInsights(),
                
                // Rooms section
                _buildRoomsSection(),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Fixed bottom button (conditional)
          if (_showBottomButton)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildSimpleActionButton('Call', Icons.phone, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Calling hotel...')),
              );
            }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSimpleActionButton('Website', Icons.language, () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening hotel website...')),
              );
            }),
          ),
          const SizedBox(width: 12),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.body1.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
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

  Widget _buildImageCarousel() {
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
    
    // If no images, show a placeholder
    if (images.isEmpty) {
      return SizedBox(
        height: 250,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
          ),
          child: const Icon(
            Icons.hotel,
            color: AppColors.textSecondary,
            size: 64,
          ),
        ),
      );
    }
    
    return SizedBox(
      height: 250,
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
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                ),
                child: Image.network(
                  images[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(
                        Icons.hotel,
                        color: AppColors.textSecondary,
                        size: 64,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          
          // Image indicators
          if (images.length > 1)
            Positioned(
              bottom: 16,
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
        ],
      ),
    );
  }

  Widget _buildHotelInfo() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hotel name
          Text(
            widget.hotel['name'] ?? 'Hotel Name',
            style: AppTypography.title1.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          
          // Location
          Text(
            widget.hotel['location'] ?? 'Location',
            style: AppTypography.body1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          
                  // Rating and reviews
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.hotel['rating'] ?? 0.0}',
                        style: AppTypography.title2.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${widget.hotel['reviewCount'] ?? 0} reviews)',
                        style: AppTypography.body1.copyWith(
                          color: AppColors.textSecondary,
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
              const Spacer(),
              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.hotel['originalPrice'] != null) ...[
                    Text(
                      '\$${widget.hotel['originalPrice']}',
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    '\$${widget.hotel['price'] ?? 0}',
                    style: AppTypography.title1.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
                      '${(widget.hotel['rating'] ?? 0.0).toStringAsFixed(1)}',
                      style: AppTypography.title1.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 32,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Good',
                      style: AppTypography.title2.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.hotel['reviewCount'] ?? 0} reviews',
                      style: AppTypography.body1.copyWith(
                        color: AppColors.accent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      Icons.star,
                      color: index < (widget.hotel['rating'] ?? 0.0).floor()
                          ? AppColors.accent
                          : AppColors.surfaceVariant,
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
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: rating / 5.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            rating.toStringAsFixed(1),
            style: AppTypography.body1.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsSection() {
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
          
          // Date and guest selector
          GestureDetector(
            onTap: _showDateGuestModal,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    '$_selectedCheckIn - $_selectedCheckOut',
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.people, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    '${_adultCount + _kidsCount} guests',
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w500,
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
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Available room types
          _buildAvailableRooms(),
        ],
      ),
    );
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
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
                child: Image.network(
                  room['image'],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
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
                    );
                  },
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
                  style: AppTypography.title2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${room['price'].toStringAsFixed(0)} per night',
                  style: AppTypography.title1.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${(room['price'] * 1.15).toStringAsFixed(2)} including taxes + fees',
                  style: AppTypography.body1.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    room['bedType'],
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w500,
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
                        SnackBar(content: Text('Reserving ${room['name']}...')),
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
              const Icon(Icons.star, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'What people say',
                style: AppTypography.title2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Text(
              widget.hotel['description'] ?? 'No reviews available',
              style: AppTypography.body1.copyWith(
                height: 1.4,
              ),
            ),
          ),
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
            ? '${description.substring(0, 150)}...'
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
              Text(
                'Choose this if',
                style: AppTypography.title2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Text(
              _getChooseThisIfText(),
              style: AppTypography.body1.copyWith(
                height: 1.4,
              ),
            ),
          ),
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
          Text(
            'About',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _getAboutText(isExpanded: _isDescriptionExpanded),
            style: AppTypography.body1.copyWith(
              height: 1.4,
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
              style: AppTypography.body1.copyWith(
                color: AppColors.accent,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmenities() {
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
    ];
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Amenities',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: amenities.map((amenity) => _buildAmenityChip(amenity)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAmenityChip(String amenity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        amenity,
        style: AppTypography.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLocation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Location',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_on,
                    color: AppColors.textSecondary,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.hotel['location'] ?? 'Location not available',
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to view on map',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      height: MediaQuery.of(context).size.height * 0.8,
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

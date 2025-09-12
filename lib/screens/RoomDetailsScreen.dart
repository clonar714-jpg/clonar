import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class RoomDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  final Map<String, dynamic> hotel;

  const RoomDetailsScreen({
    Key? key,
    required this.room,
    required this.hotel,
  }) : super(key: key);

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  late PageController _imagePageController;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100), // Add padding for sticky button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room image carousel
                _buildImageCarousel(),
                
                // Hotel and room info
                _buildRoomInfo(),
                
                // Room features
                _buildRoomFeatures(),
                
                // Hotel features
                _buildHotelFeatures(),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Sticky reserve button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyReserveButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCarousel() {
    final dynamic imagesData = widget.room['images'];
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
      final thumbnail = widget.room['thumbnail'];
      if (thumbnail != null && thumbnail.toString().isNotEmpty) {
        images = [thumbnail.toString()];
      }
    }
    
    return SizedBox(
      height: 300,
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
                        Icons.bed,
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

  Widget _buildRoomInfo() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hotel name
          Text(
            widget.hotel['name'] ?? 'Hotel Name',
            style: AppTypography.body1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          
          // Room name
          Text(
            widget.room['name'] ?? 'Room Name',
            style: AppTypography.title1.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          
          // Price
          Row(
            children: [
              Text(
                '\$${widget.room['price'] ?? 0}',
                style: AppTypography.title1.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'per night',
                style: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'including taxes + fees',
                style: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomFeatures() {
    final dynamic featuresData = widget.room['features'];
    List<String> roomFeatures = [];
    
    if (featuresData != null && featuresData is List) {
      roomFeatures = featuresData.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
    }
    
    // Fallback to default features if none available
    if (roomFeatures.isEmpty) {
      roomFeatures = [
        '2 Queen Bed',
        'Minibar',
        'Shower',
        'Safety deposit box',
        'Pay-per-view channels',
        'TV',
        'Telephone',
        'Air conditioning',
        'Hairdryer',
        'Wake up service/Alarm clock',
        'Iron',
        'Bathrobe',
        'Desk',
        'Toilet',
        'Private bathroom',
        'Heating',
        'Satellite channels',
        'Cable channels',
        'Carpeted',
        'Interconnected room(s) available',
        'Laptop safe',
        'Flat-screen TV',
        'Wardrobe or closet',
        'Hypoallergenic',
        'City view',
        'Towels',
        'Linen',
        'Upper floors accessible by elevator',
        'Clothes rack',
        'Toilet paper',
        'Trash cans',
        'Cots',
        'Shampoo',
        'Conditioner',
        'Body soap',
        'Socket near the bed',
        'Non-feather pillow',
        'Hypoallergenic pillow',
        'Smoke alarm',
        'Non-smoking',
      ];
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Room features',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Features grid
          Wrap(
            children: roomFeatures.map((feature) => _buildFeatureItem(feature)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHotelFeatures() {
    final dynamic featuresData = widget.hotel['features'];
    List<String> hotelFeatures = [];
    
    if (featuresData != null && featuresData is List) {
      hotelFeatures = featuresData.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
    }
    
    // Fallback to default features if none available
    if (hotelFeatures.isEmpty) {
      hotelFeatures = [
        'Hot breakfast',
        'Continental breakfast',
        'Golf',
        'Phone services',
        'Meeting rooms',
        'Parking',
        'Movies in room',
        'Private bath or shower',
        'Laundry/Valet service',
        'Elevators',
        'Spa',
        'Lunch served in restaurant',
        'Meal plan available',
        'Restaurant',
        'Concierge desk',
        'Bell staff/porter',
        'High speed internet access',
        'Air conditioning',
        'Health club',
        'Jogging track',
        'Child programs',
        'Non-smoking rooms',
        'Safe deposit box',
        'Pets allowed',
        'Fax service',
      ];
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Hotel features',
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Features grid
          Wrap(
            children: hotelFeatures.map((feature) => _buildFeatureItem(feature)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String feature) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.surfaceVariant,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check,
            color: AppColors.accent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              feature,
              style: AppTypography.body1.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyReserveButton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
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
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Redirecting to booking...')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                'Reserve',
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

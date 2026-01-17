
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/room.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';


class RoomCard extends StatefulWidget {
  final Room room;
  final VoidCallback? onReserve;

  const RoomCard({
    Key? key,
    required this.room,
    this.onReserve,
  }) : super(key: key);

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  int _currentImageIndex = 0;
  late PageController _pageController;

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
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ ROOM IMAGE CAROUSEL
          _buildImageCarousel(),

          // ✅ ROOM DETAILS
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room name
                Text(
                  widget.room.name,
                  style: AppTypography.title2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),

                // Price per night
                Text(
                  '\$${widget.room.price.toStringAsFixed(0)} per night',
                  style: AppTypography.body1.copyWith(
                    color: const Color(0xFF00D4AA), // Perplexity teal/cyan
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),

                // Price including taxes + fees
                Text(
                  '\$${widget.room.priceWithTaxes.toStringAsFixed(2)} including taxes + fees',
                  style: AppTypography.body2.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),

                if (widget.room.amenities.isNotEmpty || widget.room.bedType.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Bed type chips
                        ...widget.room.bedType.map((bed) => _buildAmenityChip(bed)),
                        // Other amenity chips
                        ...widget.room.amenities.take(5).map((amenity) => _buildAmenityChip(amenity)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.room.available ? (widget.onReserve ?? () {}) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D4AA), // Perplexity teal/cyan
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Reserve',
                      style: AppTypography.body1.copyWith(
                        color: Colors.white,
                        fontSize: 16,
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

  // ✅ Image carousel with dots indicator
  Widget _buildImageCarousel() {
    if (widget.room.images.isEmpty) {
      return Container(
        height: 250,
        width: double.infinity,
        color: AppColors.surfaceVariant,
        child: const Icon(
          Icons.hotel,
          color: AppColors.textSecondary,
          size: 64,
        ),
      );
    }

    return Stack(
      children: [
        // Image carousel
        SizedBox(
          height: 250,
          width: double.infinity,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemCount: widget.room.images.length,
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: widget.room.images[index],
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
                    Icons.broken_image,
                    color: AppColors.textSecondary,
                    size: 48,
                  ),
                ),
              );
            },
          ),
        ),

        // Close button (X) in top-left
        Positioned(
          top: 12,
          left: 12,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),

        // Dots indicator at bottom
        if (widget.room.images.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.room.images.length,
                (index) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
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

  
  Widget _buildAmenityChip(String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.border,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.textPrimary,
          fontSize: 12,
        ),
      ),
    );
  }
}


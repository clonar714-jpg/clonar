import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class HotelCardPerplexity extends StatelessWidget {
  final Map<String, dynamic> hotel;

  const HotelCardPerplexity({Key? key, required this.hotel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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

    // Validate image URL - filter out invalid Google Photos CDN URLs
    bool isValidImageUrl(String url) {
      if (url.isEmpty) return false;
      
      // Filter out invalid Google Photos CDN URLs that cause 400 errors
      // These URLs often have format issues or require authentication
      if (url.contains('googleusercontent.com/p/')) {
        // Only accept if it's a properly formatted Places API photo URL
        // or if it's a valid Google Photos URL with proper parameters
        if (url.contains('maps.googleapis.com/maps/api/place/photo')) {
          return true; // This is a valid Places API photo URL
        }
        // Reject direct Google Photos CDN URLs that cause 400 errors
        if (url.contains('=s') && !url.contains('maps.googleapis.com')) {
          return false; // Invalid direct Google Photos CDN URL
        }
      }
      
      // Accept other valid HTTP/HTTPS URLs
      return url.startsWith('http://') || url.startsWith('https://');
    }

    // Extract image
    String? getImage() {
      final images = hotel["images"];
      if (images != null && images is List && images.isNotEmpty) {
        // Try all images in the list until we find a valid one
        for (final firstImg in images) {
          String? candidateUrl;
          
          if (firstImg is String && firstImg.isNotEmpty) {
            candidateUrl = firstImg;
          } else if (firstImg is Map) {
            final original = firstImg["original_image"]?.toString();
            final thumbnail = firstImg["thumbnail"]?.toString();
            candidateUrl = original?.isNotEmpty == true ? original : 
                          (thumbnail?.isNotEmpty == true ? thumbnail : null);
          }
          
          // Return first valid URL
          if (candidateUrl != null && isValidImageUrl(candidateUrl)) {
            return candidateUrl;
          }
        }
      }
      
      // Fallback to thumbnail
      final thumbnail = hotel["thumbnail"];
      if (thumbnail != null) {
        String? candidateUrl;
        
        if (thumbnail is String && thumbnail.isNotEmpty) {
          candidateUrl = thumbnail;
        } else if (thumbnail is Map) {
          final original = thumbnail["original_image"]?.toString();
          final thumb = thumbnail["thumbnail"]?.toString();
          candidateUrl = original?.isNotEmpty == true ? original : 
                        (thumb?.isNotEmpty == true ? thumb : null);
        }
        
        if (candidateUrl != null && isValidImageUrl(candidateUrl)) {
          return candidateUrl;
        }
      }
      return null;
    }

    final img = getImage();
    final name = safeString(hotel["name"] ?? hotel["title"], "Hotel");
    final rating = safeNumber(hotel["rating"] ?? hotel["overall_rating"], 0.0);
    final reviews = safeString(hotel["reviews"] ?? hotel["review_count"] ?? hotel["reviewCount"], "");
    final address = safeString(hotel["address"] ?? hotel["location"], "");
    
    // Extract price - support multiple formats from SerpAPI and future affiliate APIs
    String? getPrice() {
      // Try different price fields that might come from SerpAPI or affiliate APIs
      final price = hotel["price"];
      final ratePerNight = hotel["rate_per_night"];
      final extractedPrice = hotel["extracted_price"];
      final pricePerNight = hotel["price_per_night"];
      final nightlyRate = hotel["nightly_rate"];
      
      // Handle different price formats
      String? priceStr;
      if (price != null) {
        if (price is String) {
          priceStr = price.trim();
        } else if (price is Map) {
          // Handle rate_per_night object format: {lowest: "$299", highest: "$399"}
          priceStr = price["lowest"]?.toString().trim() ?? 
                     price["price"]?.toString().trim() ?? 
                     price["value"]?.toString().trim();
        } else {
          priceStr = price.toString().trim();
        }
      } else if (ratePerNight != null) {
        if (ratePerNight is Map) {
          priceStr = ratePerNight["lowest"]?.toString().trim() ?? 
                     ratePerNight["price"]?.toString().trim();
        } else {
          priceStr = ratePerNight.toString().trim();
        }
      } else if (extractedPrice != null) {
        // If it's a number, format it as currency
        if (extractedPrice is num) {
          priceStr = "\$${extractedPrice.toStringAsFixed(0)}";
        } else {
          priceStr = extractedPrice.toString().trim();
        }
      } else if (pricePerNight != null) {
        priceStr = pricePerNight.toString().trim();
      } else if (nightlyRate != null) {
        priceStr = nightlyRate.toString().trim();
      }
      
      // Validate price - don't show if it's "0", empty, or invalid
      if (priceStr == null || priceStr.isEmpty || priceStr == "0" || priceStr == "\$0") {
        return null;
      }
      
      // Ensure it has $ sign if it's a number
      if (priceStr.startsWith(RegExp(r'\d'))) {
        priceStr = "\$" + priceStr;
      }
      
      return priceStr;
    }
    
    final price = getPrice();
    
    // ✅ Perplexity-style: Extract review-based themes (dynamically generated from reviews)
    // Themes are provided by backend after analyzing hotel reviews
    final themesData = hotel["themes"];
    List<String> themes = [];
    if (themesData != null && themesData is List) {
      themes = themesData.map((t) => t.toString()).where((t) => t.isNotEmpty).toList();
    }
    
    // Fallback: If no themes from backend, infer from metadata (for backwards compatibility)
    if (themes.isEmpty) {
      if (address.isNotEmpty) themes.add("Location");
      final amenities = hotel["amenities"];
      if (amenities != null && (amenities is List ? amenities.isNotEmpty : true)) {
        themes.add("Amenities");
      }
      final service = hotel["service"] ?? hotel["service_rating"];
      if (service != null) themes.add("Service");
    }
    
    // ✅ Check if hotel has GPS coordinates for Map button
    final hasMap = (hotel["geo"] != null || 
                   hotel["gps_coordinates"] != null || 
                   (hotel["latitude"] != null && hotel["longitude"] != null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ LARGE LANDSCAPE IMAGE
        img != null
                ? CachedNetworkImage(
                    imageUrl: img,
                    height: 200, // ✅ Larger landscape image
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      width: double.infinity,
                      color: AppColors.surfaceVariant,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      width: double.infinity,
                      color: AppColors.surfaceVariant,
                      child: const Icon(
                        Icons.hotel,
                        color: AppColors.textSecondary,
                        size: 48,
                      ),
                    ),
                  )
                : Container(
                    height: 200,
                    width: double.infinity,
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.hotel,
                      color: AppColors.textSecondary,
                      size: 48,
                    ),
                  ),

          // ✅ CONTENT
          Padding(
            padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // ✅ HOTEL NAME
              Text(
                  name,
                  style: AppTypography.title2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
                const SizedBox(height: 8),

                // ✅ RATING + REVIEW COUNT + PRICE
                Row(
                  children: [
                    if (rating > 0) ...[
                      const Icon(Icons.star, size: 18, color: Colors.amber),
                      const SizedBox(width: 4),
                    Text(
                        rating.toStringAsFixed(1),
                        style: AppTypography.body1.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      if (reviews.isNotEmpty) ...[
                        Text(
                          " ($reviews)",
                          style: AppTypography.body1.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                    // ✅ PRICE - Display if available from SerpAPI or future affiliate APIs
                    if (price != null) ...[
                      const Spacer(),
                      Text(
                        price,
                        style: AppTypography.body1.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                    // ✅ TripAdvisor logo - Ready for when official API is integrated
                    // TODO: When TripAdvisor API is integrated, uncomment below and check:
                    // if (hotel["tripadvisor_api"] == true || hotel["source"]?.toString().toLowerCase() == "tripadvisor")
                    // if (false) ...[
                    //   const SizedBox(width: 8),
                    //   Row(
                    //     children: [
                    //       Icon(Icons.star, size: 14, color: Colors.green.shade700),
                    //       const SizedBox(width: 4),
                    //       Text(
                    //         "TripAdvisor",
                    //         style: AppTypography.caption.copyWith(
                    //           color: AppColors.textSecondary,
                    //           fontSize: 12,
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // ],
                  ],
                ),

                const SizedBox(height: 12),

                // ✅ FEATURE TAGS (Perplexity-style: Review-based dynamic themes)
                // Horizontal scrollable single line with equal spacing
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Display dynamic themes from review analysis with equal spacing
                      for (int i = 0; i < themes.length; i++) ...[
                        _buildFeatureTag(
                          themes[i],
                          true, // All themes are supported (they were filtered by backend)
                          _getIconForTheme(themes[i]),
                        ),
                        if (i < themes.length - 1 || hasMap) const SizedBox(width: 8),
                      ],
                      // Map button if coordinates available
                      if (hasMap)
                        _buildMapButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
    );
  }

  // ✅ Get icon for theme label
  IconData _getIconForTheme(String theme) {
    final themeLower = theme.toLowerCase();
    if (themeLower.contains("location") || themeLower.contains("views")) {
      return Icons.location_on;
    } else if (themeLower.contains("amenities") || themeLower.contains("facilities")) {
      return Icons.spa;
    } else if (themeLower.contains("service") || themeLower.contains("communication")) {
      return Icons.room_service;
    } else if (themeLower.contains("rooms") || themeLower.contains("accommodations")) {
      return Icons.bed;
    } else if (themeLower.contains("cleanliness")) {
      return Icons.cleaning_services;
    } else if (themeLower.contains("water") || themeLower.contains("temperature")) {
      return Icons.water;
    } else if (themeLower.contains("renovations") || themeLower.contains("renovated")) {
      return Icons.home_repair_service;
    } else if (themeLower.contains("value")) {
      return Icons.attach_money;
    }
    return Icons.star; // Default icon
  }

  // ✅ Feature tag widget (with checkmark - all themes are supported)
  Widget _buildFeatureTag(String label, bool hasFeature, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: hasFeature ? AppColors.surfaceVariant : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasFeature ? Colors.green.withOpacity(0.3) : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFeature ? Icons.check : Icons.close,
            size: 14,
            color: hasFeature ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
                ),
            ],
          ),
    );
  }

  // ✅ Map button widget
  Widget _buildMapButton() {
    return GestureDetector(
      onTap: () {
        // TODO: Navigate to map view
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map,
              size: 14,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              "Map",
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/**
 * ✅ PERPLEXITY-STYLE: Card conversion utilities
 * 
 * Converts backend card structures to Flutter models for detail screens
 */

import '../models/Product.dart';

/// Convert backend product card → Product model
Product cardToProduct(Map<String, dynamic> card) {
  // Parse price string (e.g., "$83.97" or "83.97") → double
  final priceStr = card['price']?.toString() ?? '0';
  final price = double.tryParse(priceStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
  
  // Extract rating
  final ratingValue = card['rating'];
  final rating = ratingValue is num 
      ? ratingValue.toDouble() 
      : (double.tryParse(ratingValue?.toString() ?? '0') ?? 0.0);
  
  // Extract reviews
  final reviewsValue = card['reviews'];
  final reviews = reviewsValue is num 
      ? reviewsValue.toInt() 
      : (int.tryParse(reviewsValue?.toString() ?? '0'));
  
  // Extract link
  final link = card['link']?.toString();
  
  // Build images list (thumbnail + any additional images)
  final images = <String>[];
  if (card['thumbnail'] != null && card['thumbnail'].toString().isNotEmpty) {
    images.add(card['thumbnail'].toString());
  }
  if (card['images'] != null) {
    if (card['images'] is List) {
      for (final img in card['images'] as List) {
        final imgUrl = img?.toString();
        if (imgUrl != null && imgUrl.isNotEmpty && !images.contains(imgUrl)) {
          images.add(imgUrl);
        }
      }
    } else if (card['images'] is String && card['images'].toString().isNotEmpty) {
      final imgUrl = card['images'].toString();
      if (!images.contains(imgUrl)) {
        images.add(imgUrl);
      }
    }
  }
  
  // Generate ID from URL or title+price if not provided
  final id = card['id']?.toString() ?? 
      '${card['title'] ?? ''}_${price}_${card['link'] ?? ''}'.hashCode.abs();
  
  // Source is the retailer name (e.g., "Dillard's", "Walmart")
  // Link is the product URL
  final source = card['source']?.toString() ?? 'Unknown Source';
  
  return Product(
    id: id is int ? id : (id.toString().hashCode.abs()),
    title: card['title']?.toString() ?? 'Unknown Product',
    description: card['description']?.toString() ?? 
                 card['snippet']?.toString() ?? 
                 'No description available',
    price: price,
    source: source,
    rating: rating,
    reviews: reviews,
    link: link,
    images: images,
    variants: [], // ✅ Variants not supported from backend cards yet
  );
}

/// Extract movieId from backend movie card
int cardToMovieId(Map<String, dynamic> card) {
  final id = card['id'];
  if (id is int) return id;
  if (id is String) {
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed;
  }
  // Fallback: use TMDB ID if available, or hash of title
  if (card['tmdbId'] != null) {
    final tmdbId = card['tmdbId'];
    if (tmdbId is int) return tmdbId;
    if (tmdbId is String) {
      final parsed = int.tryParse(tmdbId);
      if (parsed != null) return parsed;
    }
  }
  return (card['title']?.toString() ?? '').hashCode.abs();
}

/// Hotel and Place cards are already Map<String, dynamic>, no conversion needed
/// Just pass them directly to HotelDetailScreen/PlaceDetailScreen


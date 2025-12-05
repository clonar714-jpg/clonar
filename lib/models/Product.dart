import 'Variant.dart';

class Product {
  final int id;
  final String title;
  final String description;
  final double price;
  final double? discountPrice;
  final String source;
  final double rating;
  final List<String> images;
  final List<Variant> variants;

  Product({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.discountPrice,
    required this.source,
    required this.rating,
    required this.images,
    this.variants = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: (json['id'] as num?)?.toInt() ?? 0, // ✅ null-safe: default to 0 if null
      title: json['title'] as String? ?? 'Untitled Product', // ✅ null-safe: default to 'Untitled Product'
      description: json['description'] as String? ?? 'No description available', // ✅ null-safe: default to 'No description available'
      price: (json['price'] as num?)?.toDouble() ?? 0.0, // ✅ null-safe: default to 0.0 if null
      discountPrice: (json['discountPrice'] as num?)?.toDouble(), // ✅ null-safe: nullable double
      source: json['source'] as String? ?? 'Unknown Source', // ✅ null-safe: default to 'Unknown Source'
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0, // ✅ null-safe: default to 0.0 if null
      images: _parseImagesList(json['images']), // ✅ null-safe: handle null/empty images
      variants: _parseVariantsList(json['variants']), // ✅ null-safe: handle null/empty variants
    );
  }

  // ✅ null-safe: Helper method to safely parse images list
  static List<String> _parseImagesList(dynamic imagesJson) {
    if (imagesJson == null) return []; // ✅ null-safe: return empty list if null
    if (imagesJson is! List) return []; // ✅ null-safe: return empty list if not a list
    
    final List<String> images = [];
    for (final item in imagesJson) {
      if (item is String && item.isNotEmpty) { // ✅ null-safe: only add non-empty strings
        images.add(item);
      }
    }
    return images;
  }

  // ✅ null-safe: Helper method to safely parse variants list
  static List<Variant> _parseVariantsList(dynamic variantsJson) {
    if (variantsJson == null) return []; // ✅ null-safe: return empty list if null
    if (variantsJson is! List) return []; // ✅ null-safe: return empty list if not a list
    
    final List<Variant> variants = [];
    for (final item in variantsJson) {
      if (item is Map<String, dynamic>) { // ✅ null-safe: only process valid maps
        try {
          variants.add(Variant.fromJson(item));
        } catch (e) {
          // ✅ null-safe: skip invalid variant entries
          continue;
        }
      }
    }
    return variants;
  }

  String get formattedPrice => '\$${price.toStringAsFixed(2)}';
  
  String get formattedDiscountPrice => discountPrice != null ? '\$${discountPrice!.toStringAsFixed(2)}' : '';
  
  bool get hasDiscount => discountPrice != null && discountPrice! < price;
}

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
      id: json['id'],
      title: json['title'],
      description: json['description'],
      price: json['price'].toDouble(),
      discountPrice: json['discountPrice']?.toDouble(),
      source: json['source'],
      rating: json['rating'].toDouble(),
      images: List<String>.from(json['images']),
      variants: json['variants'] != null
          ? (json['variants'] as List)
              .map((v) => Variant.fromJson(v))
              .toList()
          : [],
    );
  }

  String get formattedPrice => '\$${price.toStringAsFixed(2)}';
  
  String get formattedDiscountPrice => discountPrice != null ? '\$${discountPrice!.toStringAsFixed(2)}' : '';
  
  bool get hasDiscount => discountPrice != null && discountPrice! < price;
}

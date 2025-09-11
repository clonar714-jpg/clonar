import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/Product.dart';

class ProductService {
  static const String baseUrl = String.fromEnvironment("BACKEND_URL", defaultValue: "http://10.0.2.2:3000");

  Future<List<dynamic>> searchProducts(String query) async {
    final url = Uri.parse("$baseUrl/search");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"query": query}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["results"] ?? [];
    } else {
      throw Exception("Failed to load products: ${response.body}");
    }
  }

  Future<List<Product>> fetchProducts(String query) async {
    final results = await searchProducts(query);
    return results.map((item) => _convertToProduct(item)).toList();
  }

  Product _convertToProduct(dynamic productData) {
    if (productData is! Map<String, dynamic>) {
      return Product(
        id: DateTime.now().millisecondsSinceEpoch,
        title: 'Unknown Product',
        description: '',
        price: 0.0,
        discountPrice: null,
        source: 'Unknown Source',
        rating: 0.0,
        images: [],
      );
    }

    // Extract price - handle both string and numeric formats
    double price = 0.0;
    if (productData['extracted_price'] != null) {
      price = double.tryParse(productData['extracted_price'].toString()) ?? 0.0;
    } else if (productData['price'] != null) {
      // Extract numeric value from price string like "$150.00"
      String priceStr = productData['price'].toString().replaceAll(RegExp(r'[^\d.]'), '');
      price = double.tryParse(priceStr) ?? 0.0;
    }

    // Extract discount price if available
    double? discountPrice;
    if (productData['old_price'] != null) {
      // If there's an old_price, use current price as discount price and old_price as original
      discountPrice = price;
      String oldPriceStr = productData['old_price'].toString().replaceAll(RegExp(r'[^\d.]'), '');
      price = double.tryParse(oldPriceStr) ?? price;
    } else if (productData['discountPrice'] != null) {
      discountPrice = double.tryParse(productData['discountPrice'].toString()) ?? null;
    }

    // Extract rating - handle both string and numeric formats
    double rating = 0.0;
    if (productData['rating'] != null) {
      rating = double.tryParse(productData['rating'].toString()) ?? 0.0;
    }

    // Extract images - use thumbnail as primary image
    List<String> images = [];
    if (productData['thumbnail'] != null && productData['thumbnail'].toString().isNotEmpty) {
      images.add(productData['thumbnail'].toString());
    }

    return Product(
      id: DateTime.now().millisecondsSinceEpoch + (productData.hashCode % 1000),
      title: productData['title'] ?? 'Unknown Product',
      description: productData['description'] ?? '',
      price: price,
      discountPrice: discountPrice,
      source: productData['source'] ?? 'Unknown Source',
      rating: rating,
      images: images,
    );
  }
}

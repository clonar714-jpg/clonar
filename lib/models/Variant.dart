class Variant {
  final String color;
  final List<String> sizes;
  final int availableQuantity;

  Variant({
    required this.color,
    required this.sizes,
    required this.availableQuantity,
  });

  factory Variant.fromJson(Map<String, dynamic> json) {
    return Variant(
      color: json['color'] as String? ?? 'Unknown Color', // ✅ null-safe: default to 'Unknown Color'
      sizes: _parseSizesList(json['sizes']), // ✅ null-safe: handle null/empty sizes
      availableQuantity: _parseAvailableQuantity(json), // ✅ null-safe: handle multiple quantity field names
    );
  }

  // ✅ null-safe: Helper method to safely parse sizes list
  static List<String> _parseSizesList(dynamic sizesJson) {
    if (sizesJson == null) return []; // ✅ null-safe: return empty list if null
    if (sizesJson is! List) return []; // ✅ null-safe: return empty list if not a list
    
    final List<String> sizes = [];
    for (final item in sizesJson) {
      if (item is String && item.isNotEmpty) { // ✅ null-safe: only add non-empty strings
        sizes.add(item);
      }
    }
    return sizes;
  }

  // ✅ null-safe: Helper method to safely parse available quantity
  static int _parseAvailableQuantity(Map<String, dynamic> json) {
    // ✅ null-safe: try multiple possible field names for quantity
    final quantity = json['availableQuantity'] ?? 
                    json['available_quantity'] ?? 
                    json['quantity'] ?? 
                    json['stock'];
    
    if (quantity is num) {
      return quantity.toInt(); // ✅ null-safe: convert to int
    }
    return 0; // ✅ null-safe: default to 0 if null or invalid
  }
}

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
      color: json['color'] ?? '',
      sizes: List<String>.from(json['sizes'] ?? []),
      availableQuantity: json['availableQuantity'] ?? json['available_quantity'] ?? 0,
    );
  }
}

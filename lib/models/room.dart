// lib/models/room.dart

/// 🏨 Hotel Room Model (Perplexity-style)
/// 
/// Mirrors the backend Room interface
class Room {
  final String id;
  final String name;
  final String? description;
  final double price; // Base price per night
  final double priceWithTaxes; // Total price including taxes and fees
  final List<String> images;
  final List<String> bedType; // e.g., ["1 King Bed"], ["2 Queen Bed"]
  final List<String> amenities; // e.g., ["AM/FM radio", "Alarm clock", "Bathrobe"]
  final bool? refundable;
  final bool available;
  final String? roomSize; // e.g., "350 sq ft"
  final int? maxOccupancy;
  final String? cancellationPolicy;

  Room({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.priceWithTaxes,
    required this.images,
    required this.bedType,
    required this.amenities,
    this.refundable,
    required this.available,
    this.roomSize,
    this.maxOccupancy,
    this.cancellationPolicy,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Standard Room',
      description: json['description']?.toString(),
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : 0.0,
      priceWithTaxes: (json['priceWithTaxes'] is num) ? (json['priceWithTaxes'] as num).toDouble() : 0.0,
      images: (json['images'] as List<dynamic>?)
          ?.map((img) => img.toString())
          .where((img) => img.isNotEmpty)
          .toList() ?? [],
      bedType: (json['bedType'] as List<dynamic>?)
          ?.map((bed) => bed.toString())
          .where((bed) => bed.isNotEmpty)
          .toList() ?? [],
      amenities: (json['amenities'] as List<dynamic>?)
          ?.map((amenity) => amenity.toString())
          .where((amenity) => amenity.isNotEmpty)
          .toList() ?? [],
      refundable: json['refundable'] as bool?,
      available: json['available'] as bool? ?? true,
      roomSize: json['roomSize']?.toString(),
      maxOccupancy: json['maxOccupancy'] != null ? (json['maxOccupancy'] as num).toInt() : null,
      cancellationPolicy: json['cancellationPolicy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'priceWithTaxes': priceWithTaxes,
      'images': images,
      'bedType': bedType,
      'amenities': amenities,
      'refundable': refundable,
      'available': available,
      'roomSize': roomSize,
      'maxOccupancy': maxOccupancy,
      'cancellationPolicy': cancellationPolicy,
    };
  }
}


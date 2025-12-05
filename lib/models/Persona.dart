import 'dart:convert';

class PersonaItem {
  final String id;
  final String imageUrl;
  final String? title;
  final String? description;
  final int position;

  PersonaItem({
    required this.id,
    required this.imageUrl,
    this.title,
    this.description,
    this.position = 0,
  });

  factory PersonaItem.fromJson(Map<String, dynamic> json) {
    return PersonaItem(
      id: json['id'] ?? '',
      imageUrl: json['image_url'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      position: json['position'] ?? 0,
    );
  }

}

class Persona {
  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final List<String> tags;
  final List<PersonaItem>? items; // ✅ Additional images/items (nullable)

  Persona({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.tags = const [],
    this.items,
  });

  factory Persona.fromJson(Map<String, dynamic> json) {
    // Handle wrapped API response (with "data" key)
    final data = json['data'] ?? json;

    return Persona(
      id: data['id'] ?? '',
      title: data['name'] ?? data['title'] ?? '',
      description: data['description'],
      imageUrl: data['cover_image_url'] ?? data['image_url'],
      tags: (data['tags'] != null)
          ? List<String>.from(data['tags'])
          : <String>[],
      items: (data['persona_items'] != null)
          ? (data['persona_items'] as List)
              .map((item) => PersonaItem.fromJson(item))
              .toList()
          : (data['items'] != null)
              ? (data['items'] as List)
                  .map((item) => PersonaItem.fromJson(item))
                  .toList()
              : <PersonaItem>[],
    );
  }

  // ✅ null-safe: Simple string extraction with guaranteed non-null result
  static String _extractString(dynamic value, String fallback) {
    if (value == null) return fallback;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? fallback : trimmed;
    }
    return fallback;
  }






  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description ?? '',
      'imageUrl': imageUrl ?? '',
      'tags': tags,
    };
  }

  // ✅ copyWith method for updating persona properties
  Persona copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    List<String>? tags,
    List<PersonaItem>? items,
  }) {
    return Persona(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      items: items ?? this.items,
    );
  }
}

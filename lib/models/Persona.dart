class Persona {
  final String id;
  final String name;
  final String? description;
  final String? coverImageUrl;
  final List<String> tags;
  final List<PersonaItem> items;
  final bool isSecret;
  final List<String> collaborators;
  final DateTime createdAt;
  final DateTime updatedAt;

  Persona({
    required this.id,
    required this.name,
    this.description,
    this.coverImageUrl,
    this.tags = const [],
    this.items = const [],
    this.isSecret = false,
    this.collaborators = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Persona copyWith({
    String? id,
    String? name,
    String? description,
    String? coverImageUrl,
    List<String>? tags,
    List<PersonaItem>? items,
    bool? isSecret,
    List<String>? collaborators,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      tags: tags ?? this.tags,
      items: items ?? this.items,
      isSecret: isSecret ?? this.isSecret,
      collaborators: collaborators ?? this.collaborators,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'tags': tags,
      'items': items.map((item) => item.toJson()).toList(),
      'isSecret': isSecret,
      'collaborators': collaborators,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Persona.fromJson(Map<String, dynamic> json) {
    return Persona(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      coverImageUrl: json['coverImageUrl'],
      tags: List<String>.from(json['tags'] ?? []),
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => PersonaItem.fromJson(item))
          .toList() ?? [],
      isSecret: json['isSecret'] ?? false,
      collaborators: List<String>.from(json['collaborators'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class PersonaItem {
  final String id;
  final String imageUrl;
  final String? title;
  final String? description;
  final List<String> tags;
  final DateTime addedAt;

  PersonaItem({
    required this.id,
    required this.imageUrl,
    this.title,
    this.description,
    this.tags = const [],
    required this.addedAt,
  });

  PersonaItem copyWith({
    String? id,
    String? imageUrl,
    String? title,
    String? description,
    List<String>? tags,
    DateTime? addedAt,
  }) {
    return PersonaItem(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'title': title,
      'description': description,
      'tags': tags,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory PersonaItem.fromJson(Map<String, dynamic> json) {
    return PersonaItem(
      id: json['id'],
      imageUrl: json['imageUrl'],
      title: json['title'],
      description: json['description'],
      tags: List<String>.from(json['tags'] ?? []),
      addedAt: DateTime.parse(json['addedAt']),
    );
  }
}

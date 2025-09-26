import 'package:flutter/material.dart';

class Collage {
  final String id;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final List<CollageItem> items;
  final String layout;
  final Map<String, dynamic> settings;
  final List<String> tags;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;

  Collage({
    required this.id,
    required this.title,
    this.description,
    this.coverImageUrl,
    this.items = const [],
    this.layout = 'grid',
    this.settings = const {},
    this.tags = const [],
    this.isPublished = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Collage copyWith({
    String? id,
    String? title,
    String? description,
    String? coverImageUrl,
    List<CollageItem>? items,
    String? layout,
    Map<String, dynamic>? settings,
    List<String>? tags,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Collage(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      items: items ?? this.items,
      layout: layout ?? this.layout,
      settings: settings ?? this.settings,
      tags: tags ?? this.tags,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'items': items.map((item) => item.toJson()).toList(),
      'layout': layout,
      'settings': settings,
      'tags': tags,
      'isPublished': isPublished,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Collage.fromJson(Map<String, dynamic> json) {
    return Collage(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      coverImageUrl: json['coverImageUrl'],
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => CollageItem.fromJson(item))
          .toList() ?? [],
      layout: json['layout'] ?? 'grid',
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
      tags: List<String>.from(json['tags'] ?? []),
      isPublished: json['isPublished'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class CollageItem {
  final String id;
  final String imageUrl;
  final String? title;
  final String? description;
  final Offset position;
  final Size size;
  final double rotation;
  final double opacity;
  final int zIndex;
  final Map<String, dynamic> filters;
  final DateTime addedAt;

  CollageItem({
    required this.id,
    required this.imageUrl,
    this.title,
    this.description,
    this.position = Offset.zero,
    this.size = const Size(100, 100),
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.filters = const {},
    required this.addedAt,
  });

  CollageItem copyWith({
    String? id,
    String? imageUrl,
    String? title,
    String? description,
    Offset? position,
    Size? size,
    double? rotation,
    double? opacity,
    int? zIndex,
    Map<String, dynamic>? filters,
    DateTime? addedAt,
  }) {
    return CollageItem(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      zIndex: zIndex ?? this.zIndex,
      filters: filters ?? this.filters,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'title': title,
      'description': description,
      'position': {'x': position.dx, 'y': position.dy},
      'size': {'width': size.width, 'height': size.height},
      'rotation': rotation,
      'opacity': opacity,
      'zIndex': zIndex,
      'filters': filters,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory CollageItem.fromJson(Map<String, dynamic> json) {
    return CollageItem(
      id: json['id'],
      imageUrl: json['imageUrl'],
      title: json['title'],
      description: json['description'],
      position: Offset(
        (json['position']?['x'] ?? 0).toDouble(),
        (json['position']?['y'] ?? 0).toDouble(),
      ),
      size: Size(
        (json['size']?['width'] ?? 100).toDouble(),
        (json['size']?['height'] ?? 100).toDouble(),
      ),
      rotation: (json['rotation'] ?? 0).toDouble(),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      zIndex: json['zIndex'] ?? 0,
      filters: Map<String, dynamic>.from(json['filters'] ?? {}),
      addedAt: DateTime.parse(json['addedAt']),
    );
  }
}


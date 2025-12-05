import 'package:flutter/material.dart';
import 'dart:convert';

class Collage {
  final String id;
  final String userId;
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
    required this.userId,
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
    String? userId,
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
      userId: userId ?? this.userId,
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
      'userId': userId,
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
      id: (json['id'] as String?) ?? 'unknown_id', // ✅ null-safe
      userId: (json['user_id'] as String?) ?? 'unknown_user', // ✅ null-safe - backend uses snake_case
      title: (json['title'] as String?) ?? 'Untitled Collage', // ✅ null-safe
      description: json['description'] as String?, // ✅ null-safe
      coverImageUrl: json['cover_image_url'] as String?, // ✅ null-safe - backend uses snake_case
      items: (json['items'] as List<dynamic>? ?? json['collage_items'] as List<dynamic>?)
          ?.map((item) => CollageItem.fromJson(item))
          .toList() ?? [],
      layout: (json['layout'] as String?) ?? 'grid', // ✅ null-safe
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? [], // ✅ null-safe
      isPublished: json['is_published'] ?? false, // ✅ backend uses snake_case
      createdAt: DateTime.parse((json['createdAt'] as String?) ?? (json['created_at'] as String?) ?? DateTime.now().toIso8601String()), // ✅ null-safe
      updatedAt: DateTime.parse((json['updatedAt'] as String?) ?? (json['updated_at'] as String?) ?? DateTime.now().toIso8601String()), // ✅ null-safe
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
  // ✅ New fields for text and shapes
  final String? type; // 'image', 'text', 'shape'
  final String? text; // For text items
  final String? shapeType; // 'circle', 'rectangle'
  final int? color; // Color value for shapes
  // ✅ Text styling fields
  final String? fontFamily; // Font family for text
  final double? fontSize; // Font size for text
  final int? textColor; // Text color
  final bool? isBold; // Bold text
  final bool? hasBackground; // Text background

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
    this.type = 'image',
    this.text,
    this.shapeType,
    this.color,
    this.fontFamily = 'Roboto',
    this.fontSize,
    this.textColor,
    this.isBold,
    this.hasBackground,
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
    String? type,
    String? text,
    String? shapeType,
    int? color,
    String? fontFamily,
    double? fontSize,
    int? textColor,
    bool? isBold,
    bool? hasBackground,
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
      type: type ?? this.type,
      text: text ?? this.text,
      shapeType: shapeType ?? this.shapeType,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      isBold: isBold ?? this.isBold,
      hasBackground: hasBackground ?? this.hasBackground,
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
      'type': type,
      'text': text,
      'shapeType': shapeType,
      'color': color,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'textColor': textColor,
      'isBold': isBold,
      'hasBackground': hasBackground,
    };
  }

  factory CollageItem.fromJson(Map<String, dynamic> json) {
    // Check if this is a text item stored in image_url
    final imageUrl = (json['imageUrl'] as String? ?? json['image_url'] as String?) ?? '';
    final isTextItem = imageUrl.startsWith('text://');
    
    String? textContent;
    String? fontFamily = 'Roboto';
    double? fontSize = 20.0;
    int? textColor = 0xFF000000;
    bool? isBold = false;
    bool? hasBackground = false;
    int? color = 0xFFFFFFFF;
    
    if (isTextItem) {
      try {
        final textDataJson = Uri.decodeComponent(imageUrl.substring(7));
        print('🔍 Parsing text data: $textDataJson');
        final textData = jsonDecode(textDataJson) as Map<String, dynamic>;
        textContent = textData['text'] as String?;
        fontFamily = textData['fontFamily'] as String? ?? 'Roboto';
        fontSize = (textData['fontSize'] as num?)?.toDouble() ?? 20.0;
        textColor = textData['textColor'] as int? ?? 0xFF000000;
        isBold = textData['isBold'] as bool? ?? false;
        hasBackground = textData['hasBackground'] as bool? ?? false;
        color = textData['color'] as int? ?? 0xFFFFFFFF;
        print('🔍 Parsed text data: text="$textContent", fontFamily="$fontFamily", hasBackground=$hasBackground');
      } catch (e) {
        print('🔍 Error parsing text data: $e');
        // Fallback to simple text extraction
        textContent = Uri.decodeComponent(imageUrl.substring(7));
      }
    }
    
    return CollageItem(
      id: (json['id'] as String?) ?? 'unknown_item_id', // ✅ null-safe
      imageUrl: isTextItem ? '' : imageUrl, // Empty for text items
      title: json['title'] as String?, // ✅ null-safe
      description: json['description'] as String?, // ✅ null-safe
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
      zIndex: json['zIndex'] ?? json['z_index'] ?? 0,
      filters: Map<String, dynamic>.from(json['filters'] ?? {}),
      addedAt: DateTime.parse((json['addedAt'] as String?) ?? (json['added_at'] as String?) ?? DateTime.now().toIso8601String()), // ✅ null-safe
      type: isTextItem ? 'text' : (json['type'] as String? ?? 'image'),
      text: isTextItem ? textContent : (json['text'] as String?),
      shapeType: json['shapeType'] as String?,
      color: isTextItem ? color : (json['color'] as int?),
      fontFamily: isTextItem ? fontFamily : (json['fontFamily'] as String? ?? 'Roboto'),
      fontSize: isTextItem ? fontSize : ((json['fontSize'] as num?)?.toDouble() ?? 20.0),
      textColor: isTextItem ? textColor : (json['textColor'] as int? ?? 0xFF000000),
      isBold: isTextItem ? isBold : (json['isBold'] as bool? ?? false),
      hasBackground: isTextItem ? hasBackground : (json['hasBackground'] as bool? ?? false),
    );
  }
}


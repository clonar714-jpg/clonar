import 'dart:convert';
import '../core/api_client.dart';
import '../models/Collage.dart';

class CollageService {
  static const String _baseUrl = '/collages';

  /// Get all published collages for the feed with user info (no authentication required)
  static Future<List<Map<String, dynamic>>> getPublishedCollagesForFeed({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'is_published': 'true',
      };

      final response = await ApiClient.getWithParams('$_baseUrl', queryParams);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch published collages: ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body);
      print('🔍 Feed collages response: $responseData');
      
      if (responseData['success'] == true && responseData['data'] != null) {
        // Handle nested structure: data.collages
        final data = responseData['data'];
        List<dynamic> collagesJson;
        
        if (data is Map<String, dynamic> && data.containsKey('collages')) {
          // Backend returns {data: {collages: [...]}}
          collagesJson = data['collages'] as List<dynamic>;
        } else if (data is List) {
          // Backend returns {data: [...]}
          collagesJson = data;
        } else {
          throw Exception('Unexpected data format: $data');
        }
        
        // Return both collage and user info
        return collagesJson.map((json) {
          final collage = Collage.fromJson(json);
          return {
            'collage': collage,
            'username': 'User ${collage.userId.substring(0, 8)}', // Temporary username
            'user_id': collage.userId,
          };
        }).toList();
      } else {
        throw Exception('Invalid response format: ${responseData['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('❌ Error fetching published collages for feed: $e');
      rethrow;
    }
  }

  /// Get all collages with optional filters
  static Future<List<Collage>> getCollages({
    String? search,
    List<String>? tags,
    String? layout,
    bool? isPublished,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (tags != null && tags.isNotEmpty) {
        queryParams['tags'] = tags.join(',');
      }
      if (layout != null && layout.isNotEmpty) {
        queryParams['layout'] = layout;
      }
      if (isPublished != null) {
        queryParams['is_published'] = isPublished.toString();
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await ApiClient.get('$_baseUrl?$queryString');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final collages = (data['data'] as List)
            .map((json) => Collage.fromJson(json))
            .toList();
        return collages;
      } else {
        throw Exception('Failed to fetch collages: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching collages: $e');
      rethrow;
    }
  }

  /// Get a single collage by ID
  static Future<Collage> getCollage(String id) async {
    try {
      final response = await ApiClient.get('$_baseUrl/$id');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Collage.fromJson(data);
      } else {
        throw Exception('Failed to fetch collage: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching collage: $e');
      rethrow;
    }
  }

  /// Create a new collage
  static Future<Collage> createCollage({
    required String title,
    String? description,
    String? coverImageUrl,
    String layout = 'grid',
    Map<String, dynamic>? settings,
    List<String>? tags,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final collageData = {
        'title': title,
        'description': (description != null && description.isNotEmpty)
            ? description
            : null,
        'cover_image_url': (coverImageUrl != null && coverImageUrl.isNotEmpty)
            ? coverImageUrl
            : null,
        'layout': layout,
        'settings': settings ?? {},
        'tags': tags ?? [],
        'items': items ?? [],
      };

      final response = await ApiClient.post(_baseUrl, collageData);
      
      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        print('🔍 CollageService response: $responseData');
        
        // Backend returns { success: true, data: { collage }, message: "..." }
        if (responseData['success'] == true && responseData['data'] != null) {
          return Collage.fromJson(responseData['data']);
        } else {
          throw Exception('Invalid response format: ${responseData}');
        }
      } else {
        throw Exception('Failed to create collage: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error creating collage: $e');
      rethrow;
    }
  }

  /// Update an existing collage
  static Future<Collage> updateCollage(String id, {
    String? title,
    String? description,
    String? coverImageUrl,
    String? layout,
    Map<String, dynamic>? settings,
    List<String>? tags,
    bool? isPublished,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (coverImageUrl != null) updateData['cover_image_url'] = coverImageUrl;
      if (layout != null) updateData['layout'] = layout;
      if (settings != null) updateData['settings'] = settings;
      if (tags != null) updateData['tags'] = tags;
      if (isPublished != null) updateData['is_published'] = isPublished;
      if (items != null) updateData['items'] = items;

      final response = await ApiClient.put('$_baseUrl/$id', updateData);
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('🔍 CollageService update response: $responseData');
        
        // Backend returns { success: true, data: { collage }, message: "..." }
        if (responseData['success'] == true && responseData['data'] != null) {
          return Collage.fromJson(responseData['data']);
        } else {
          throw Exception('Invalid response format: ${responseData}');
        }
      } else {
        throw Exception('Failed to update collage: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error updating collage: $e');
      rethrow;
    }
  }

  /// Delete a collage
  static Future<void> deleteCollage(String id) async {
    try {
      final response = await ApiClient.delete('$_baseUrl/$id');
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete collage: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error deleting collage: $e');
      rethrow;
    }
  }

  /// Add an item to a collage
  static Future<CollageItem> addCollageItem(String collageId, {
    required String imageUrl,
    required Map<String, double> position,
    required Map<String, double> size,
    double rotation = 0.0,
    double opacity = 1.0,
    int zIndex = 0,
  }) async {
    try {
      final itemData = {
        'image_url': imageUrl,
        'position': position,
        'size': size,
        'rotation': rotation,
        'opacity': opacity,
        'z_index': zIndex,
      };

      final response = await ApiClient.post('$_baseUrl/$collageId/items', itemData);
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return CollageItem.fromJson(data);
      } else {
        throw Exception('Failed to add collage item: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error adding collage item: $e');
      rethrow;
    }
  }

  /// Remove an item from a collage
  static Future<void> removeCollageItem(String collageId, String itemId) async {
    try {
      final response = await ApiClient.delete('$_baseUrl/$collageId/items/$itemId');
      
      if (response.statusCode != 200) {
        throw Exception('Failed to remove collage item: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error removing collage item: $e');
      rethrow;
    }
  }
}

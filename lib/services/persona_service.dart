import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/Persona.dart';
import '../core/api_client.dart';

class PersonaService {
  static Future<Persona> fetchPersona(String id) async {
    final response = await ApiClient.get('/personas/$id');
    if (response.statusCode == 200) {
      return compute(_parsePersona, response.body);
    } else {
      throw Exception('Failed to fetch persona: ${response.statusCode}');
    }
  }

  static Persona _parsePersona(String body) {
    final jsonData = jsonDecode(body);
    return Persona.fromJson(jsonData);
  }

  // ✅ Express backend dev route - Create persona using ApiClient
  static Future<Persona> createPersona({
    required String name,
    required String description,
    String? coverImageUrl,
    List<String> tags = const [],
    List<String> extraImageUrls = const [],
    bool isSecret = false,
  }) async {
    if (kDebugMode) {
      debugPrint('🚀 Creating persona → {name: $name, description: $description}'); // ✅ dev log
    }

    final body = {
      'name': name,
      'description': description,
      'cover_image_url': coverImageUrl,
      'tags': tags,
      'extra_image_urls': extraImageUrls,
      'is_secret': isSecret,
    };

    final response = await ApiClient.post('/personas', body); // ✅ Express backend dev route

    if (response.statusCode == 201) {
      final jsonData = jsonDecode(response.body);
      return Persona.fromJson(jsonData['data']);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['error'] ?? 'Failed to create persona: ${response.statusCode}');
    }
  }

  static Future<void> updatePersona(String id, String description, List<String> tags) async {
    debugPrint('🚀 Updating persona $id → description="$description", tags=$tags');

    final response = await ApiClient.put('/personas/$id', {
      'description': description,
      'tags': tags, // ✅ always send an array, even if empty
    });

    if (response.statusCode == 200) {
      debugPrint('✅ Persona updated successfully');
    } else {
      debugPrint('❌ Persona update failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to update persona');
    }
  }

  static Future<void> uploadImage(String personaId, File imageFile) async {
    final response = await ApiClient.upload('/personas/$personaId/items', imageFile, 'image');
    if (response.statusCode != 200) {
      throw Exception('Image upload failed: ${response.statusCode}');
    }
  }

  static Future<void> deletePersona(String id) async {
    debugPrint('🗑️ Deleting persona: $id');
    
    final response = await ApiClient.delete('/personas/$id');
    
    if (response.statusCode == 200) {
      debugPrint('✅ Persona deleted successfully');
    } else {
      debugPrint('❌ Persona deletion failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to delete persona: ${response.statusCode}');
    }
  }

  static Future<void> deletePersonaItem(String personaId, String itemId) async {
    debugPrint('🗑️ Deleting persona item: $itemId from persona: $personaId');
    
    final response = await ApiClient.delete('/personas/$personaId/items/$itemId');
    
    if (response.statusCode == 200) {
      debugPrint('✅ Persona item deleted successfully');
    } else {
      debugPrint('❌ Persona item deletion failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to delete persona item: ${response.statusCode}');
    }
  }
}


import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/room.dart';
import 'AgentService.dart';

class RoomsService {
  static String get baseUrl => AgentService.baseUrl;


  static Future<List<Room>> fetchRooms({
    required String hotelId,
    required String checkIn,
    required String checkOut,
    int guests = 2,
    int? adults,
    int? children,
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{
        'checkIn': checkIn,
        'checkOut': checkOut,
        'guests': guests.toString(),
      };

      if (adults != null) {
        queryParams['adults'] = adults.toString();
      }
      if (children != null) {
        queryParams['children'] = children.toString();
      }

      // Build URL with query parameters
      final uri = Uri.parse('$baseUrl/api/hotels/$hotelId/rooms')
          .replace(queryParameters: queryParams);

      print('🏨 Fetching rooms from: $uri');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Request timeout: Failed to fetch rooms');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final roomsData = data['rooms'] as List<dynamic>? ?? [];

        final rooms = roomsData
            .map((roomJson) => Room.fromJson(roomJson as Map<String, dynamic>))
            .toList();

        print('✅ Fetched ${rooms.length} rooms');
        return rooms;
      } else {
        print('❌ Failed to fetch rooms: ${response.statusCode}');
        throw Exception('Failed to fetch rooms: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching rooms: $e');
      rethrow;
    }
  }
}


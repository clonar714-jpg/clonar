import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/AgentService.dart';

class GeocodingService {
  
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    if (address.isEmpty) return null;

    try {
      final url = Uri.parse('${AgentService.baseUrl}/api/geocode');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'address': address}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        
        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
    } catch (e) {
      print('❌ Geocoding error: $e');
    }

    return null;
  }

  
  static Map<String, double>? extractCoordinates(Map<String, dynamic> data) {
    // Try gps_coordinates first
    final gpsCoordinates = data['gps_coordinates'];
    if (gpsCoordinates != null && gpsCoordinates is Map) {
      final lat = gpsCoordinates['latitude'];
      final lng = gpsCoordinates['longitude'];
      if (lat != null && lng != null) {
        return {
          'latitude': lat is double ? lat : double.tryParse(lat.toString()) ?? 0.0,
          'longitude': lng is double ? lng : double.tryParse(lng.toString()) ?? 0.0,
        };
      }
    }

    // Try geo field
    final geo = data['geo'];
    if (geo != null && geo is Map) {
      final lat = geo['lat'] ?? geo['latitude'];
      final lng = geo['lng'] ?? geo['longitude'];
      if (lat != null && lng != null) {
        return {
          'latitude': lat is double ? lat : double.tryParse(lat.toString()) ?? 0.0,
          'longitude': lng is double ? lng : double.tryParse(lng.toString()) ?? 0.0,
        };
      }
    }

  
    final lat = data['latitude'] ?? data['lat'];
    final lng = data['longitude'] ?? data['lng'];
    if (lat != null && lng != null) {
      return {
        'latitude': lat is double ? lat : double.tryParse(lat.toString()) ?? 0.0,
        'longitude': lng is double ? lng : double.tryParse(lng.toString()) ?? 0.0,
      };
    }

    return null;
  }
}


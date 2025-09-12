import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // Try different URLs for different environments
  static const List<String> baseUrls = [
    'http://10.0.2.2:8001',  // Android emulator
    'http://localhost:8001',  // Local development
    'http://127.0.0.1:8001', // Alternative local
  ];
  
  /// Search for products or hotels using the backend API
  static Future<Map<String, dynamic>> search(String query) async {
    Exception? lastException;
    
    for (String baseUrl in baseUrls) {
      try {
        print('Trying API at: $baseUrl');
        final response = await http.post(
          Uri.parse('$baseUrl/search'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'query': query,
          }),
        ).timeout(Duration(seconds: 10));

        print('Response status: ${response.statusCode}');
        print('Response body length: ${response.body.length}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          print('Successfully connected to: $baseUrl');
          return data;
        } else {
          lastException = Exception('Failed to search: ${response.statusCode} - ${response.body}');
        }
      } on SocketException catch (e) {
        print('SocketException for $baseUrl: $e');
        lastException = Exception('No internet connection to $baseUrl');
      } on HttpException catch (e) {
        print('HttpException for $baseUrl: $e');
        lastException = Exception('HTTP error occurred: $e');
      } on FormatException catch (e) {
        print('FormatException for $baseUrl: $e');
        lastException = Exception('Invalid response format: $e');
      } catch (e) {
        print('General error for $baseUrl: $e');
        lastException = Exception('Search failed: $e');
      }
    }
    
    throw lastException ?? Exception('All API endpoints failed');
  }
}

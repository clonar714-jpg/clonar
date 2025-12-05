import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// Singleton HTTP client for memory efficiency
class _HttpClientSingleton {
  static final _HttpClientSingleton _instance = _HttpClientSingleton._internal();
  factory _HttpClientSingleton() => _instance;
  _HttpClientSingleton._internal();
  
  late final http.Client _client;
  
  void initialize() {
    _client = http.Client();
  }
  
  http.Client get client => _client;
  
  void dispose() {
    _client.close();
  }
}

final _httpClient = _HttpClientSingleton();

/// Safe HTTP request wrapper that adds timeouts and error handling
Future<http.Response> safeRequest(Future<http.Response> future) async {
  try {
    return await future.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    return http.Response(
      jsonEncode({'success': false, 'error': 'Request timeout'}),
      408,
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    if (kDebugMode) print('HTTP request error: $e');
    return http.Response(
      jsonEncode({'success': false, 'error': e.toString()}),
      500,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// API service class for making HTTP requests with optimized memory usage
class ApiService {
  static const String baseUrl = 'http://10.0.0.127:8001';  // Python API running on port 8001
  static const String apiUrl = baseUrl;  // Python API doesn't use /api prefix
  
  // Initialize the singleton HTTP client
  static void initialize() {
    _httpClient.initialize();
  }
  
  // Dispose the singleton HTTP client
  static void dispose() {
    _httpClient.dispose();
  }

  /// Make a GET request with timeout and error handling
  static Future<http.Response> get(String endpoint, {Map<String, String>? headers}) async {
    return safeRequest(
      http.get(
        Uri.parse('$apiUrl$endpoint'),
        headers: headers,
      ),
    );
  }

  /// Make a POST request with timeout and error handling
  static Future<http.Response> post(String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return safeRequest(
      http.post(
        Uri.parse('$apiUrl$endpoint'),
        headers: headers,
        body: body,
      ),
    );
  }

  /// Make a PUT request with timeout and error handling
  static Future<http.Response> put(String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return safeRequest(
      http.put(
        Uri.parse('$apiUrl$endpoint'),
        headers: headers,
        body: body,
      ),
    );
  }

  /// Make a DELETE request with timeout and error handling
  static Future<http.Response> delete(String endpoint, {
    Map<String, String>? headers,
  }) async {
    return safeRequest(
      http.delete(
        Uri.parse('$apiUrl$endpoint'),
        headers: headers,
      ),
    );
  }

  /// Upload a file with timeout and error handling
  static Future<http.Response> uploadFile(String endpoint, {
    Map<String, String>? headers,
    required http.MultipartRequest request,
  }) async {
    return safeRequest(
      request.send().then((streamedResponse) => http.Response.fromStream(streamedResponse)),
    );
  }

  /// Search method for shopping and hotel results
  static Future<http.Response> search(String query) async {
    return safeRequest(
      http.post(
        Uri.parse('$apiUrl/search'),
        headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query': query,
          'image_url': "",
        }),
      ),
    );
  }

  /// Image-based search method for shopping and hotel results
  static Future<http.Response> searchWithImage(String query, String imageUrl) async {
    return safeRequest(
      http.post(
        Uri.parse('$apiUrl/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': query,
          'image_url': imageUrl.isNotEmpty ? imageUrl : "",
        }),
      ),
    );
  }
}
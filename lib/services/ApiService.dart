import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';


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


class ApiService {
  static const String baseUrl = 'http://10.0.0.127:8001';  
  static const String apiUrl = baseUrl;  
  
  
  static void initialize() {
    _httpClient.initialize();
  }
  
  
  static void dispose() {
    _httpClient.dispose();
  }

 
  static Future<http.Response> get(String endpoint, {Map<String, String>? headers}) async {
    return safeRequest(
      http.get(
        Uri.parse('$apiUrl$endpoint'),
        headers: headers,
      ),
    );
  }

  
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

  
  static Future<http.Response> uploadFile(String endpoint, {
    Map<String, String>? headers,
    required http.MultipartRequest request,
  }) async {
    return safeRequest(
      request.send().then((streamedResponse) => http.Response.fromStream(streamedResponse)),
    );
  }

  
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
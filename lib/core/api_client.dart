import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  // ✅ Local Express backend
  static const String baseUrl = 'http://127.0.0.1:4000/api';
  // For web/iOS: use 'http://localhost:4000/api'

  /// Builds full API URL from endpoint
  static Uri _url(String endpoint) => Uri.parse('$baseUrl$endpoint');

  /// Retrieves stored token — sends fake token in dev mode
  static Future<String?> _getToken() async {
    const bool isDev = true; // still true for local
    if (isDev) {
      debugPrint('🧪 Dev mode: sending fake token');
      return 'dev-mode-token'; // 👈 send a harmless fake token
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  static Future<void> _saveTokens(String token, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('refresh_token', refreshToken);
  }

  /// GET request
  static Future<http.Response> get(String endpoint) async =>
      _sendRequest('GET', endpoint);

  /// GET request with query parameters
  static Future<http.Response> getWithParams(String endpoint, Map<String, String> queryParams) async {
    final token = await _getToken();
    
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);

    if (kDebugMode) {
      debugPrint('🌐 GET $uri');
    }

    return await http.get(uri, headers: headers);
  }

  /// POST request
  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async =>
      _sendRequest('POST', endpoint, body: body);

  /// POST request with streaming support (returns StreamedResponse for SSE)
  static Future<http.StreamedResponse> postStream(String endpoint, Map<String, dynamic> body) async {
    final token = await _getToken();
    
    var headers = {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Accept': 'text/event-stream',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final url = _url(endpoint);
    print("🔥🔥🔥 API_CLIENT: Sending POST (stream) → $url");
    print("🔥🔥🔥 API_CLIENT: Body keys: ${body.keys.join(', ')}");
    print("🔥🔥🔥 API_CLIENT: Query: ${body['query']}");
    
    if (kDebugMode) {
      debugPrint('🌐 Sending POST (stream) → $url');
      debugPrint('📦 Body: $body');
    }

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);
    
    print("🔥🔥🔥 API_CLIENT: Request created, sending...");
    final response = await request.send();
    print("🔥🔥🔥 API_CLIENT: Response received - status: ${response.statusCode}");
    
    return response;
  }

  /// PUT request
  static Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final token = await _getToken();

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$baseUrl$endpoint');

    if (kDebugMode) {
      debugPrint('🌐 PUT $uri');
      debugPrint('📦 Body: $body');
    }

    return await http.put(uri, headers: headers, body: jsonEncode(body)); // ✅ Correct encoding
  }

  /// DELETE request
  static Future<http.Response> delete(String endpoint) async {
    final token = await _getToken();

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$baseUrl$endpoint');

    if (kDebugMode) {
      debugPrint('🌐 DELETE $uri');
    }

    return await http.delete(uri, headers: headers);
  }

  /// Multipart upload (for image or file)
  static Future<http.StreamedResponse> upload(
      String endpoint, File file, String fieldName) async {
    final token = await _getToken();
    final request = http.MultipartRequest('POST', _url(endpoint));

    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (kDebugMode && token == null) debugPrint('⚠️ Skipping token for upload (dev mode)');

    request.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    return request.send();
  }

  /// Internal request handler with dev logging and token refresh logic
  static Future<http.Response> _sendRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _getToken();

    var headers = {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    if (kDebugMode) {
      debugPrint('🌐 Sending $method → ${_url(endpoint)}'); // ✅ dev log
      if (body != null) debugPrint('📦 Body: $body');
      if (token == null) debugPrint('⚠️ Skipping token (dev mode)');
    }

    http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await http.post(_url(endpoint), headers: headers, body: jsonEncode(body));
          break;
        case 'PUT':
          response = await http.put(_url(endpoint), headers: headers, body: jsonEncode(body));
          break;
        case 'DELETE':
          response = await http.delete(_url(endpoint), headers: headers);
          break;
        default:
          response = await http.get(_url(endpoint), headers: headers);
      }

      // Auto-refresh if token expired
      if (response.statusCode == 401) {
        final refreshed = await _refreshToken();
        if (refreshed) return _sendRequest(method, endpoint, body: body);
      }

      if (kDebugMode) {
        debugPrint('🔗 ${method.toUpperCase()} $endpoint → ${response.statusCode}');
      }

      return response;
    } catch (e) {
      if (kDebugMode) debugPrint('💥 API Error [$method $endpoint]: $e');
      rethrow;
    }
  }

  /// Token refresh logic
  static Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _getRefreshToken();
      if (refreshToken == null) return false;

      final response = await http.post(
        _url('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data['token'], data['refresh_token']);
        if (kDebugMode) debugPrint('✅ Token refreshed successfully');
        return true;
      } else {
        if (kDebugMode) debugPrint('❌ Token refresh failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('💥 Refresh error: $e');
      return false;
    }
  }
}
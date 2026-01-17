import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiClient {

  static const String baseUrl = 'http://127.0.0.1:4000/api';

  
  static Uri _url(String endpoint) {
    final url = Uri.parse('$baseUrl$endpoint');
    
    if (kDebugMode) {
      debugPrint('🌐 ApiClient._url: $url');
    }
    return url;
  }

  
  static Future<String?> _getToken() async {
    const bool isDev = true; 
    if (isDev) {
      debugPrint('🧪 Dev mode: sending fake token');
      return 'dev-mode-token'; // 
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

  
  static Future<http.Response> get(String endpoint) async =>
      _sendRequest('GET', endpoint);

  
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

  
  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async =>
      _sendRequest('POST', endpoint, body: body);

  
  static Future<bool> testConnectivity() async {
    try {
      
      final testUrl = Uri.parse('http://127.0.0.1:4000/api/test');
      print("🔍 Testing connectivity to: $testUrl");
      print("🔍 Using adb reverse - ensure 'adb reverse tcp:4000 tcp:4000' is active");
      final response = await http.get(testUrl).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print("❌ Connectivity test timeout - server not reachable");
          return http.Response('Timeout', 408);
        },
      );
      print("✅ Connectivity test result: ${response.statusCode}");
      return response.statusCode == 200;
    } catch (e) {
      print("❌ Connectivity test failed: $e");
      return false;
    }
  }

  
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
    
    print(" API_CLIENT: Sending POST (stream) → $url");
    print(" API_CLIENT: Full URL: $url");
    print(" API_CLIENT: Base URL: $baseUrl");
    print(" API_CLIENT: Endpoint: $endpoint");
    print(" API_CLIENT: Body keys: ${body.keys.join(', ')}");
    print(" API_CLIENT: Query: ${body['query']}");
    
    if (kDebugMode) {
      debugPrint('🌐 Sending POST (stream) → $url');
      debugPrint('🌐 Full URL: $url');
      debugPrint('🌐 Base URL: $baseUrl');
      debugPrint('📦 Body: $body');
    }

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);
    
    print(" API_CLIENT: Request created, sending...");
    try {
      
      final response = await request.send().timeout(
        const Duration(seconds: 60), 
        onTimeout: () {
          print(" API_CLIENT: Request timeout after 60 seconds");
          print(" URL: $url");
          print(" Base URL: $baseUrl");
          print(" Troubleshooting:");
          print(" 1. Verify IP address: Run 'ipconfig' (Windows) or 'ifconfig' (Mac/Linux)");
          print(" 2. Check if server is running on port 4000");
          print(" 3. Test connectivity: Open http://127.0.0.1:4000/api/test in phone browser");
          print(" 4. Ensure device and computer are on SAME WiFi network");
          print(" 5. Check Windows Firewall - allow port 4000");
          throw TimeoutException('Streaming request timeout after 60 seconds');
        },
      );
      print(" API_CLIENT: Response received - status: ${response.statusCode}");
      print(" API_CLIENT: Response headers: ${response.headers}");
      print(" API_CLIENT: Content-Type: ${response.headers['content-type']}");
      print(" API_CLIENT: Connection: ${response.headers['connection']}");
      return response;
    } on SocketException catch (e) {
      print(" API_CLIENT: SocketException - Connection failed");
      print(" Error: $e");
      print(" This usually means:");
      print("   - Server is not running");
      print("   - Wrong IP address (current: 10.0.0.127)");
      print("   - Firewall blocking connection");
      print("   - Device and computer not on same network");
      rethrow;
    } on TimeoutException catch (e) {
      print(" API_CLIENT: TimeoutException: $e");
      rethrow;
    } catch (e, stackTrace) {
      print(" API_CLIENT: Error sending request: $e");
      print(" API_CLIENT: Error type: ${e.runtimeType}");
      print(" API_CLIENT: Stack trace: $stackTrace");
      rethrow;
    }
  }

 
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

  
  static Future<http.StreamedResponse> upload(
      String endpoint, File file, String fieldName) async {
    final token = await _getToken();
    final request = http.MultipartRequest('POST', _url(endpoint));

    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (kDebugMode && token == null) debugPrint('⚠️ Skipping token for upload (dev mode)');

    request.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    return request.send();
  }

  
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
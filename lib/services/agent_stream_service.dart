import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';


class AgentStreamService {
 
  static final AgentStreamService _instance = AgentStreamService._internal();
  factory AgentStreamService() => _instance;
  AgentStreamService._internal();

  
  late final HttpClient _httpClient;
  
  
  StreamSubscription<String>? _activeSubscription;
  String? _activeSessionId;
  
  
  String? _baseUrl;
  
  
  bool _initialized = false;

 
  void initialize(String baseUrl) {
    if (_initialized) {
      if (kDebugMode) {
        debugPrint('⚠️ AgentStreamService already initialized');
      }
      return;
    }
    
    _baseUrl = baseUrl;
    
    
    _httpClient = HttpClient();
    
    
    _httpClient.autoUncompress = true;
    _httpClient.idleTimeout = const Duration(minutes: 30); 
    _httpClient.connectionTimeout = const Duration(seconds: 60); 
    
    _initialized = true;
    
    if (kDebugMode) {
      debugPrint('✅ AgentStreamService initialized with baseUrl: $baseUrl');
      debugPrint('✅ HttpClient created ONCE - will be reused for all SSE requests');
    }
  }

  
  Future<String?> _getToken() async {
    const bool isDev = true; 
    if (isDev) {
      return 'dev-mode-token';
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  
  Future<Stream<String>> postStream(
    String endpoint,
    Map<String, dynamic> body, {
    String? sessionId,
  }) async {
    if (!_initialized) {
      throw StateError('AgentStreamService not initialized. Call initialize() first.');
    }
    
    if (_baseUrl == null) {
      throw StateError('Base URL not set. Call initialize() first.');
    }

    
    if (_activeSubscription != null) {
      if (kDebugMode) {
        debugPrint('⚠️ Canceling existing stream subscription for session: $_activeSessionId');
      }
      await _activeSubscription?.cancel();
      _activeSubscription = null;
      _activeSessionId = null;
    }

    
    final uri = Uri.parse('$_baseUrl$endpoint');
    
    if (kDebugMode) {
      debugPrint('🌐 AgentStreamService.postStream: $uri');
      debugPrint('   Session: $sessionId');
    }

   
    final request = await _httpClient.postUrl(uri);
    
    
    final token = await _getToken();
    
    
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Accept', 'text/event-stream');
    request.headers.set('Cache-Control', 'no-cache');
    request.headers.set('Pragma', 'no-cache');
    request.headers.set('Connection', 'keep-alive');
    
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }

    
    final requestBody = jsonEncode(body);
    request.contentLength = utf8.encode(requestBody).length;
    request.write(requestBody);

    if (kDebugMode) {
      debugPrint('✅ AgentStreamService: Request sent, waiting for response...');
    }

    
    final response = await request.close().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        if (kDebugMode) {
          debugPrint('❌ AgentStreamService: Connection timeout after 60 seconds');
          debugPrint('   URL: $uri');
          debugPrint('   Troubleshooting:');
          debugPrint('     1. Check if backend server is running');
          debugPrint('     2. Verify network connectivity');
          debugPrint('     3. Check backend logs for errors');
        }
        throw TimeoutException('Connection timeout: Server did not respond within 60 seconds');
      },
    );
    
    if (response.statusCode != 200) {
      
      try {
        final errorBody = await response.transform(utf8.decoder).join();
        throw HttpException('Streaming request failed: ${response.statusCode}\n$errorBody');
      } catch (e) {
        throw HttpException('Streaming request failed: ${response.statusCode}');
      }
    }

    if (kDebugMode) {
      debugPrint('✅ AgentStreamService: Response received - status: ${response.statusCode}');
      debugPrint('✅ AgentStreamService: Content-Type: ${response.headers.value('content-type')}');
      debugPrint('✅ AgentStreamService: Connection: ${response.headers.value('connection')}');
    }

    
    final stream = response.transform(utf8.decoder);
    
    
    _activeSessionId = sessionId;
    
    if (kDebugMode) {
      debugPrint('✅ AgentStreamService: Stream created for session: $sessionId');
      debugPrint('✅ AgentStreamService: Using SINGLE HttpClient instance (survives rebuilds)');
    }

    
    return stream;
  }

 
  void cancelStream(String sessionId) {
    if (_activeSessionId == sessionId) {
      if (kDebugMode) {
        debugPrint('🛑 AgentStreamService: Marking stream for cancellation - session: $sessionId');
      }
      _activeSessionId = null;
      
    }
  }

  
  String? get activeSessionId => _activeSessionId;

  
  Future<void> dispose() async {
    if (kDebugMode) {
      debugPrint('🛑 AgentStreamService.dispose() called (app shutdown)');
    }
    
    if (_activeSubscription != null) {
      await _activeSubscription?.cancel();
      _activeSubscription = null;
    }
    
    _activeSessionId = null;
    _httpClient.close(force: true);
    _initialized = false;
    
    if (kDebugMode) {
      debugPrint('✅ AgentStreamService disposed');
    }
  }
}


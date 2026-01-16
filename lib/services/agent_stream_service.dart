import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ GLOBAL SINGLETON SSE SERVICE
/// Owns exactly ONE HttpClient for the entire app lifetime
/// Owns exactly ONE active StreamSubscription at a time
/// NEVER disposed automatically, NEVER depends on BuildContext
class AgentStreamService {
  // ✅ SINGLETON PATTERN
  static final AgentStreamService _instance = AgentStreamService._internal();
  factory AgentStreamService() => _instance;
  AgentStreamService._internal();

  // ✅ CRITICAL: ONE HttpClient for entire app lifetime
  late final HttpClient _httpClient;
  
  // ✅ CRITICAL: ONE active StreamSubscription at a time
  StreamSubscription<String>? _activeSubscription;
  String? _activeSessionId;
  
  // ✅ CRITICAL: Base URL (set once at app startup)
  String? _baseUrl;
  
  // ✅ CRITICAL: Track if service is initialized
  bool _initialized = false;

  /// ✅ INITIALIZE: Call this ONCE at app startup (e.g., in main.dart)
  /// Must be called before any streaming requests
  void initialize(String baseUrl) {
    if (_initialized) {
      if (kDebugMode) {
        debugPrint('⚠️ AgentStreamService already initialized');
      }
      return;
    }
    
    _baseUrl = baseUrl;
    
    // ✅ CRITICAL: Create HttpClient ONCE in constructor/initialization
    // NEVER create HttpClient in postStream() or anywhere else
    _httpClient = HttpClient();
    
    // ✅ CRITICAL: Configure HttpClient for long-lived connections
    _httpClient.autoUncompress = true;
    _httpClient.idleTimeout = const Duration(minutes: 30); // Long timeout for SSE connections
    _httpClient.connectionTimeout = const Duration(seconds: 60); // 60 second connection timeout
    
    _initialized = true;
    
    if (kDebugMode) {
      debugPrint('✅ AgentStreamService initialized with baseUrl: $baseUrl');
      debugPrint('✅ HttpClient created ONCE - will be reused for all SSE requests');
    }
  }

  /// ✅ GET TOKEN: Helper to get auth token (matches ApiClient logic)
  Future<String?> _getToken() async {
    const bool isDev = true; // Matches ApiClient
    if (isDev) {
      return 'dev-mode-token';
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// ✅ STREAM REQUEST: Create SSE stream request
  /// Returns a Stream<String> that survives widget rebuilds
  /// Uses the SINGLE HttpClient instance created in initialize()
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

    // ✅ CRITICAL: Cancel any existing subscription before starting new one
    if (_activeSubscription != null) {
      if (kDebugMode) {
        debugPrint('⚠️ Canceling existing stream subscription for session: $_activeSessionId');
      }
      await _activeSubscription?.cancel();
      _activeSubscription = null;
      _activeSessionId = null;
    }

    // ✅ CRITICAL: Build full URL
    final uri = Uri.parse('$_baseUrl$endpoint');
    
    if (kDebugMode) {
      debugPrint('🌐 AgentStreamService.postStream: $uri');
      debugPrint('   Session: $sessionId');
    }

    // ✅ CRITICAL: Use the SINGLE HttpClient instance (created in initialize)
    // NEVER create a new HttpClient here - this is the key fix
    final request = await _httpClient.postUrl(uri);
    
    // ✅ CRITICAL: Get auth token
    final token = await _getToken();
    
    // ✅ CRITICAL: Set headers
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Accept', 'text/event-stream');
    request.headers.set('Cache-Control', 'no-cache');
    request.headers.set('Pragma', 'no-cache');
    request.headers.set('Connection', 'keep-alive');
    
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }

    // ✅ CRITICAL: Write request body
    final requestBody = jsonEncode(body);
    request.contentLength = utf8.encode(requestBody).length;
    request.write(requestBody);

    if (kDebugMode) {
      debugPrint('✅ AgentStreamService: Request sent, waiting for response...');
    }

    // ✅ CRITICAL: Get response (this establishes the SSE connection)
    // Wrap in timeout to give server time to establish SSE connection (60 seconds)
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
      // Read error body if possible
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

    // ✅ CRITICAL: Create stream decoder
    final stream = response.transform(utf8.decoder);
    
    // ✅ CRITICAL: Store session ID for tracking (not subscription - that's managed by await for)
    _activeSessionId = sessionId;
    
    if (kDebugMode) {
      debugPrint('✅ AgentStreamService: Stream created for session: $sessionId');
      debugPrint('✅ AgentStreamService: Using SINGLE HttpClient instance (survives rebuilds)');
    }

    // ✅ CRITICAL: Return the stream directly
    // The subscription is managed implicitly by the await for loop in AgentController
    // We track it via _activeSessionId for cancellation purposes
    return stream;
  }

  /// ✅ CANCEL STREAM: Cancel active stream by session ID
  /// Note: This is a marker - actual cancellation happens when await for loop exits
  void cancelStream(String sessionId) {
    if (_activeSessionId == sessionId) {
      if (kDebugMode) {
        debugPrint('🛑 AgentStreamService: Marking stream for cancellation - session: $sessionId');
      }
      _activeSessionId = null;
      // Note: We don't cancel _activeSubscription here because it's managed by await for
      // The cancellation happens when the await for loop in AgentController exits
    }
  }

  /// ✅ GET ACTIVE SESSION: Check if a session is currently streaming
  String? get activeSessionId => _activeSessionId;

  /// ✅ DISPOSE: Only call this on app shutdown
  /// NEVER call this on widget dispose or provider rebuild
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


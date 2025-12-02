import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

/// Perplexity-style persistent caching service
/// Features:
/// - Disk persistence (survives app restarts)
/// - LRU eviction (removes least recently used entries)
/// - Size limits (prevents cache from growing too large)
/// - Smart cache keys (query + context hash)
/// - Cache metadata (timestamp, size, access count)
class CacheService {
  static const String _cachePrefix = 'api_cache_';
  static const String _metadataKey = 'cache_metadata';
  static const int _maxCacheSize = 50; // Maximum number of cached responses
  static const int _maxCacheSizeBytes = 10 * 1024 * 1024; // 10MB max cache size
  static const Duration _defaultExpiry = Duration(days: 7); // 7 days default expiry
  
  /// Get smart expiry based on query type
  /// Shopping queries need shorter expiry (products change frequently)
  /// Hotel queries can have longer expiry (data changes slowly)
  static Duration getSmartExpiry(String query) {
    final lower = query.toLowerCase();
    
    // NO CACHE: Stock/availability queries (changes too fast)
    // BUT: "places available" or "attractions available" should still be cached (different context)
    if ((lower.contains('in stock') || 
         lower.contains('stock status')) &&
        !lower.contains('place') &&
        !lower.contains('attraction')) {
      return Duration.zero; // No cache
  }
  
    // NO CACHE: Real-time availability queries (but not for places)
    if (lower.contains('available now') && 
        !lower.contains('place') &&
        !lower.contains('attraction')) {
      return Duration.zero; // No cache
    }
    
    // VERY SHORT CACHE (15 min): Price-sensitive queries
    if (lower.contains('under') || 
        lower.contains('cheap') ||
        lower.contains('sale') ||
        lower.contains('discount') ||
        lower.contains('price') ||
        lower.contains('cost') ||
        lower.contains('affordable')) {
      return Duration(minutes: 15);
    }
    
    // SHORT CACHE (30 min): General shopping/product searches
    if (lower.contains('buy') ||
        lower.contains('shop') ||
        lower.contains('product') ||
        lower.contains('shopping')) {
      return Duration(minutes: 30);
    }
    
    // MEDIUM CACHE (1 hour): General product searches (best, top, review)
    if (lower.contains('best') || 
        lower.contains('top') ||
        lower.contains('review') ||
        lower.contains('compare')) {
      return Duration(hours: 1);
    }
    
    // LONG CACHE (2 hours): Brand/model searches (catalog changes slowly)
    if (lower.contains('nike') || 
        lower.contains('adidas') ||
        lower.contains('iphone') ||
        lower.contains('samsung') ||
        lower.contains('gucci') ||
        lower.contains('puma')) {
      return Duration(hours: 2);
    }
    
    // VERY LONG CACHE (7 days): Hotels, restaurants, places (data changes slowly)
    // Places queries: Tourist attractions, landmarks, things to do, etc. change very slowly
    if (lower.contains('hotel') ||
        lower.contains('resort') ||
        lower.contains('restaurant') ||
        lower.contains('cafe') ||
        lower.contains('dining') ||
        // Places/attractions queries
        lower.contains('places to visit') ||
        lower.contains('place to visit') ||
        lower.contains('things to do') ||
        lower.contains('attraction') ||
        lower.contains('attractions') ||
        lower.contains('tourist spot') ||
        lower.contains('tourist attraction') ||
        lower.contains('landmark') ||
        lower.contains('landmarks') ||
        lower.contains('sightseeing') ||
        lower.contains('must visit') ||
        lower.contains('city to visit') ||
        lower.contains('heritage site') ||
        lower.contains('cultural site') ||
        lower.contains('cultural sites') ||
        // Specific place types (these change very slowly)
        lower.contains('temple') ||
        lower.contains('temples') ||
        lower.contains('park') ||
        lower.contains('parks') ||
        lower.contains('beach') ||
        lower.contains('beaches') ||
        lower.contains('island') ||
        lower.contains('islands') ||
        lower.contains('mountain') ||
        lower.contains('mountains') ||
        lower.contains('waterfall') ||
        lower.contains('waterfalls') ||
        lower.contains('museum') ||
        lower.contains('museums') ||
        lower.contains('monument') ||
        lower.contains('monuments')) {
      return Duration(days: 7);
    }
    
    // DEFAULT: 30 minutes (safe for most queries)
    return Duration(minutes: 30);
            }
  
  // In-memory metadata for fast access
  static Map<String, CacheMetadata>? _metadataCache;
  
  /// Initialize cache service (load metadata)
  static Future<void> initialize() async {
    await _loadMetadata();
  }
  
  /// Generate smart cache key from query and context
  /// Perplexity strategy: Include query + conversation history hash
  static String generateCacheKey(
    String query, {
    List<Map<String, dynamic>>? conversationHistory,
    Map<String, dynamic>? context,
  }) {
    // Create hash from query + history + context
    final queryLower = query.trim().toLowerCase();
    final historyHash = conversationHistory?.length ?? 0;
    
    // Include context in hash if provided
    String contextHash = '';
    if (context != null) {
      final contextStr = jsonEncode({
        'intent': context['intent'],
        'cardType': context['cardType'],
        'sessionId': context['sessionId'],
      });
      contextHash = _hashString(contextStr);
    }
    
    // Create composite key
    final keyString = '${queryLower}_h${historyHash}_c$contextHash';
    return _hashString(keyString);
  }
  
  /// Hash string to create consistent cache key
  static String _hashString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 chars
  }
  
  /// Get cached response
  /// Returns null if cache miss or expired
  static Future<Map<String, dynamic>?> get(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
    
      // Check if key exists
      if (!prefs.containsKey('$_cachePrefix$cacheKey')) {
        return null;
      }
      
      // Load metadata
      await _loadMetadata();
      final metadata = _metadataCache?[cacheKey];
      
      // Check expiry
      if (metadata != null) {
        final now = DateTime.now();
        final age = now.difference(metadata.timestamp);
        if (age > metadata.expiry) {
          final ageMinutes = age.inMinutes;
          final expiryMinutes = metadata.expiry.inMinutes;
          print('⏰ Cache expired for key: $cacheKey (age: ${ageMinutes}min, expiry: ${expiryMinutes}min)');
          await _remove(cacheKey);
          return null;
        }
        
        // Log cache age
        final ageMinutes = age.inMinutes;
        final expiryMinutes = metadata.expiry.inMinutes;
        final remainingMinutes = expiryMinutes - ageMinutes;
        
        // Update access count and last accessed
        metadata.accessCount++;
        metadata.lastAccessed = now;
        await _saveMetadata();
        
        print('✅ Cache HIT for key: $cacheKey (age: ${ageMinutes}min, ${remainingMinutes}min remaining, accessed ${metadata.accessCount} times)');
      } else {
        print('✅ Cache HIT for key: $cacheKey (no metadata)');
      }
      
      // Load cached data
      final cachedData = prefs.getString('$_cachePrefix$cacheKey');
      if (cachedData == null) {
        return null;
      }
      
      return jsonDecode(cachedData) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Cache get error: $e');
      return null;
    }
  }
  
  /// Store response in cache
  /// Automatically handles LRU eviction if cache is full
  /// If expiry not provided, uses smart expiry based on query content
  static Future<void> set(
    String cacheKey,
    Map<String, dynamic> data, {
    Duration? expiry,
    String? query, // Optional: query string for smart expiry
  }) async {
    try {
      // If expiry is zero (no cache), don't store
      final finalExpiry = expiry ?? (query != null ? getSmartExpiry(query) : _defaultExpiry);
      if (finalExpiry == Duration.zero) {
        print('⏭️ Skipping cache (no cache for this query type)');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final dataString = jsonEncode(data);
      final dataSize = utf8.encode(dataString).length;
      
      // Check cache size limits
      await _enforceSizeLimits(dataSize);
    
    // Store data
      await prefs.setString('$_cachePrefix$cacheKey', dataString);
    
      // Update metadata
      await _loadMetadata();
      _metadataCache ??= {};
      _metadataCache![cacheKey] = CacheMetadata(
        key: cacheKey,
        timestamp: DateTime.now(),
        lastAccessed: DateTime.now(),
        size: dataSize,
        expiry: finalExpiry,
        accessCount: 1,
      );
      
      await _saveMetadata();
      
      // Log cache expiry info
      final expiryMinutes = finalExpiry.inMinutes;
      final expiryHours = finalExpiry.inHours;
      final expiryDays = finalExpiry.inDays;
      String expiryStr;
      if (expiryDays > 0) {
        expiryStr = '$expiryDays day${expiryDays > 1 ? 's' : ''}';
      } else if (expiryHours > 0) {
        expiryStr = '$expiryHours hour${expiryHours > 1 ? 's' : ''}';
      } else {
        expiryStr = '$expiryMinutes minute${expiryMinutes > 1 ? 's' : ''}';
      }
      
      print('💾 Cached response: $cacheKey (${(dataSize / 1024).toStringAsFixed(2)} KB, expires in $expiryStr)');
      if (query != null) {
        print('   Query: "$query" → Smart expiry: $expiryStr');
      }
    } catch (e) {
      print('❌ Cache set error: $e');
    }
  }
  
  /// Remove specific cache entry
  static Future<void> _remove(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cachePrefix$cacheKey');
      
      _metadataCache?.remove(cacheKey);
      await _saveMetadata();
    } catch (e) {
      print('❌ Cache remove error: $e');
    }
  }
  
  /// Enforce cache size limits using LRU eviction
  /// Perplexity strategy: Remove least recently used entries first
  static Future<void> _enforceSizeLimits(int newEntrySize) async {
    await _loadMetadata();
    if (_metadataCache == null || _metadataCache!.isEmpty) return;
    
    // Calculate current cache size
    int totalSize = _metadataCache!.values.fold(0, (sum, meta) => sum + meta.size);
    final entries = _metadataCache!.length;
    
    // Remove entries if we exceed limits (LRU: remove least recently accessed)
    while ((entries >= _maxCacheSize || totalSize + newEntrySize > _maxCacheSizeBytes) && 
           _metadataCache!.isNotEmpty) {
      // Find least recently used entry
      String? lruKey;
      DateTime? lruTime;
      
      _metadataCache!.forEach((key, meta) {
        if (lruTime == null || meta.lastAccessed.isBefore(lruTime!)) {
          lruTime = meta.lastAccessed;
          lruKey = key;
        }
      });
      
      if (lruKey != null) {
        final key = lruKey!; // Non-null assertion
        final removedSize = _metadataCache![key]!.size;
        await _remove(key);
        totalSize -= removedSize;
        print('🗑️ LRU eviction: Removed $key (${(removedSize / 1024).toStringAsFixed(2)} KB)');
      } else {
        break;
      }
    }
  }
  
  /// Load metadata from disk
  static Future<void> _loadMetadata() async {
    if (_metadataCache != null) return; // Already loaded
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataJson = prefs.getString(_metadataKey);
      
      if (metadataJson == null) {
        _metadataCache = {};
        return;
      }
      
      final data = jsonDecode(metadataJson) as Map<String, dynamic>;
      _metadataCache = {};
      
      data.forEach((key, value) {
        try {
          _metadataCache![key] = CacheMetadata.fromJson(value as Map<String, dynamic>);
        } catch (e) {
          print('⚠️ Failed to parse metadata for $key: $e');
        }
      });
      
      print('📦 Loaded ${_metadataCache!.length} cache entries');
    } catch (e) {
      print('❌ Failed to load metadata: $e');
      _metadataCache = {};
    }
  }
  
  /// Save metadata to disk
  static Future<void> _saveMetadata() async {
    if (_metadataCache == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataJson = jsonEncode(
        _metadataCache!.map((key, meta) => MapEntry(key, meta.toJson())),
      );
      await prefs.setString(_metadataKey, metadataJson);
    } catch (e) {
      print('❌ Failed to save metadata: $e');
    }
  }
  
  /// Clear all cache entries
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      await prefs.remove(_metadataKey);
      _metadataCache = {};
      
      print('🧹 Cache cleared');
    } catch (e) {
      print('❌ Cache clear error: $e');
    }
  }
  
  /// Get cache statistics
  static Future<CacheStats> getStats() async {
    await _loadMetadata();
    
    if (_metadataCache == null || _metadataCache!.isEmpty) {
      return CacheStats(
        entryCount: 0,
        totalSize: 0,
        hitRate: 0.0,
      );
    }
    
    final totalSize = _metadataCache!.values.fold(0, (sum, meta) => sum + meta.size);
    final totalAccesses = _metadataCache!.values.fold(0, (sum, meta) => sum + meta.accessCount);
    
    return CacheStats(
      entryCount: _metadataCache!.length,
      totalSize: totalSize,
      hitRate: totalAccesses > 0 ? totalAccesses / _metadataCache!.length : 0.0,
    );
  }
  
  /// Clean expired entries (background task)
  static Future<void> cleanExpired() async {
    await _loadMetadata();
    if (_metadataCache == null) return;
    
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    _metadataCache!.forEach((key, meta) {
      if (now.difference(meta.timestamp) > meta.expiry) {
        expiredKeys.add(key);
    }
    });
    
    for (final key in expiredKeys) {
      await _remove(key);
    }
    
    if (expiredKeys.isNotEmpty) {
      print('🧹 Cleaned ${expiredKeys.length} expired cache entries');
    }
  }
}

/// Cache metadata for tracking
class CacheMetadata {
  final String key;
  final DateTime timestamp;
  DateTime lastAccessed;
  final int size;
  final Duration expiry;
  int accessCount;
  
  CacheMetadata({
    required this.key,
    required this.timestamp,
    required this.lastAccessed,
    required this.size,
    required this.expiry,
    this.accessCount = 0,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'timestamp': timestamp.toIso8601String(),
      'lastAccessed': lastAccessed.toIso8601String(),
      'size': size,
      'expiry': expiry.inMilliseconds,
      'accessCount': accessCount,
    };
  }
  
  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      key: json['key'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      size: json['size'] as int,
      expiry: Duration(milliseconds: json['expiry'] as int),
      accessCount: json['accessCount'] as int? ?? 0,
    );
  }
}

/// Cache statistics
class CacheStats {
  final int entryCount;
  final int totalSize;
  final double hitRate;
  
  CacheStats({
    required this.entryCount,
    required this.totalSize,
    required this.hitRate,
  });
  
  String get totalSizeFormatted {
    if (totalSize < 1024) return '${totalSize}B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(2)}KB';
    return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
}


import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'cache_expiry_strategy.dart';


class CacheService {
  static const String _cachePrefix = 'api_cache_';
  static const String _metadataKey = 'cache_metadata';
  static const int _maxCacheSize = 50; 
  static const int _maxCacheSizeBytes = 10 * 1024 * 1024; 
  static const Duration _defaultExpiry = Duration(days: 7); 
  
  
  static Duration getSmartExpiry(String query) {
    return CacheExpiryStrategy.getSmartExpiry(query);
  }
  
  
  static Map<String, CacheMetadata>? _metadataCache;
  

  static Future<void> initialize() async {
    await _loadMetadata();
  }
  
  
  static String generateCacheKey(
    String query, {
    List<Map<String, dynamic>>? conversationHistory,
    Map<String, dynamic>? context,
  }) {
    
    final queryLower = query.trim().toLowerCase();
    final historyHash = conversationHistory?.length ?? 0;
    
   
    String contextHash = '';
    if (context != null) {
      final contextStr = jsonEncode({
        'intent': context['intent'],
        'cardType': context['cardType'],
        'sessionId': context['sessionId'],
      });
      contextHash = _hashString(contextStr);
    }
    
    
    final keyString = '${queryLower}_h${historyHash}_c$contextHash';
    return _hashString(keyString);
  }
  
 
  static String _hashString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 chars
  }
  
 
  static Future<Map<String, dynamic>?> get(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
     // Check if key exists
      if (!prefs.containsKey('$_cachePrefix$cacheKey')) {
        return null;
      }
      
      
      await _loadMetadata();
      final metadata = _metadataCache?[cacheKey];
      
      
      if (metadata != null) {
        final now = DateTime.now();
        final age = now.difference(metadata.timestamp);
        if (age > metadata.expiry) {
          final ageMinutes = age.inMinutes;
          final expiryMinutes = metadata.expiry.inMinutes;
          if (kDebugMode) {
            debugPrint('⏰ Cache expired for key: $cacheKey (age: ${ageMinutes}min, expiry: ${expiryMinutes}min)');
          }
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
        
        if (kDebugMode) {
          debugPrint('✅ Cache HIT for key: $cacheKey (age: ${ageMinutes}min, ${remainingMinutes}min remaining, accessed ${metadata.accessCount} times)');
        }
      } else {
        if (kDebugMode) {
          debugPrint('✅ Cache HIT for key: $cacheKey (no metadata)');
        }
      }
      
      // Load cached data
      final cachedData = prefs.getString('$_cachePrefix$cacheKey');
      if (cachedData == null) {
        return null;
      }
      
      return jsonDecode(cachedData) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Cache get error: $e');
      }
      return null;
    }
  }
  
  
  static Future<void> set(
    String cacheKey,
    Map<String, dynamic> data, {
    Duration? expiry,
    String? query,
  }) async {
    try {
      
      final finalExpiry = expiry ?? (query != null ? getSmartExpiry(query) : _defaultExpiry);
      if (finalExpiry == Duration.zero) {
        if (kDebugMode) {
          debugPrint('⏭️ Skipping cache (no cache for this query type)');
        }
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
      
      if (kDebugMode) {
        debugPrint('💾 Cached response: $cacheKey (${(dataSize / 1024).toStringAsFixed(2)} KB, expires in $expiryStr)', wrapWidth: 1024);
        if (query != null) {
          debugPrint('   Query: "$query" → Smart expiry: $expiryStr', wrapWidth: 1024);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Cache set error: $e');
      }
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
      if (kDebugMode) {
        debugPrint('❌ Cache remove error: $e');
      }
    }
  }
  
  
  static Future<void> _enforceSizeLimits(int newEntrySize) async {
    await _loadMetadata();
    if (_metadataCache == null || _metadataCache!.isEmpty) return;
    
    
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
        if (kDebugMode) {
          debugPrint('🗑️ LRU eviction: Removed $key (${(removedSize / 1024).toStringAsFixed(2)} KB)');
        }
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
          if (kDebugMode) {
            debugPrint('⚠️ Failed to parse metadata for $key: $e');
          }
        }
      });
      
      if (kDebugMode) {
        debugPrint('📦 Loaded ${_metadataCache!.length} cache entries');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load metadata: $e');
      }
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
      if (kDebugMode) {
        debugPrint('❌ Failed to save metadata: $e');
      }
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
      
      if (kDebugMode) {
        debugPrint('🧹 Cache cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Cache clear error: $e');
      }
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
      if (kDebugMode) {
        debugPrint('🧹 Cleaned ${expiredKeys.length} expired cache entries');
      }
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


import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/foundation.dart';

class AppProviderObserver extends ProviderObserver {
  // ✅ PRODUCTION: Throttle logging to prevent excessive output
  DateTime? _lastLogTime;
  static const Duration _minLogInterval = Duration(seconds: 2); // Increased to 2 seconds

  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      final providerName = provider.name ?? '';
      
      // ✅ PRODUCTION: Skip logging for high-frequency providers
      if (providerName.contains('streamingTextProvider') || 
          providerName.contains('queryProvider') ||
          providerName.contains('debouncedQueryProvider')) {
        return; // Don't log these - they update too frequently
      }

      // ✅ PRODUCTION: Throttle other provider logs
      final now = DateTime.now();
      if (_lastLogTime != null && 
          now.difference(_lastLogTime!) < _minLogInterval) {
        return; // Skip if logged too recently
      }

      // ✅ PRODUCTION: Truncate long values to prevent log spam
      final valueStr = newValue.toString();
      final truncatedValue = valueStr.length > 100 
          ? '${valueStr.substring(0, 100)}...' 
          : valueStr;
      
      debugPrint("🔄 Provider Updated → $providerName, New Value: $truncatedValue");
      _lastLogTime = now;
    }
  }

  void handleError(
    ProviderBase provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    debugPrint("❌ Provider Error in ${provider.name}: $error");
  }
}


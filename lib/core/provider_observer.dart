import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/foundation.dart';

class AppProviderObserver extends ProviderObserver {
  
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
      
      
      if (providerName.contains('streamingTextProvider') || 
          providerName.contains('queryProvider') ||
          providerName.contains('debouncedQueryProvider')) {
        return; 
      }

      
      final now = DateTime.now();
      if (_lastLogTime != null && 
          now.difference(_lastLogTime!) < _minLogInterval) {
        return; 
      }

      
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


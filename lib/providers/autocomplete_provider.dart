import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../core/api_client.dart';

/// ✅ PHASE 7: Enhanced autocomplete provider with throttle + debounce + request cancellation
final autocompleteProvider =
    StateNotifierProvider<AutocompleteNotifier, AsyncValue<List<String>>>(
  (ref) {
    ref.keepAlive();
    return AutocompleteNotifier();
  },
);

class AutocompleteNotifier extends StateNotifier<AsyncValue<List<String>>> {
  Timer? _debounceTimer;
  Timer? _throttleTimer;
  String? _lastQuery;
  DateTime? _lastRequestTime;
  // Note: ApiClient doesn't expose Request objects, so we track pending state instead
  bool _isRequestPending = false;

  AutocompleteNotifier() : super(const AsyncValue.data([]));

  /// ✅ PRODUCTION: Autocomplete feature disabled to prevent freezes
  /// This method now does nothing - no API calls will be made
  void fetch(String query) {
    // ✅ PRODUCTION: Completely disabled - return immediately without any processing
    // This prevents any autocomplete API calls that were causing freezes
    if (query.isEmpty) {
      state = const AsyncValue.data([]);
      _lastQuery = null;
    }
    // Cancel any pending timers
    _debounceTimer?.cancel();
    _throttleTimer?.cancel();
    // Do NOT call _executeFetch - autocomplete is completely disabled
    return;
  }

  /// Execute the actual fetch request
  Future<void> _executeFetch(String query) async {
    if (_isRequestPending) {
      if (kDebugMode) {
        debugPrint('⏭️ Autocomplete request already pending, skipping');
      }
      return;
    }

    _lastRequestTime = DateTime.now();
    _isRequestPending = true;

    try {
      final res = await ApiClient.getWithParams("/autocomplete", {"q": query});

      if (res.statusCode == 200) {
        final list = List<String>.from(jsonDecode(res.body));
        // Only update if this is still the latest query
        if (query == _lastQuery) {
          state = AsyncValue.data(list);
        }
      } else {
        if (query == _lastQuery) {
          state = AsyncValue.error('HTTP ${res.statusCode}', StackTrace.current);
        }
      }
    } catch (e) {
      // Only update if this is still the latest query
      if (query == _lastQuery) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    } finally {
      _isRequestPending = false;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _throttleTimer?.cancel();
    super.dispose();
  }
}


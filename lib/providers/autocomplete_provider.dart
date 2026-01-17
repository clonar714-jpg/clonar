import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../core/api_client.dart';


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
  
  bool _isRequestPending = false;

  AutocompleteNotifier() : super(const AsyncValue.data([]));

 
  void fetch(String query) {
    
    if (query.isEmpty) {
      state = const AsyncValue.data([]);
      _lastQuery = null;
    }
    
    _debounceTimer?.cancel();
    _throttleTimer?.cancel();
    
    return;
  }

  
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
        
        if (query == _lastQuery) {
          state = AsyncValue.data(list);
        }
      } else {
        if (query == _lastQuery) {
          state = AsyncValue.error('HTTP ${res.statusCode}', StackTrace.current);
        }
      }
    } catch (e) {
      
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


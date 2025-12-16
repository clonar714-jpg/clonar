import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ PRODUCTION-GRADE: Query provider with debouncing to prevent excessive updates
/// This provider should only be updated on submit or when needed, not on every keystroke
final queryProvider = StateProvider<String>((ref) => "");

/// ✅ PRODUCTION: Local text state for TextField (doesn't trigger provider updates)
/// This is used internally by ShopScreen to track text field state without causing rebuilds
final localQueryTextProvider = StateProvider<String>((ref) => "");

final isQueryTypingProvider = StateProvider<bool>((ref) => false);

/// ✅ PRODUCTION: Debounced query provider for autocomplete (updates after user stops typing)
final debouncedQueryProvider = StateNotifierProvider<DebouncedQueryNotifier, String>((ref) {
  return DebouncedQueryNotifier();
});

class DebouncedQueryNotifier extends StateNotifier<String> {
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  DebouncedQueryNotifier() : super("");

  void update(String query) {
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      state = "";
      return;
    }

    _debounceTimer = Timer(_debounceDelay, () {
      if (query != state) {
        state = query;
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}


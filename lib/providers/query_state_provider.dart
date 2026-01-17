import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';


final queryProvider = StateProvider<String>((ref) => "");


final localQueryTextProvider = StateProvider<String>((ref) => "");

final isQueryTypingProvider = StateProvider<bool>((ref) => false);


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


import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ PRODUCTION: Simplified streaming text provider
/// Now just holds the target text - animation is handled by StreamingTextWidget
/// This prevents provider updates from causing rebuilds
class StreamingTextNotifier extends StateNotifier<String> {
  StreamingTextNotifier() : super('');

  /// Set target text (animation handled by widget)
  void start(String targetText) {
    state = targetText;
  }

  /// Reset streaming state
  void reset() {
    state = '';
  }

  /// Set text immediately (no animation)
  void setImmediate(String text) {
    state = text;
  }
}

/// ✅ PRODUCTION: Simplified provider - just holds text, no animation logic
final streamingTextProvider =
    StateNotifierProvider<StreamingTextNotifier, String>(
  (ref) {
    ref.keepAlive();
    return StreamingTextNotifier();
  },
);


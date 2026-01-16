import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ PERPLEXITY-STYLE: Stream controller for text chunks (separate from session)
/// Text chunks flow through stream, NOT through session updates
/// This prevents widget rebuilds on every chunk
class SessionStreamNotifier extends StateNotifier<StreamController<String>?> {
  SessionStreamNotifier() : super(null);
  
  // ✅ PERPLEXITY-STYLE: Accumulate text internally (stream sends full text each time)
  String _accumulatedText = '';

  /// Initialize stream for a session
  void initialize(String sessionId) {
    state?.close(); // Close previous stream if exists
    _accumulatedText = ''; // Reset accumulator
    state = StreamController<String>.broadcast();
  }

  /// Add text chunk to stream (does NOT update session)
  /// Stream sends accumulated text so StreamBuilder can display full text
  void addChunk(String chunk) {
    if (chunk.isNotEmpty) {
      _accumulatedText += chunk;
      state?.add(_accumulatedText); // Send full accumulated text
    }
  }

  /// Close stream
  void close() {
    state?.close();
    state = null;
    _accumulatedText = '';
  }
}

/// ✅ PERPLEXITY-STYLE: Stream controller provider (one per session)
final sessionStreamProvider = StateNotifierProvider<SessionStreamNotifier, StreamController<String>?>((ref) {
  ref.keepAlive();
  return SessionStreamNotifier();
});

/// ✅ PERPLEXITY-STYLE: Get stream for a specific session
final sessionStreamFamilyProvider = Provider.family<Stream<String>?, String>((ref, sessionId) {
  final controller = ref.watch(sessionStreamProvider);
  return controller?.stream;
});


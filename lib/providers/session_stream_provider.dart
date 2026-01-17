import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class SessionStreamNotifier extends StateNotifier<StreamController<String>?> {
  SessionStreamNotifier() : super(null);
  
  
  String _accumulatedText = '';

 
  void initialize(String sessionId) {
    state?.close(); 
    _accumulatedText = ''; 
    state = StreamController<String>.broadcast();
  }


  void addChunk(String chunk) {
    if (chunk.isNotEmpty) {
      _accumulatedText += chunk;
      state?.add(_accumulatedText); 
    }
  }

  
  void close() {
    state?.close();
    state = null;
    _accumulatedText = '';
  }
}


final sessionStreamProvider = StateNotifierProvider<SessionStreamNotifier, StreamController<String>?>((ref) {
  ref.keepAlive();
  return SessionStreamNotifier();
});


final sessionStreamFamilyProvider = Provider.family<Stream<String>?, String>((ref, sessionId) {
  final controller = ref.watch(sessionStreamProvider);
  return controller?.stream;
});


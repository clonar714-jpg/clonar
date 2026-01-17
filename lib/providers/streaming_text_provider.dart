import 'package:flutter_riverpod/flutter_riverpod.dart';


class StreamingTextNotifier extends StateNotifier<String> {
  StreamingTextNotifier() : super('');

  
  void start(String targetText) {
    state = targetText;
  }


  void reset() {
    state = '';
  }

  
  void setImmediate(String text) {
    state = text;
  }
}


final streamingTextProvider =
    StateNotifierProvider<StreamingTextNotifier, String>(
  (ref) {
    ref.keepAlive();
    return StreamingTextNotifier();
  },
);


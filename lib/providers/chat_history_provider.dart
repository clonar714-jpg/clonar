import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ChatHistoryServiceCloud.dart';
import '../screens/ShopScreen.dart';

/// ✅ STARTUP FIX: Lazy FutureProvider - only loads when first accessed
/// This prevents eager loading during app startup
final chatHistoryProvider =
    FutureProvider<List<ChatHistoryItem>>.autoDispose((ref) {
  // ✅ STARTUP FIX: Defer loading until after first frame
  // This provider is only accessed when ShopScreen drawer is opened
  return ChatHistoryServiceCloud.loadChatHistory();
});

final chatHistoryRefreshProvider =
    StateProvider<int>((ref) => 0);

void refreshChatHistory(Ref ref) {
  ref.read(chatHistoryRefreshProvider.notifier).state++;
}


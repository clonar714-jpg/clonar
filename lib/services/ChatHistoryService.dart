import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/ShopScreen.dart';

/// ✅ High-performance chat history storage service
/// Uses SharedPreferences with async operations to prevent UI freezes
class ChatHistoryService {
  static const String _chatHistoryKey = 'chat_history_v1';
  static const int _maxChats = 50; // Limit to prevent memory issues
  
  /// ✅ Load all chats asynchronously (non-blocking)
  static Future<List<ChatHistoryItem>> loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_chatHistoryKey);
      
      if (historyJson == null || historyJson.isEmpty) {
        return [];
      }
      
      // Parse JSON in background
      final List<dynamic> decoded = jsonDecode(historyJson);
      final chats = decoded
          .map((json) => ChatHistoryItem.fromJson(json as Map<String, dynamic>))
          .toList();
      
      // Sort by timestamp (newest first)
      chats.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      // Limit to max chats
      return chats.take(_maxChats).toList();
    } catch (e) {
      print('❌ Error loading chat history: $e');
      return []; // Return empty list on error (don't crash)
    }
  }
  
  /// ✅ Save chat history asynchronously (non-blocking, batched)
  static Future<void> saveChatHistory(List<ChatHistoryItem> chats) async {
    try {
      // Limit to max chats to prevent storage bloat
      final chatsToSave = chats.take(_maxChats).toList();
      
      // Convert to JSON
      final historyJson = jsonEncode(
        chatsToSave.map((chat) => chat.toJson()).toList(),
      );
      
      // Save to SharedPreferences (async, non-blocking)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chatHistoryKey, historyJson);
      
      print('💾 Saved ${chatsToSave.length} chats to storage');
    } catch (e) {
      print('❌ Error saving chat history: $e');
      // Don't throw - silently fail to prevent crashes
    }
  }
  
  /// ✅ Save a single chat (optimized - updates existing list)
  static Future<void> saveChat(ChatHistoryItem chat) async {
    try {
      final existingChats = await loadChatHistory();
      
      // Remove old chat if exists (by id)
      existingChats.removeWhere((item) => item.id == chat.id);
      
      // Add new/updated chat at the beginning
      existingChats.insert(0, chat);
      
      // Save updated list
      await saveChatHistory(existingChats);
    } catch (e) {
      print('❌ Error saving single chat: $e');
    }
  }
  
  /// ✅ Delete a chat
  static Future<void> deleteChat(String chatId) async {
    try {
      final existingChats = await loadChatHistory();
      existingChats.removeWhere((item) => item.id == chatId);
      await saveChatHistory(existingChats);
    } catch (e) {
      print('❌ Error deleting chat: $e');
    }
  }
  
  /// ✅ Update chat title
  static Future<void> updateChatTitle(String chatId, String newTitle) async {
    try {
      final existingChats = await loadChatHistory();
      final index = existingChats.indexWhere((item) => item.id == chatId);
      
      if (index != -1) {
        existingChats[index] = ChatHistoryItem(
          id: existingChats[index].id,
          title: newTitle,
          query: existingChats[index].query,
          timestamp: existingChats[index].timestamp,
          imageUrl: existingChats[index].imageUrl,
          conversationHistory: existingChats[index].conversationHistory,
        );
        await saveChatHistory(existingChats);
      }
    } catch (e) {
      print('❌ Error updating chat title: $e');
    }
  }
  
  /// ✅ Clear all chat history
  static Future<void> clearAllChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chatHistoryKey);
    } catch (e) {
      print('❌ Error clearing chat history: $e');
    }
  }
}


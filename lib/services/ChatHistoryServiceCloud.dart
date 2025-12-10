import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/ShopScreen.dart';
import '../core/api_client.dart';

/// ✅ Cloud-based chat history service with local cache
/// Hybrid approach: Local cache for instant loading + Cloud database for persistence
/// Similar to ChatGPT's architecture
class ChatHistoryServiceCloud {
  static const String _localCacheKey = 'chat_history_local_cache_v1';
  static const String _lastSyncKey = 'chat_history_last_sync';
  static const int _maxChats = 50;
  
  /// ✅ Load chats: Local cache first (instant), then sync with cloud
  static Future<List<ChatHistoryItem>> loadChatHistory() async {
    try {
      // 1. Load from local cache first (instant, 0ms latency)
      final localChats = await _loadFromLocalCache();
      
      // 2. Sync with cloud in background (non-blocking)
      _syncWithCloud().catchError((e) {
        print('⚠️ Cloud sync failed (using local cache): $e');
      });
      
      return localChats;
    } catch (e) {
      print('❌ Error loading chat history: $e');
      return [];
    }
  }
  
  /// ✅ Load from local cache (instant)
  static Future<List<ChatHistoryItem>> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_localCacheKey);
      
      if (historyJson == null || historyJson.isEmpty) {
        return [];
      }
      
      final List<dynamic> decoded = jsonDecode(historyJson);
      final chats = decoded
          .map((json) => ChatHistoryItem.fromJson(json as Map<String, dynamic>))
          .toList();
      
      chats.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return chats.take(_maxChats).toList();
    } catch (e) {
      print('❌ Error loading local cache: $e');
      return [];
    }
  }
  
  /// ✅ Sync with cloud (background, non-blocking)
  static Future<void> _syncWithCloud() async {
    try {
      final response = await ApiClient.get('/chats')
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final conversations = data['conversations'] as List? ?? [];
        
        // Convert cloud format to local format
        final chats = conversations.map((conv) {
          return ChatHistoryItem(
            id: conv['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
            title: conv['title'] as String? ?? 'Untitled',
            query: conv['query'] as String? ?? '',
            timestamp: conv['created_at'] != null
                ? DateTime.parse(conv['created_at'] as String)
                : DateTime.now(),
            imageUrl: conv['image_url'] as String?,
            conversationHistory: null, // Will be loaded on demand
          );
        }).toList();
        
        // Update local cache
        await _saveToLocalCache(chats);
        
        // Update last sync timestamp
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
        
        print('✅ Synced ${chats.length} chats from cloud');
      }
    } catch (e) {
      print('⚠️ Cloud sync error: $e');
      // Don't throw - continue with local cache
    }
  }
  
  /// ✅ Save chat to both local cache and cloud
  static Future<void> saveChat(ChatHistoryItem chat) async {
    try {
      // 1. Save to local cache first (instant)
      await _saveToLocalCache([chat]);
      
      // 2. Save to cloud in background (non-blocking)
      _saveToCloud(chat).catchError((e) {
        print('⚠️ Cloud save failed (local saved): $e');
      });
    } catch (e) {
      print('❌ Error saving chat: $e');
    }
  }
  
  /// ✅ Save to local cache
  static Future<void> _saveToLocalCache(List<ChatHistoryItem> newChats) async {
    try {
      final existingChats = await _loadFromLocalCache();
      
      // Merge: Remove old versions, add new ones
      for (final newChat in newChats) {
        existingChats.removeWhere((item) => item.id == newChat.id);
        existingChats.insert(0, newChat);
      }
      
      // Limit to max chats
      final chatsToSave = existingChats.take(_maxChats).toList();
      
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(
        chatsToSave.map((chat) => chat.toJson()).toList(),
      );
      
      await prefs.setString(_localCacheKey, historyJson);
    } catch (e) {
      print('❌ Error saving to local cache: $e');
    }
  }
  
  /// ✅ Save to cloud (background, non-blocking)
  static Future<void> _saveToCloud(ChatHistoryItem chat) async {
    try {
      // Check if chat already exists in cloud
      final existingResponse = await ApiClient.get('/chats/${chat.id}')
          .timeout(const Duration(seconds: 5));
      
      if (existingResponse.statusCode == 200) {
        // Update existing conversation
        await ApiClient.put('/chats/${chat.id}', {
          'title': chat.title,
        }).timeout(const Duration(seconds: 5));
      } else {
        // Create new conversation
        await ApiClient.post('/chats', {
          'title': chat.title,
          'query': chat.query,
          'imageUrl': chat.imageUrl,
        }).timeout(const Duration(seconds: 5));
      }
      
      // Save conversation history if available
      if (chat.conversationHistory != null && chat.conversationHistory!.isNotEmpty) {
        for (final session in chat.conversationHistory!) {
          await ApiClient.post('/chats/${chat.id}/messages', {
            'query': session['query'] as String? ?? '',
            'summary': session['summary'] as String?,
            'intent': session['intent'] as String?,
            'cardType': session['cardType'] as String?,
            'cards': session['cards'],
            'results': session['results'],
            'sections': session['sections'],
            'answer': session['answer'],
            'imageUrl': session['imageUrl'] as String?,
          }).timeout(const Duration(seconds: 5));
        }
      }
      
      print('✅ Saved chat to cloud: ${chat.title}');
    } catch (e) {
      print('⚠️ Cloud save error: $e');
      // Don't throw - local cache is already saved
    }
  }
  
  /// ✅ Delete chat from both local cache and cloud
  static Future<void> deleteChat(String chatId) async {
    try {
      // 1. Delete from local cache first
      final existingChats = await _loadFromLocalCache();
      existingChats.removeWhere((item) => item.id == chatId);
      
      // Save updated list
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(
        existingChats.map((chat) => chat.toJson()).toList(),
      );
      await prefs.setString(_localCacheKey, historyJson);
      
      // 2. Delete from cloud in background
      _deleteFromCloud(chatId).catchError((e) {
        print('⚠️ Cloud delete failed (local deleted): $e');
      });
    } catch (e) {
      print('❌ Error deleting chat: $e');
    }
  }
  
  /// ✅ Delete from cloud (background, non-blocking)
  static Future<void> _deleteFromCloud(String chatId) async {
    try {
      await ApiClient.delete('/chats/$chatId')
          .timeout(const Duration(seconds: 5));
      
      print('✅ Deleted chat from cloud: $chatId');
    } catch (e) {
      print('⚠️ Cloud delete error: $e');
    }
  }
  
  /// ✅ Load full conversation history from cloud (on demand)
  static Future<List<Map<String, dynamic>>?> loadConversationHistory(String chatId) async {
    try {
      final response = await ApiClient.get('/chats/$chatId')
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final messages = data['messages'] as List? ?? [];
        
        // Convert to conversation history format
        return messages.map((msg) {
          return {
            'query': msg['query'] as String? ?? '',
            'summary': msg['summary'] as String?,
            'intent': msg['intent'] as String?,
            'cardType': msg['card_type'] as String?,
            'cards': msg['cards'] != null ? jsonDecode(msg['cards'] as String) : null,
            'results': msg['results'] != null ? jsonDecode(msg['results'] as String) : null,
            'sections': msg['sections'] != null ? jsonDecode(msg['sections'] as String) : null,
            'answer': msg['answer'] != null ? jsonDecode(msg['answer'] as String) : null,
            'imageUrl': msg['image_url'] as String?,
          };
        }).toList();
      }
      
      return null;
    } catch (e) {
      print('❌ Error loading conversation history: $e');
      return null;
    }
  }
}


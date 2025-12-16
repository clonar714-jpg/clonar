import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/ShopScreen.dart';
import '../core/api_client.dart';

// ✅ PRODUCTION: Top-level function for isolate (must be top-level for compute)
List<ChatHistoryItem> _parseChatHistoryJson(String historyJson) {
  try {
    final List<dynamic> decoded = jsonDecode(historyJson);
    final chats = decoded
        .map((json) => ChatHistoryItem.fromJson(json as Map<String, dynamic>))
        .toList();
    
    chats.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return chats.take(50).toList(); // Max 50 chats
  } catch (e) {
    // Can't use kDebugMode in isolate, so just return empty
    return [];
  }
}

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
      
      // 2. Sync with cloud in background (non-blocking, deferred to prevent startup freeze)
      // ✅ PRODUCTION: Defer cloud sync to prevent blocking startup
      Future.delayed(const Duration(seconds: 3), () {
        _syncWithCloud().catchError((e) {
          if (kDebugMode) {
            debugPrint('⚠️ Cloud sync failed (using local cache): $e');
          }
        });
      });
      
      return localChats;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading chat history: $e');
      }
      return [];
    }
  }
  
  /// ✅ Load from local cache (instant)
  /// ✅ PRODUCTION FIX: Move JSON decoding to microtask to prevent UI freeze
  static Future<List<ChatHistoryItem>> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_localCacheKey);
      
      if (historyJson == null || historyJson.isEmpty) {
        return [];
      }
      
      // ✅ PRODUCTION: Parse JSON in isolate for large datasets (31 chats with conversation history)
      // This prevents blocking the UI thread during startup
      return await compute(_parseChatHistoryJson, historyJson);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading local cache: $e');
      }
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
        
        if (kDebugMode) {
          debugPrint('✅ Synced ${chats.length} chats from cloud');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Cloud sync error: $e');
      }
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
        if (kDebugMode) {
          debugPrint('⚠️ Cloud save failed (local saved): $e');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving chat: $e');
      }
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
      
      // ✅ PRODUCTION FIX: Move JSON encoding to microtask to prevent UI freeze
      final prefs = await SharedPreferences.getInstance();
      final historyJson = await Future.microtask(() => jsonEncode(
        chatsToSave.map((chat) => chat.toJson()).toList(),
      ));
      
      await prefs.setString(_localCacheKey, historyJson);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving to local cache: $e');
      }
    }
  }
  
  /// ✅ Save to cloud (background, non-blocking)
  /// Production-grade: Handles errors gracefully, ensures conversation exists before saving messages
  static Future<void> _saveToCloud(ChatHistoryItem chat) async {
    try {
      // ✅ Step 1: Ensure conversation exists in cloud
      // Try to get existing conversation first
      final existingResponse = await ApiClient.get('/chats/${chat.id}')
          .timeout(const Duration(seconds: 5));
      
      if (existingResponse.statusCode == 200) {
        // Conversation exists, just update title if needed
        try {
          await ApiClient.put('/chats/${chat.id}', {
            'title': chat.title,
          }).timeout(const Duration(seconds: 5));
        } catch (e) {
          // Title update failed, but conversation exists - continue
          if (kDebugMode) {
            debugPrint('⚠️ Failed to update conversation title: $e');
          }
        }
      } else {
        // Conversation doesn't exist, create it
        try {
          final createResponse = await ApiClient.post('/chats', {
            'title': chat.title,
            'query': chat.query,
            'imageUrl': chat.imageUrl,
          }).timeout(const Duration(seconds: 5));
          
          if (createResponse.statusCode != 201 && createResponse.statusCode != 200) {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to create conversation: ${createResponse.statusCode}');
            }
            // Don't throw - will try to save messages anyway (backend will auto-create)
          }
        } catch (e) {
          // Creation failed, but backend will auto-create when saving messages
          if (kDebugMode) {
            debugPrint('⚠️ Failed to create conversation, will rely on auto-create: $e');
          }
        }
      }
      
      // ✅ Step 2: Save conversation history (messages)
      // Backend will auto-create conversation if it doesn't exist (idempotent)
      // Backend may return a different conversation ID if numeric ID was converted to UUID
      String actualConversationId = chat.id;
      
      if (chat.conversationHistory != null && chat.conversationHistory!.isNotEmpty) {
        int successCount = 0;
        int failCount = 0;
        
        for (final session in chat.conversationHistory!) {
          try {
            final messageResponse = await ApiClient.post('/chats/$actualConversationId/messages', {
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
            
            if (messageResponse.statusCode == 201 || messageResponse.statusCode == 200) {
              successCount++;
              
              // ✅ Update conversation ID if backend returned a different one
              try {
                final responseBody = jsonDecode(messageResponse.body);
                if (responseBody is Map && responseBody.containsKey('conversationId')) {
                  final returnedId = responseBody['conversationId'] as String?;
                  if (returnedId != null && returnedId != actualConversationId) {
                    actualConversationId = returnedId;
                    if (kDebugMode) {
                      debugPrint('🔄 Updated conversation ID: ${chat.id} → $actualConversationId');
                    }
                  }
                }
              } catch (e) {
                // Ignore JSON parse errors
              }
            } else {
              failCount++;
              if (kDebugMode) {
                debugPrint('⚠️ Failed to save message: ${messageResponse.statusCode}');
              }
            }
          } catch (e) {
            failCount++;
            if (kDebugMode) {
              debugPrint('⚠️ Error saving message: $e');
            }
            // Continue with next message (don't fail entire sync)
          }
        }
        
        if (kDebugMode) {
          debugPrint('💾 Saved ${successCount}/${chat.conversationHistory!.length} messages to cloud');
          if (failCount > 0) {
            debugPrint('⚠️ Failed to save $failCount messages');
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ Saved chat to cloud: ${chat.title}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Cloud save error: $e');
      }
      // Don't throw - local cache is already saved
      // User can retry sync later
    }
  }
  
  /// ✅ Delete chat from both local cache and cloud
  static Future<void> deleteChat(String chatId) async {
    try {
      // 1. Delete from local cache first
      final existingChats = await _loadFromLocalCache();
      existingChats.removeWhere((item) => item.id == chatId);
      
      // ✅ PRODUCTION FIX: Move JSON encoding to microtask
      final prefs = await SharedPreferences.getInstance();
      final historyJson = await Future.microtask(() => jsonEncode(
        existingChats.map((chat) => chat.toJson()).toList(),
      ));
      await prefs.setString(_localCacheKey, historyJson);
      
      // 2. Delete from cloud in background
      _deleteFromCloud(chatId).catchError((e) {
        if (kDebugMode) {
          debugPrint('⚠️ Cloud delete failed (local deleted): $e');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error deleting chat: $e');
      }
    }
  }
  
  /// ✅ Delete from cloud (background, non-blocking)
  static Future<void> _deleteFromCloud(String chatId) async {
    try {
      await ApiClient.delete('/chats/$chatId')
          .timeout(const Duration(seconds: 5));
      
      if (kDebugMode) {
        debugPrint('✅ Deleted chat from cloud: $chatId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Cloud delete error: $e');
      }
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
      if (kDebugMode) {
        debugPrint('❌ Error loading conversation history: $e');
      }
      return null;
    }
  }
}


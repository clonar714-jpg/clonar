import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/ShopScreen.dart';
import '../core/api_client.dart';


List<ChatHistoryItem> _parseChatHistoryJson(String historyJson) {
  try {
    final List<dynamic> decoded = jsonDecode(historyJson);
    final chats = decoded
        .map((json) => ChatHistoryItem.fromJson(json as Map<String, dynamic>))
        .toList();
    
    chats.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return chats.take(50).toList(); 
  } catch (e) {
    
    return [];
  }
}


class _CachedMessages {
  final Set<String> queries;
  final DateTime timestamp;
  static const Duration _cacheTTL = Duration(seconds: 5);
  
  _CachedMessages(this.queries, this.timestamp);
  
  bool get isExpired => DateTime.now().difference(timestamp) > _cacheTTL;
}


class ChatHistoryServiceCloud {
  static const String _localCacheKey = 'chat_history_local_cache_v1';
  static const String _lastSyncKey = 'chat_history_last_sync';
  static const int _maxChats = 50;
  
  
  static final Map<String, _CachedMessages> _messagesCache = {};
  
  
  static final Map<String, Timer> _pendingSaves = {};
  static final Map<String, ChatHistoryItem> _pendingChats = {};
  static const Duration _saveDebounceDelay = Duration(seconds: 2);
  
  
  static Future<List<ChatHistoryItem>> loadChatHistory() async {
    try {
      
      final localChats = await _loadFromLocalCache();
      
      
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
  
  
  static Future<List<ChatHistoryItem>> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_localCacheKey);
      
      if (historyJson == null || historyJson.isEmpty) {
        return [];
      }
      
     
      return await compute(_parseChatHistoryJson, historyJson);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading local cache: $e');
      }
      return [];
    }
  }
  
  
  static Future<void> _syncWithCloud() async {
    try {
      final response = await ApiClient.get('/chats')
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final conversations = data['conversations'] as List? ?? [];
        
        
        final chats = conversations.map((conv) {
          final id = conv['id'] as String?;
          
          if (id == null || id.isEmpty) {
            if (kDebugMode) {
              debugPrint('⚠️ Skipping conversation without UUID: ${conv['title']}');
            }
            return null;
          }
          
          return ChatHistoryItem(
            id: id, 
            title: conv['title'] as String? ?? 'Untitled',
            query: conv['query'] as String? ?? '',
            timestamp: conv['created_at'] != null
                ? DateTime.parse(conv['created_at'] as String)
                : DateTime.now(),
            imageUrl: conv['image_url'] as String?,
            conversationHistory: null, // Will be loaded on demand
          );
        }).whereType<ChatHistoryItem>().toList(); 
        
       
        await _saveToLocalCache(chats);
        
       
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
      
    }
  }
  
  
  static Future<void> saveChat(ChatHistoryItem chat) async {
    try {
      
      await _saveToLocalCache([chat]);
      
      
      final chatId = chat.id;
      _pendingChats[chatId] = chat; 
      
      
      _pendingSaves[chatId]?.cancel();
      
      
      _pendingSaves[chatId] = Timer(_saveDebounceDelay, () {
        final chatToSave = _pendingChats[chatId];
        if (chatToSave != null) {
         
          _pendingSaves.remove(chatId);
          _pendingChats.remove(chatId);
          
          
          _saveToCloud(chatToSave).catchError((e) {
            if (kDebugMode) {
              debugPrint('⚠️ Cloud save failed (using local cache): $e');
            }
          });
          
          if (kDebugMode) {
            debugPrint('💾 Executing debounced save for chat: $chatId');
          }
        }
      });
      
      if (kDebugMode) {
        debugPrint('⏳ Scheduled debounced save for chat: $chatId (delay: ${_saveDebounceDelay.inSeconds}s)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving chat: $e');
      }
    }
  }
  
  
  static Future<void> _saveToLocalCache(List<ChatHistoryItem> newChats) async {
    try {
      final existingChats = await _loadFromLocalCache();
      
      
      for (final newChat in newChats) {
        existingChats.removeWhere((item) => item.id == newChat.id);
        existingChats.insert(0, newChat);
      }
      
      
      final chatsToSave = existingChats.take(_maxChats).toList();
      
      
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
  

  static Future<void> _saveToCloud(ChatHistoryItem chat) async {
    try {
      
      final existingResponse = await ApiClient.get('/chats/${chat.id}')
          .timeout(const Duration(seconds: 5));
      
      if (existingResponse.statusCode == 200) {
        
        try {
          await ApiClient.put('/chats/${chat.id}', {
            'title': chat.title,
          }).timeout(const Duration(seconds: 5));
        } catch (e) {
          
          if (kDebugMode) {
            debugPrint('⚠️ Failed to update conversation title: $e');
          }
        }
      } else {
        
        try {
          final createResponse = await ApiClient.post('/chats', {
            'title': chat.title,
          }).timeout(const Duration(seconds: 5));
          
          if (createResponse.statusCode == 201 || createResponse.statusCode == 200) {
            final responseBody = jsonDecode(createResponse.body) as Map<String, dynamic>;
            final conversation = responseBody['conversation'] as Map<String, dynamic>?;
            final backendId = conversation?['id'] as String?;
            
            if (backendId != null && backendId.isNotEmpty && chat.id != backendId) {
              if (kDebugMode) {
                debugPrint('🔄 Updated conversation ID: ${chat.id} → $backendId');
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to create conversation: ${createResponse.statusCode}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to create conversation: $e');
          }
        }
      }
      
      
      String actualConversationId = chat.id;
      
      if (chat.conversationHistory != null && chat.conversationHistory!.isNotEmpty) {
        
        Set<String> existingQueries = {};
        
        
        final cached = _messagesCache[actualConversationId];
        if (cached != null && !cached.isExpired) {
          existingQueries = cached.queries;
          if (kDebugMode) {
            debugPrint('📋 Using cached messages (${existingQueries.length} queries) for conversation: $actualConversationId');
          }
        } else {
          
          try {
            final existingMessagesResponse = await ApiClient.get('/chats/$actualConversationId')
                .timeout(const Duration(seconds: 5));
            if (existingMessagesResponse.statusCode == 200) {
              final existingData = jsonDecode(existingMessagesResponse.body) as Map<String, dynamic>;
              final existingMessages = existingData['messages'] as List? ?? [];
              // Extract query texts from existing messages to identify duplicates
              existingQueries = existingMessages
                  .map((msg) => (msg['query'] as String? ?? '').trim().toLowerCase())
                  .where((q) => q.isNotEmpty)
                  .toSet();
              
              // ✅ FIX #3: Cache the result
              _messagesCache[actualConversationId] = _CachedMessages(existingQueries, DateTime.now());
              
              if (kDebugMode) {
                debugPrint('📋 Fetched and cached ${existingQueries.length} existing messages for conversation: $actualConversationId');
              }
            }
          } catch (e) {
           
            if (kDebugMode) {
              debugPrint('⚠️ Could not fetch existing messages, will save all: $e');
            }
          }
        }
        
        int successCount = 0;
        int failCount = 0;
        int skippedCount = 0;
        
        for (final session in chat.conversationHistory!) {
          try {
            final sessionQuery = (session['query'] as String? ?? '').trim();
            final sessionQueryLower = sessionQuery.toLowerCase();
            
            
            if (sessionQuery.isNotEmpty && existingQueries.contains(sessionQueryLower)) {
              skippedCount++;
              if (kDebugMode) {
                debugPrint('⏭️ Skipping duplicate message: "${sessionQuery.substring(0, 50)}..."');
              }
              continue; 
            }
            
            
            final messageResponse = await ApiClient.post('/chats/$actualConversationId/messages', {
              'query': session['query'] as String? ?? '',
              'summary': session['summary'] as String?,
              'intent': session['intent'] as String?,
              'cardType': session['cardType'] as String?,
              'cards': session['cards'],
              'results': session['results'],
              'sections': session['sections'],
              'answer': session['answer'],
              'sources': session['sources'], 
              'followUpSuggestions': session['followUpSuggestions'], // ✅ CRITICAL: Save follow-ups for old chats
              'imageUrl': session['imageUrl'] as String?,
              'destinationImages': session['destinationImages'], // ✅ NEW: Save images array for media tab
            }).timeout(const Duration(seconds: 5));
            
            if (messageResponse.statusCode == 201 || messageResponse.statusCode == 200) {
              successCount++;
              
              
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
            
          }
        }
        
        if (kDebugMode) {
          debugPrint('💾 Saved ${successCount}/${chat.conversationHistory!.length} messages to cloud');
          if (skippedCount > 0) {
            debugPrint('⏭️ Skipped $skippedCount duplicate messages');
          }
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


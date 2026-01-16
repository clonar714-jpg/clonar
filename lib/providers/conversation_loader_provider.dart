import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/query_session_model.dart';
import '../services/conversation_hydration.dart';

/// Provider to load conversation messages from backend
/// ✅ CHATGPT/PERPLEXITY-STYLE: Fetches messages and hydrates into QuerySession list
final conversationLoaderProvider = FutureProvider.family<List<QuerySession>, String>(
  (ref, conversationId) async {
    if (kDebugMode) {
      debugPrint('📥 ConversationLoader: Loading conversation $conversationId');
    }
    
    try {
      // ✅ Fetch messages from backend
      final response = await ApiClient.get('/chats/$conversationId')
          .timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('❌ ConversationLoader: Failed to load conversation ${response.statusCode}');
        }
        return [];
      }
      
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final messagesJson = data['messages'] as List? ?? [];
      
      if (kDebugMode) {
        debugPrint('✅ ConversationLoader: Loaded ${messagesJson.length} messages from backend');
      }
      
      // ✅ Convert JSON messages to Message objects
      final messages = messagesJson
          .map((msg) => Message.fromJson(msg as Map<String, dynamic>))
          .toList();
      
      // ✅ CHATGPT/PERPLEXITY-STYLE: Hydrate messages into QuerySession list
      // Each message = one complete turn (user query + assistant response)
      final sessions = hydrateSessionsFromMessages(messages);
      
      if (kDebugMode) {
        debugPrint('✅ ConversationLoader: Hydrated ${sessions.length} sessions from ${messages.length} messages');
        for (int i = 0; i < sessions.length; i++) {
          final s = sessions[i];
          debugPrint('   Session $i: "${s.query.substring(0, s.query.length > 40 ? 40 : s.query.length)}..."');
          debugPrint('     - Summary: ${s.summary?.length ?? 0} chars');
          debugPrint('     - Sections: ${s.sections?.length ?? 0}');
          debugPrint('     - Sources: ${s.sources.length}');
          debugPrint('     - Follow-ups: ${s.followUpSuggestions.length}');
          debugPrint('     - isFinalized: ${s.isFinalized}');
          if (s.summary == null || s.summary!.isEmpty) {
            debugPrint('     ⚠️ WARNING: Session has no summary - may not render');
          }
          if (s.sections == null || s.sections!.isEmpty) {
            debugPrint('     ⚠️ WARNING: Session has no sections');
          }
        }
      }
      
      return sessions;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ConversationLoader: Error loading conversation: $e');
        debugPrint('   Stack: $stackTrace');
      }
      return [];
    }
  },
);


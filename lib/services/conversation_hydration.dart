import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/query_session_model.dart';

/// Message model from backend
class Message {
  final String id;
  final String conversationId;
  final String query;
  final String? summary;
  final String? intent;
  final String? cardType;
  final String? cards;
  final String? results;
  final String? sections;
  final String? answer;
  final String? imageUrl;
  final String? sources;
  final String? followUpSuggestions;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.query,
    this.summary,
    this.intent,
    this.cardType,
    this.cards,
    this.results,
    this.sections,
    this.answer,
    this.imageUrl,
    this.sources,
    this.followUpSuggestions,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      query: json['query'] as String? ?? '',
      summary: json['summary'] as String?,
      intent: json['intent'] as String?,
      cardType: json['card_type'] as String?,
      cards: json['cards'] as String?,
      results: json['results'] as String?,
      sections: json['sections'] as String?,
      answer: json['answer'] as String?,
      imageUrl: json['image_url'] as String?,
      sources: json['sources'] as String?,
      followUpSuggestions: json['follow_up_suggestions'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}


List<QuerySession> hydrateSessionsFromMessages(List<Message> messages) {
  if (kDebugMode) {
    debugPrint('🔄 Hydrating ${messages.length} messages into QuerySession list');
  }

  final sessions = <QuerySession>[];

  for (final message in messages) {
    try {
      // Parse JSON fields
      List<Map<String, dynamic>>? sections;
      if (message.sections != null) {
        try {
          final sectionsData = message.sections is String
              ? jsonDecode(message.sections!)
              : message.sections;
          if (sectionsData is List) {
            sections = sectionsData.map((e) => Map<String, dynamic>.from(e)).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to parse sections: $e');
          }
        }
      }

      List<Map<String, dynamic>> sources = [];
      if (message.sources != null) {
        try {
          final sourcesData = message.sources is String
              ? jsonDecode(message.sources!)
              : message.sources;
          if (sourcesData is List) {
            sources = sourcesData.map((e) => Map<String, dynamic>.from(e)).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to parse sources: $e');
          }
        }
      }

      List<String> followUpSuggestions = [];
      if (message.followUpSuggestions != null) {
        try {
          final followUpsData = message.followUpSuggestions is String
              ? jsonDecode(message.followUpSuggestions!)
              : message.followUpSuggestions;
          if (followUpsData is List) {
            followUpSuggestions = followUpsData.map((e) => e.toString()).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to parse follow-ups: $e');
          }
        }
      }

      Map<String, dynamic>? cardsByDomain;
      if (message.cards != null) {
        try {
          final cardsData = message.cards is String
              ? jsonDecode(message.cards!)
              : message.cards;
          if (cardsData is Map) {
            cardsByDomain = Map<String, dynamic>.from(cardsData);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to parse cards: $e');
          }
        }
      }

      List<dynamic> results = [];
      List<String> destinationImages = [];
      if (message.results != null) {
        try {
          final resultsData = message.results is String
              ? jsonDecode(message.results!)
              : message.results;
          
          // ✅ FIX: results can be either a List or an Object (Map)
          if (resultsData is List) {
            results = resultsData;
          } else if (resultsData is Map) {
            // ✅ Extract destination_images from results object
            if (resultsData['destination_images'] != null) {
              final destImages = resultsData['destination_images'];
              if (destImages is List) {
                destinationImages = destImages.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
              }
            }
            // ✅ Keep results as the original object (or convert to list if needed)
            results = [resultsData];
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to parse results: $e');
          }
        }
      }

      
      final session = QuerySession(
        sessionId: null, // ✅ Auto-generate sessionId for rehydrated sessions
        query: message.query,
        summary: message.summary,
        answer: message.answer, // ✅ CRITICAL: Include full answer text from database
        intent: message.intent,
        cardType: message.cardType,
        sections: sections, // ✅ May be null - DB doesn't always store this
        sources: sources, // ✅ May be empty - DB doesn't always store this
        followUpSuggestions: followUpSuggestions,
        cardsByDomain: cardsByDomain, // ✅ May be null - DB doesn't always store this
        results: results,
        destinationImages: destinationImages, // ✅ FIX: Extract destination_images from results
        phase: QueryPhase.done, // ✅ HISTORY MODE: Set to done - these are completed sessions, never searching
        isStreaming: false, // ✅ Always false for rehydrated chats
        isParsing: false,
        isFinalized: true, // ✅ CRITICAL FIX: Mark DB-hydrated sessions as finalized so they render
        imageUrl: message.imageUrl,
        timestamp: message.createdAt,
      );

      sessions.add(session);

      if (kDebugMode) {
        debugPrint('  ✅ Hydrated session: "${message.query.substring(0, message.query.length > 50 ? 50 : message.query.length)}..."');
        debugPrint('     - Summary: ${message.summary?.length ?? 0} chars');
        debugPrint('     - Sections: ${sections?.length ?? 0}');
        debugPrint('     - Sources: ${sources.length}');
        debugPrint('     - Follow-ups: ${followUpSuggestions.length}');
        debugPrint('     - Destination Images: ${destinationImages.length}');
        debugPrint('     - isFinalized: ${session.isFinalized}');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Error hydrating message ${message.id}: $e');
        debugPrint('   Stack: $stackTrace');
      }
    }
  }

  if (kDebugMode) {
    debugPrint('✅ Hydrated ${sessions.length} sessions from ${messages.length} messages');
  }

  return sessions;
}


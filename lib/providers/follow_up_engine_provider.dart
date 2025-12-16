import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/query_session_model.dart';
import 'follow_up_dedupe_provider.dart';

/// ✅ PHASE 5 + PHASE 10: Follow-up engine provider - generates contextual follow-up suggestions
final followUpEngineProvider = FutureProvider.family<List<String>, QuerySession>((ref, session) async {
  ref.keepAlive(); // ✅ PHASE 10: Keep alive for better performance
  try {
    final suggestions = <String>[];
    final intent = session.intent?.toLowerCase() ?? session.cardType?.toLowerCase() ?? '';
    final summary = session.summary ?? '';
    final query = session.query.toLowerCase();
    
    // ✅ Heuristic 1: Intent-based suggestions
    if (intent.contains('shopping') || intent.contains('shop')) {
      // Shopping-specific follow-ups
      if (query.contains('under') || query.contains('\$') || query.contains('price')) {
        suggestions.add('Show me cheaper alternatives?');
        suggestions.add('What about higher quality options?');
        suggestions.add('Filter by size?');
      } else {
        suggestions.add('Show me options under \$100?');
        suggestions.add('Compare with similar products?');
        suggestions.add('What are the reviews saying?');
      }
    } else if (intent.contains('hotel') || intent.contains('hotels')) {
      // Hotel-specific follow-ups
      suggestions.add('Show me hotels near downtown?');
      suggestions.add('What\'s the best time to visit?');
      suggestions.add('Show me on a map?');
      suggestions.add('Similar places nearby?');
    } else if (intent.contains('movie') || intent.contains('movies') || intent.contains('film')) {
      // Movie-specific follow-ups
      suggestions.add('Who\'s in the cast?');
      suggestions.add('Show me similar movies?');
      suggestions.add('What are the ratings?');
    } else if (intent.contains('restaurant') || intent.contains('food') || intent.contains('dining')) {
      // Restaurant-specific follow-ups
      suggestions.add('Show me the menu?');
      suggestions.add('What\'s the price range?');
      suggestions.add('Make a reservation?');
    } else if (intent.contains('place') || intent.contains('location') || intent.contains('attraction')) {
      // Location/place-specific follow-ups
      suggestions.add('Best time to visit?');
      suggestions.add('How to get there?');
      suggestions.add('What else is nearby?');
    }
    
    // ✅ Heuristic 2: Long answer - extract key questions
    if (summary.length > 500 && suggestions.length < 3) {
      // Extract potential questions from long answers
      if (summary.contains('?')) {
        final questionMatches = RegExp(r'[^.!?]*\?').allMatches(summary);
        for (final match in questionMatches.take(2)) {
          final question = match.group(0)?.trim();
          if (question != null && question.length > 10 && question.length < 100) {
            suggestions.add(question);
          }
        }
      }
      
      // Generic follow-ups for long answers
      if (suggestions.isEmpty) {
        suggestions.add('Tell me more about this');
        suggestions.add('What are the key points?');
        suggestions.add('Can you summarize?');
      }
    }
    
    // ✅ Heuristic 3: Location-based follow-ups
    if (session.locationCards.isNotEmpty && suggestions.length < 3) {
      suggestions.add('Show me more places like this?');
      suggestions.add('What\'s nearby?');
      suggestions.add('Show on map?');
    }
    
    // ✅ Heuristic 4: Product-based follow-ups (if products exist)
    if (session.products.isNotEmpty && suggestions.length < 3) {
      suggestions.add('Show me more options?');
      suggestions.add('Filter by price?');
      suggestions.add('Compare products?');
    }
    
    // ✅ Heuristic 5: Generic fallback if no specific suggestions
    if (suggestions.isEmpty) {
      if (query.contains('what') || query.contains('how') || query.contains('why')) {
        suggestions.add('Tell me more');
        suggestions.add('What else should I know?');
        suggestions.add('Any related information?');
      } else {
        suggestions.add('Show me more details?');
        suggestions.add('What are the options?');
        suggestions.add('Any alternatives?');
      }
    }
    
    // ✅ Apply deduplication
    final deduplicated = ref.read(followUpDedupeProvider(suggestions));
    
    if (kDebugMode) {
      debugPrint('🎯 Generated ${deduplicated.length} follow-up suggestions for intent: $intent');
    }
    
    return deduplicated;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('❌ Error generating follow-ups: $e\n$st');
    }
    // Return generic fallback suggestions
    return [
      'Tell me more',
      'Show me alternatives',
      'What else?',
    ];
  }
});


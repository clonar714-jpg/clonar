import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// ✅ PHASE 5 + PHASE 10: Follow-up deduplication provider - removes duplicate and similar suggestions
final followUpDedupeProvider = Provider.family<List<String>, List<String>>((ref, suggestions) {
  ref.keepAlive(); // ✅ PHASE 10: Keep alive for better performance
  if (suggestions.isEmpty) return [];
  
  final deduplicated = <String>[];
  final seen = <String>{};
  
  for (final suggestion in suggestions) {
    final normalized = suggestion.toLowerCase().trim();
    
    // Skip if exact duplicate
    if (seen.contains(normalized)) {
      continue;
    }
    
    // Check for similar meaning (simple similarity check)
    bool isSimilar = false;
    for (final existing in seen) {
      if (_areSimilar(normalized, existing)) {
        isSimilar = true;
        break;
      }
    }
    
    if (!isSimilar) {
      deduplicated.add(suggestion);
      seen.add(normalized);
      
      // ✅ FIX: Keep maximum 3 unique follow-ups (reduced from 5)
      if (deduplicated.length >= 3) {
        break;
      }
    }
  }
  
  if (kDebugMode) {
    debugPrint('🔍 Deduplicated ${suggestions.length} suggestions to ${deduplicated.length} unique');
  }
  
  return deduplicated;
});

/// Simple similarity check - returns true if two strings have similar meaning
bool _areSimilar(String a, String b) {
  // Remove common question words and punctuation
  final cleanA = a.replaceAll(RegExp(r'[^\w\s]'), '').split(' ').where((w) => 
    !['what', 'how', 'when', 'where', 'why', 'show', 'me', 'tell', 'the', 'a', 'an', 'is', 'are', 'can', 'you'].contains(w.toLowerCase())
  ).join(' ').toLowerCase();
  
  final cleanB = b.replaceAll(RegExp(r'[^\w\s]'), '').split(' ').where((w) => 
    !['what', 'how', 'when', 'where', 'why', 'show', 'me', 'tell', 'the', 'a', 'an', 'is', 'are', 'can', 'you'].contains(w.toLowerCase())
  ).join(' ').toLowerCase();
  
  // Check if they share significant words
  final wordsA = cleanA.split(' ').where((w) => w.length > 3).toSet();
  final wordsB = cleanB.split(' ').where((w) => w.length > 3).toSet();
  
  if (wordsA.isEmpty || wordsB.isEmpty) return false;
  
  final intersection = wordsA.intersection(wordsB);
  final union = wordsA.union(wordsB);
  
  // If more than 50% of words overlap, consider them similar
  if (union.isEmpty) return false;
  final similarity = intersection.length / union.length;
  
  return similarity > 0.5;
}


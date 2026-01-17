import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show compute, kDebugMode, debugPrint;
import '../isolates/text_parsing_isolate.dart';


final parsedAgentOutputProvider = FutureProvider.family<Map<String, dynamic>?, Map<String, dynamic>?>((ref, agentResponse) async {
  
  ref.keepAlive();
  if (agentResponse == null) return null;
  
  try {
    
    final answerText = agentResponse['answer']?.toString() ?? 
                       agentResponse['summary']?.toString() ?? '';
    final locationCards = (agentResponse['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final destinationImages = (agentResponse['destination_images'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
    final intent = agentResponse['intent']?.toString();
    final cardType = agentResponse['cardType']?.toString();
    final cards = (agentResponse['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final results = agentResponse['results'] ?? [];
    final summary = agentResponse['summary']?.toString();
    
   
    ParsedContent? parsedContent;
    if (answerText.isNotEmpty && locationCards.isNotEmpty) {
      try {
        final input = ParsingInput(
          answerText: answerText,
          locationCards: locationCards,
          destinationImages: destinationImages,
        );
        
        parsedContent = await compute(parseAnswerIsolate, input.toMap());
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Parsing error: $e');
        }
      }
    }
    
    
    Map<String, dynamic>? preprocessedResponse;
    try {
      preprocessedResponse = await compute(parseAgentResponseIsolate, {
        'rawAnswer': agentResponse['answer'] ?? {},
        'rawResults': agentResponse['results'] ?? {},
        'rawSections': agentResponse['sections'] ?? [],
        'intent': intent ?? 'unknown',
        'cardType': cardType ?? 'unknown',
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Preprocessing error: $e');
      }
    }
    
    return {
      'summary': summary ?? preprocessedResponse?['summary'] ?? '',
      'intent': intent,
      'cardType': cardType,
      'cards': cards,
      'results': results,
      'destinationImages': destinationImages,
      'locationCards': locationCards,
      'parsedContent': parsedContent?.toMap(),
      'preprocessedResponse': preprocessedResponse,
    };
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Error parsing agent output: $e');
    }
    return null;
  }
});

// No imports needed - this is a pure Dart isolate function

// Helper class used for fast matching
class _Hit {
  final int start;
  final int end;
  final Map<String, dynamic> card;
  final int length;

  _Hit(this.start, this.end, this.card, this.length);
}

// FAST, NON-BLOCKING version (runs fully in isolate)
List<Map<String, dynamic>> fastParseTextWithLocations(
    String text,
    List<Map<String, dynamic>> locationCards,
) {
  // If nothing to parse, return plain text
  if (locationCards.isEmpty) {
    return [{'text': text, 'location': null}];
  }

  final lowerText = text.toLowerCase();

  // Prepare lookup table: key → card
  final Map<String, Map<String, dynamic>> lookup = <String, Map<String, dynamic>>{};

  for (final card in locationCards) {
    final title = (card['title']?.toString() ?? '').toLowerCase().trim();
    if (title.isEmpty) continue;

    lookup[title] = card;

    // Each significant word
    for (final word in title.split(' ')) {
      if (word.length >= 4) {
        if (!lookup.containsKey(word)) {
          lookup[word] = card;
        }
      }
    }
  }

  // Now detect mentions (very fast: single scan)
  final List<_Hit> hits = [];
  lookup.forEach((keyword, card) {
    int index = 0;
    while (true) {
      index = lowerText.indexOf(keyword, index);
      if (index == -1) break;
      hits.add(_Hit(index, index + keyword.length, card, keyword.length));
      index += keyword.length;
    }
  });

  if (hits.isEmpty) {
    // Show plain text + all cards (Perplexity behavior)
    final List<Map<String, dynamic>> segments = <Map<String, dynamic>>[
      {'text': text, 'location': null}
    ];

    for (final c in locationCards) {
      segments.add({'text': '', 'location': c});
    }

    return segments;
  }

  // Sort by starting position / longest keyword wins
  hits.sort((a, b) {
    final cmp = a.start.compareTo(b.start);
    if (cmp != 0) return cmp;
    return b.length.compareTo(a.length);
  });

  // Deduplicate overlaps
  final List<_Hit> cleaned = [];
  for (final h in hits) {
    bool overlaps = false;
    for (final exist in cleaned) {
      if (!(h.end <= exist.start || h.start >= exist.end)) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) cleaned.add(h);
  }

  // Build final segments
  final List<Map<String, dynamic>> segments = <Map<String, dynamic>>[];
  final Set<String> shown = <String>{};

  int last = 0;
  for (final h in cleaned) {
    if (h.start > last) {
      segments.add({
        'text': text.substring(last, h.start),
        'location': null,
      });
    }

    // Add card only once
    final id = (h.card['title'] ?? '').toString();
    if (!shown.contains(id)) {
      shown.add(id);
      segments.add({'text': '', 'location': h.card});
    }

    last = h.end;
  }

  // Remaining text
  if (last < text.length) {
    segments.add({'text': text.substring(last), 'location': null});
  }

  // Add all remaining cards
  for (final c in locationCards) {
    final id = (c['title'] ?? '').toString();
    if (!shown.contains(id)) {
      segments.add({'text': '', 'location': c});
      shown.add(id);
    }
  }

  return segments;
}

/// Data sent into the isolate
class ParsingInput {
  final String answerText;
  final List<Map<String, dynamic>> locationCards;
  final List<String> destinationImages;

  ParsingInput({
    required this.answerText,
    required this.locationCards,
    required this.destinationImages,
  });

  Map<String, dynamic> toMap() => {
      'answerText': answerText,
      'locationCards': locationCards,
      'destinationImages': destinationImages,
    };

  static ParsingInput fromMap(Map<String, dynamic> map) => ParsingInput(
        answerText: map['answerText'] as String,
        locationCards: List<Map<String, dynamic>>.from(map['locationCards'] as List),
        destinationImages: List<String>.from(map['destinationImages'] as List),
    );
  }

/// Output (parsed text + segment cards)
class ParsedContent {
  final String briefingText;
  final String placeNamesText;
  final List<Map<String, dynamic>> segments;

  ParsedContent({
    required this.briefingText,
    required this.placeNamesText,
    required this.segments,
  });

  Map<String, dynamic> toMap() => {
      'briefingText': briefingText,
      'placeNamesText': placeNamesText,
      'segments': segments,
    };

  static ParsedContent fromMap(Map<String, dynamic> map) => ParsedContent(
        briefingText: map['briefingText'] as String,
        placeNamesText: map['placeNamesText'] as String,
        segments: List<Map<String, dynamic>>.from(map['segments'] as List),
      );
}

// ✅ PATCH SET A: Helper functions for preprocessing (isolate-safe)
String cleanDescription(String? desc) {
  if (desc == null || desc.isEmpty) return '';
  return desc
      .replaceAll(RegExp(r'\*\*'), '')
      .replaceAll(RegExp(r'[_~>`#-]'), '')
      .replaceAll(RegExp(r'[0-9]+\.\s*'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

String generateSummary(Map<String, dynamic> rawAnswer) {
  final summary = rawAnswer['summary']?.toString() ?? 
                  rawAnswer['answer']?.toString() ?? 
                  '';
  return cleanDescription(summary);
}

String summarizeHotel(Map<String, dynamic> hotel) {
  final name = hotel['name']?.toString() ?? '';
  final location = hotel['location']?.toString() ?? '';
  final rating = hotel['rating'];
  final desc = hotel['description']?.toString() ?? '';
  
  if (desc.isNotEmpty && desc.length > 20) {
    return desc;
  }
  
  if (rating is num && rating >= 4.5) {
    return 'A ${rating >= 4.5 ? 4 : 3}-star luxury hotel${location.isNotEmpty ? ' in $location' : ''}';
  } else if (rating is num && rating >= 4.0) {
    return 'A ${rating >= 4.0 ? 3 : 2}-star hotel${location.isNotEmpty ? ' in $location' : ''}';
  } else {
    return 'A modern property${location.isNotEmpty ? ' in $location' : ''}';
  }
}

List<Map<String, dynamic>> preprocessHotels(Map<String, dynamic> raw) {
  final list = raw['hotels'] ?? raw['hotelResults'] ?? [];
  if (list is! List) return [];
  
  return List<Map<String, dynamic>>.from(list).map((h) {
    return {
      ...h,
      'cleanDesc': cleanDescription(h['description']?.toString()),
      'shortDesc': summarizeHotel(h),
    };
  }).toList();
}

List<Map<String, dynamic>> preprocessPlaces(Map<String, dynamic> raw) {
  final list = raw['places'] ?? [];
  if (list is! List) return [];
  
  return List<Map<String, dynamic>>.from(list).map((p) {
    return {
      ...p,
      'cleanDesc': cleanDescription(p['description']?.toString()),
    };
  }).toList();
}

List<Map<String, dynamic>> preprocessProducts(Map<String, dynamic> raw) {
  final list = raw['products'] ?? [];
  if (list is! List) return [];
  
  return List<Map<String, dynamic>>.from(list).map((p) {
    return {
      ...p,
      'cleanDesc': cleanDescription(p['description']?.toString()),
    };
  }).toList();
}

List<Map<String, dynamic>> preprocessMovies(Map<String, dynamic> raw) {
  final list = raw['movies'] ?? [];
  if (list is! List) return [];
  
  return List<Map<String, dynamic>>.from(list);
}

List<Map<String, dynamic>> preprocessLocations(Map<String, dynamic> raw) {
  final list = raw['locations'] ?? [];
  if (list is! List) return [];
  
  return List<Map<String, dynamic>>.from(list);
}

List<Map<String, dynamic>> preprocessSections(List<dynamic> sections) {
  if (sections.isEmpty) return [];
  
  return sections.map((sec) {
    if (sec is! Map) return <String, dynamic>{};
    return {
      'title': sec['title']?.toString() ?? '',
      'body': cleanDescription(sec['body']?.toString() ?? sec['description']?.toString()),
    };
  }).toList();
}

/// ✅ PATCH 2: Comprehensive parse function for entire agent response
Map<String, dynamic> parseAgentResponseIsolate(Map<String, dynamic> input) {
  final rawAnswer = input['rawAnswer'] ?? <String, dynamic>{};
  final rawResults = input['rawResults'] ?? <String, dynamic>{};
  final rawSections = input['rawSections'] ?? [];
  final intent = input['intent']?.toString() ?? 'unknown';
  final cardType = input['cardType']?.toString() ?? 'unknown';

  // Heavy summary generation moved here
  final summary = generateSummary(rawAnswer);

  // Heavy hotel/place preprocessing moved here
  final hotels = preprocessHotels(rawResults);
  final places = preprocessPlaces(rawResults);
  final products = preprocessProducts(rawResults);
  final movies = preprocessMovies(rawResults);
  final locations = preprocessLocations(rawResults);

  // Process Perplexity-style sections
  final parsedSections = preprocessSections(rawSections is List ? rawSections : []);

  return {
    'summary': summary,
    'sections': parsedSections,
    'answer': rawAnswer,
    'hotels': hotels,
    'places': places,
    'products': products,
    'movies': movies,
    'locations': locations,
  };
}

/// ENTRY POINT — isolate function
/// This runs in a separate isolate, off the UI thread
ParsedContent parseAnswerIsolate(Map<String, dynamic> map) {
  final input = ParsingInput.fromMap(map);

  final answerText = input.answerText;
  final cards = input.locationCards;

  // -----------------------------
  // 1. Extract briefing
  // -----------------------------
  String briefing = "";
  String placeNames = "";

  if (answerText.isEmpty) {
    return ParsedContent(
      briefingText: "",
      placeNamesText: "",
      segments: [{'text': '', 'location': null}],
    );
  }

  final colon = RegExp(r':\s*(.*)').firstMatch(answerText);
  if (colon != null) {
    briefing = answerText.substring(0, colon.start).trim();
    placeNames = colon.group(1)?.trim() ?? "";
  } else {
    final words = answerText.split(' ');
    if (words.length > 50) {
      briefing = words.take(50).join(' ');
      placeNames = words.skip(50).join(' ');
    } else {
      briefing = answerText;
      placeNames = "";
    }
  }

  // Clean briefing - remove duplicates
  final lines = briefing.split(RegExp(r'[.!?]\s+'));
  final seenLines = <String>{};
  final uniqueLines = <String>[];

  for (final line in lines) {
    final trimmed = line.trim().toLowerCase();
    if (trimmed.isNotEmpty && !seenLines.contains(trimmed)) {
      seenLines.add(trimmed);
      uniqueLines.add(line.trim());
  }
}

  briefing = uniqueLines.join('. ').trim();

  // -----------------------------
  // 2. Match cards with text
  // -----------------------------
  final cardTitles = cards
      .map((e) => (e['title'] ?? '').toString().toLowerCase().trim())
      .where((t) => t.isNotEmpty)
      .toList();

  final validNames = <String>[];
  if (placeNames.isNotEmpty) {
    for (final p in placeNames.split(',')) {
      final cleaned = p.trim().toLowerCase();
      if (cleaned.isEmpty) continue;
  
      // Check if this place name matches any card title
      final hasMatch = cardTitles.any((t) => 
        t == cleaned || 
        t.contains(cleaned) || 
        cleaned.contains(t) ||
        cleaned.split(' ').every((word) => word.length > 2 && t.contains(word))
      );
      
      if (hasMatch) {
        validNames.add(p.trim());
      }
    }
  }

  placeNames = validNames.join(', ');

  // -----------------------------
  // 3. Segment builder using fast parsing
  // -----------------------------
  // Use fastParseTextWithLocations for efficient text parsing in isolate
  final segments = fastParseTextWithLocations(answerText, cards);
  
  return ParsedContent(
    briefingText: briefing,
    placeNamesText: placeNames,
    segments: segments,
  );
}


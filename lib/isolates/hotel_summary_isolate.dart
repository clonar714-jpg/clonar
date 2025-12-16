// ✅ FIX 1: Hotel summary generation in isolate (prevents UI blocking)
// This function runs in a background isolate to avoid blocking the UI thread

String buildHotelSummary(Map<String, dynamic> hotel) {
  final name = _safeString(hotel['name'], '');
  final address = _safeString(hotel['address'], '');
  final location = _safeString(hotel['location'], '');
  final rating = _safeNumber(hotel['rating'], 0.0);
  final reviewCount = _safeInt(hotel['reviewCount'], 0);
  final amenities = hotel['amenities'] as List<dynamic>? ?? [];
  final description = _safeString(hotel['description'], '');
  final nearby = _safeString(hotel['nearby'], '');
  
  // 1. DATA EXTRACTION & ANALYSIS
  final nameLower = name.toLowerCase();
  final isStudio = nameLower.contains('studio');
  final isLuxury = nameLower.contains('luxury') || nameLower.contains('premium') || nameLower.contains('boutique');
  final isBoutique = nameLower.contains('boutique') || nameLower.contains('monaco') || nameLower.contains('kimpton');
  final isAirport = nameLower.contains('airport');
  final isDowntown = nameLower.contains('downtown');
  final isExtendedStay = nameLower.contains('extended') || nameLower.contains('long term');
  final isResort = nameLower.contains('resort');
  final isSuites = nameLower.contains('suites') || nameLower.contains('suite');
  final isInn = nameLower.contains('inn');
  
  // Determine hotel class from rating (if not explicitly provided)
  final hotelClass = rating >= 4.5 ? 4 : (rating >= 4.0 ? 3 : (rating >= 3.5 ? 2 : 1));
  final isHighEnd = rating >= 4.5 || isLuxury || isBoutique;
  
  // Extract amenities
  final amenityList = amenities.map((a) => a.toString().toLowerCase()).toList();
  final hasPool = amenityList.any((a) => a.contains('pool') || a.contains('swimming'));
  final hasParking = amenityList.any((a) => a.contains('parking') || a.contains('free parking'));
  final hasBreakfast = amenityList.any((a) => a.contains('breakfast') || a.contains('continental'));
  final hasShuttle = amenityList.any((a) => a.contains('shuttle') || a.contains('airport'));
  final hasFitness = amenityList.any((a) => a.contains('fitness') || a.contains('gym') || a.contains('workout'));
  final hasWifi = amenityList.any((a) => a.contains('wifi') || a.contains('internet') || a.contains('wireless'));
  final hasPets = amenityList.any((a) => a.contains('pet') || a.contains('dog') || a.contains('animal'));
  final hasKitchen = amenityList.any((a) => a.contains('kitchen') || a.contains('cooking') || a.contains('microwave') || a.contains('refrigerator'));
  final hasSpa = amenityList.any((a) => a.contains('spa') || a.contains('massage'));
  final hasRestaurant = amenityList.any((a) => a.contains('restaurant') || a.contains('dining') || a.contains('bar'));
  final hasBusiness = amenityList.any((a) => a.contains('business') || a.contains('meeting') || a.contains('conference'));
  final hasRooftop = amenityList.any((a) => a.contains('rooftop') || a.contains('roof'));
  final isIndoorPool = amenityList.any((a) => a.contains('indoor pool') || a.contains('indoor swimming'));
  
  // Check for unique connections/features in description
  final descLower = description.toLowerCase();
  final hasConventionCenter = descLower.contains('convention') || descLower.contains('conference center');
  final hasConnection = descLower.contains('connected to') || descLower.contains('adjacent to');
  
  // 2. VARIED OPENING PATTERNS (Perplexity style)
  List<String> sentences = [];
  String firstSentence = '';
  
  // Pattern 1: Type-based with star rating (if high-end)
  if (isHighEnd && rating >= 4.0) {
    String typeDesc = '';
    if (isBoutique) {
      typeDesc = 'A $hotelClass-star luxury boutique hotel';
    } else if (isLuxury) {
      typeDesc = 'A $hotelClass-star luxury hotel';
    } else if (rating >= 4.5) {
      typeDesc = 'A $hotelClass-star hotel';
    } else {
      typeDesc = 'A $hotelClass-star property';
    }
    
    // Add location context
    if (isDowntown || address.toLowerCase().contains('downtown')) {
      typeDesc += ' in downtown ${location.isNotEmpty && location != 'Location not specified' ? location.split(',')[0] : 'SLC'}';
    } else if (isAirport) {
      typeDesc += ' near the airport';
    }
    
    firstSentence = typeDesc;
  }
  // Pattern 2: Feature-based (unique connections)
  else if (hasConventionCenter || hasConnection) {
    String connection = '';
    if (descLower.contains('convention center')) {
      final match = RegExp(r'connected to (?:the )?([^,\.]+)').firstMatch(descLower);
      if (match != null) {
        connection = match.group(1)?.trim() ?? 'the convention center';
      } else {
        connection = 'the convention center';
      }
      firstSentence = 'A modern hotel connected to $connection';
    } else if (descLower.contains('connected to')) {
      final match = RegExp(r'connected to ([^,\.]+)').firstMatch(descLower);
      if (match != null) {
        connection = match.group(1)?.trim() ?? '';
        firstSentence = 'A hotel connected to $connection';
      } else {
        firstSentence = 'A modern hotel';
      }
    } else {
      firstSentence = 'A modern hotel';
    }
  }
  // Pattern 3: Amenity-led (for budget/mid-range)
  else if (hasPool && hasBreakfast && hasParking && !isHighEnd) {
    firstSentence = 'Clean rooms, free parking';
    if (isIndoorPool) {
      firstSentence += ', and an indoor pool';
    } else if (hasPool) {
      firstSentence += ', and a pool';
    }
  }
  // Pattern 4: Location-based
  else if (location.isNotEmpty && location != 'Location not specified') {
    final locationName = location.split(',')[0].trim();
    if (isAirport) {
      firstSentence = 'A hotel near the airport in $locationName';
    } else if (isDowntown) {
      firstSentence = 'A hotel in downtown $locationName';
    } else {
      firstSentence = 'A hotel in $locationName';
    }
  }
  // Pattern 5: Rating-based (fallback)
  else if (rating >= 4.0) {
    firstSentence = 'A ${hotelClass}-star hotel';
  } else {
    firstSentence = 'A modern property';
  }
  
  sentences.add(firstSentence);
  
  // 3. ADD KEY FEATURES (2-3 sentences)
  List<String> featureSentences = [];
  
  // Priority 1: Unique amenities
  if (hasRooftop) {
    featureSentences.add('Features a rooftop area with city views.');
  } else if (hasSpa) {
    featureSentences.add('Includes a spa for relaxation.');
  } else if (hasBusiness) {
    featureSentences.add('Offers business and meeting facilities.');
  }
  
  // Priority 2: Common amenities
  if (hasPool && !featureSentences.any((s) => s.contains('pool'))) {
    if (isIndoorPool) {
      featureSentences.add('Has an indoor pool.');
    } else {
      featureSentences.add('Features a pool.');
    }
  }
  
  if (hasBreakfast && featureSentences.length < 2) {
    featureSentences.add('Includes breakfast.');
  }
  
  if (hasParking && featureSentences.length < 2) {
    featureSentences.add('Offers parking.');
  }
  
  if (hasWifi && featureSentences.length < 2) {
    featureSentences.add('Provides WiFi.');
  }
  
  // Priority 3: Room features
  if (hasKitchen && featureSentences.length < 3) {
    featureSentences.add('Rooms include kitchen facilities.');
  }
  
  if (isExtendedStay && featureSentences.length < 3) {
    featureSentences.add('Designed for extended stays.');
  }
  
  // Add 2-3 feature sentences
  sentences.addAll(featureSentences.take(3));
  
  // 4. ADD LOCATION CONTEXT (if not already mentioned)
  if (!firstSentence.toLowerCase().contains(location.toLowerCase()) && 
      location.isNotEmpty && 
      location != 'Location not specified' &&
      sentences.length < 4) {
    final locationName = location.split(',')[0].trim();
    if (nearby.isNotEmpty) {
      sentences.add('Located in $locationName, near $nearby.');
    } else {
      sentences.add('Located in $locationName.');
    }
  }
  
  // 5. ADD RATING CONTEXT (if high rating and not already mentioned)
  if (rating >= 4.0 && reviewCount > 0 && sentences.length < 4) {
    if (rating >= 4.5) {
      sentences.add('Highly rated with ${reviewCount}+ reviews.');
    } else {
      sentences.add('Well-rated with ${reviewCount}+ reviews.');
    }
  }
  
  // 6. FALLBACK: Use description if we have very few sentences
  if (sentences.length < 2 && description.isNotEmpty && description.length > 20) {
    // Use first sentence of description
    final firstDescSentence = description.split('.').first.trim();
    if (firstDescSentence.isNotEmpty && firstDescSentence.length > 20) {
      sentences.add(firstDescSentence);
    }
  }
  
  // Join sentences
  String summary = sentences.join(' ');
  
  // Ensure minimum length
  if (summary.length < 50) {
    summary = 'A modern property offering comfortable accommodations.';
  }
  
  return summary;
}

// Batch process multiple hotels
List<Map<String, dynamic>> buildHotelSummaries(List<Map<String, dynamic>> hotels) {
  return hotels.map((hotel) {
    return {
      ...hotel,
      'summary': buildHotelSummary(hotel),
    };
  }).toList();
}

// Helper functions (must be in isolate file)
String _safeString(dynamic value, String fallback) {
  if (value == null) return fallback;
  return value.toString().trim();
}

double _safeNumber(dynamic value, double fallback) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value.toString());
  return parsed ?? fallback;
}

int _safeInt(dynamic value, int fallback) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString());
  return parsed ?? fallback;
}


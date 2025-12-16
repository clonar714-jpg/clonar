// ✅ PHASE 7: Isolate for content normalization and markdown cleaning

/// Clean markdown and remove HTML artifacts (isolate-safe)
String cleanMarkdownIsolate(String text) {
  if (text.isEmpty) return '';
  
  return text
      .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
      .replaceAll(RegExp(r'\*\*'), '') // Remove bold markdown
      .replaceAll(RegExp(r'[_~>`#-]'), '') // Remove markdown symbols
      .replaceAll(RegExp(r'[0-9]+\.\s*'), '') // Remove list numbers
      .replaceAll(RegExp(r'\s{2,}'), ' ') // Normalize spaces
      .trim();
}

/// Normalize location card structure (isolate-safe)
Map<String, dynamic> normalizeLocationCardIsolate(Map<String, dynamic> card) {
  return {
    'title': card['title']?.toString() ?? card['name']?.toString() ?? 'Unknown Location',
    'description': card['description']?.toString() ?? card['snippet']?.toString() ?? '',
    'rating': card['rating']?.toString() ?? '',
    'reviews': card['reviews']?.toString() ?? '',
    'address': card['address']?.toString() ?? card['location']?.toString() ?? '',
    'thumbnail': card['thumbnail']?.toString() ?? card['image']?.toString() ?? '',
    'link': card['link']?.toString() ?? card['url']?.toString() ?? '',
    'phone': card['phone']?.toString() ?? '',
    'images': (card['images'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [],
    'gps_coordinates': card['gps_coordinates'] ?? card['geo'] ?? {},
  };
}

/// Normalize hotel card structure (isolate-safe)
Map<String, dynamic> normalizeHotelCardIsolate(Map<String, dynamic> card) {
  return {
    'id': card['id']?.toString() ?? '',
    'name': card['name']?.toString() ?? card['title']?.toString() ?? 'Unknown Hotel',
    'description': card['description']?.toString() ?? card['summary']?.toString() ?? '',
    'rating': card['rating']?.toString() ?? '',
    'reviews': card['reviews']?.toString() ?? '',
    'price': card['price']?.toString() ?? '',
    'address': card['address']?.toString() ?? card['location']?.toString() ?? '',
    'thumbnail': card['thumbnail']?.toString() ?? card['image']?.toString() ?? '',
    'images': (card['images'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [],
    'amenities': card['amenities'] ?? [],
    'gps_coordinates': card['gps_coordinates'] ?? card['geo'] ?? {},
  };
}

/// Normalize flight card structure (isolate-safe)
Map<String, dynamic> normalizeFlightCardIsolate(Map<String, dynamic> card) {
  return {
    'id': card['id']?.toString() ?? '',
    'airline': card['airline']?.toString() ?? '',
    'departure': card['departure']?.toString() ?? '',
    'arrival': card['arrival']?.toString() ?? '',
    'price': card['price']?.toString() ?? '',
    'duration': card['duration']?.toString() ?? '',
  };
}

/// Normalize restaurant card structure (isolate-safe)
Map<String, dynamic> normalizeRestaurantCardIsolate(Map<String, dynamic> card) {
  return {
    'id': card['id']?.toString() ?? '',
    'name': card['name']?.toString() ?? card['title']?.toString() ?? 'Unknown Restaurant',
    'description': card['description']?.toString() ?? '',
    'rating': card['rating']?.toString() ?? '',
    'reviews': card['reviews']?.toString() ?? '',
    'cuisine': card['cuisine']?.toString() ?? '',
    'price': card['price']?.toString() ?? '',
    'address': card['address']?.toString() ?? card['location']?.toString() ?? '',
    'thumbnail': card['thumbnail']?.toString() ?? card['image']?.toString() ?? '',
  };
}

/// Batch normalize multiple location cards (isolate-safe)
List<Map<String, dynamic>> normalizeLocationCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeLocationCardIsolate(card)).toList();
}

/// Batch normalize multiple hotel cards (isolate-safe)
List<Map<String, dynamic>> normalizeHotelCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeHotelCardIsolate(card)).toList();
}

/// Batch normalize multiple flight cards (isolate-safe)
List<Map<String, dynamic>> normalizeFlightCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeFlightCardIsolate(card)).toList();
}

/// Batch normalize multiple restaurant cards (isolate-safe)
List<Map<String, dynamic>> normalizeRestaurantCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeRestaurantCardIsolate(card)).toList();
}

/// ✅ FIX A: Batched normalization input model
class DisplayContentInput {
  final String? summary;
  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> hotels;
  final List<Map<String, dynamic>> flights;
  final List<Map<String, dynamic>> restaurants;

  DisplayContentInput({
    this.summary,
    required this.locations,
    required this.hotels,
    required this.flights,
    required this.restaurants,
  });

  Map<String, dynamic> toMap() {
    return {
      'summary': summary,
      'locations': locations,
      'hotels': hotels,
      'flights': flights,
      'restaurants': restaurants,
    };
  }

  factory DisplayContentInput.fromMap(Map<String, dynamic> map) {
    return DisplayContentInput(
      summary: map['summary']?.toString(),
      locations: (map['locations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      hotels: (map['hotels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      flights: (map['flights'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      restaurants: (map['restaurants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
  }
}

/// ✅ FIX A: Batched normalization output model
class DisplayContentOutput {
  final String summary;
  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> hotels;
  final List<Map<String, dynamic>> flights;
  final List<Map<String, dynamic>> restaurants;

  DisplayContentOutput({
    required this.summary,
    required this.locations,
    required this.hotels,
    required this.flights,
    required this.restaurants,
  });

  Map<String, dynamic> toMap() {
    return {
      'summary': summary,
      'locations': locations,
      'hotels': hotels,
      'flights': flights,
      'restaurants': restaurants,
    };
  }

  factory DisplayContentOutput.fromMap(Map<String, dynamic> map) {
    return DisplayContentOutput(
      summary: map['summary']?.toString() ?? '',
      locations: (map['locations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      hotels: (map['hotels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      flights: (map['flights'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      restaurants: (map['restaurants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
  }
}

/// ✅ FIX A: Batched normalization - ONE isolate call for all content types
/// This avoids isolate thrashing on older Android phones
/// Returns Map for compute() serialization
Map<String, dynamic> normalizeDisplayContentIsolate(Map<String, dynamic> input) {
  final data = DisplayContentInput.fromMap(input);
  
  // Normalize summary (clean markdown)
  final summary = data.summary != null && data.summary!.isNotEmpty
      ? cleanMarkdownIsolate(data.summary!)
      : '';
  
  // Normalize all card types in parallel (within same isolate)
  final locations = normalizeLocationCardsIsolate(data.locations);
  final hotels = normalizeHotelCardsIsolate(data.hotels);
  final flights = normalizeFlightCardsIsolate(data.flights);
  final restaurants = normalizeRestaurantCardsIsolate(data.restaurants);
  
  // Return as Map for compute() serialization
  return {
    'summary': summary,
    'locations': locations,
    'hotels': hotels,
    'flights': flights,
    'restaurants': restaurants,
  };
}


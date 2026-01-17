
String cleanMarkdownIsolate(String text) {
  if (text.isEmpty) return '';
  
  return text
      .replaceAll(RegExp(r'<[^>]*>'), '') 
      .replaceAll(RegExp(r'\*\*'), '') 
      .replaceAll(RegExp(r'[_~>`#-]'), '') 
      .replaceAll(RegExp(r'[0-9]+\.\s*'), '') 
      .replaceAll(RegExp(r'\s{2,}'), ' ') 
      .trim();
}


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


List<Map<String, dynamic>> normalizeLocationCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeLocationCardIsolate(card)).toList();
}


List<Map<String, dynamic>> normalizeHotelCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeHotelCardIsolate(card)).toList();
}


List<Map<String, dynamic>> normalizeFlightCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeFlightCardIsolate(card)).toList();
}


List<Map<String, dynamic>> normalizeRestaurantCardsIsolate(List<Map<String, dynamic>> cards) {
  return cards.map((card) => normalizeRestaurantCardIsolate(card)).toList();
}


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


Map<String, dynamic> normalizeDisplayContentIsolate(Map<String, dynamic> input) {
  final data = DisplayContentInput.fromMap(input);
  
  
  final summary = data.summary != null && data.summary!.isNotEmpty
      ? cleanMarkdownIsolate(data.summary!)
      : '';
  
  
  final locations = normalizeLocationCardsIsolate(data.locations);
  final hotels = normalizeHotelCardsIsolate(data.hotels);
  final flights = normalizeFlightCardsIsolate(data.flights);
  final restaurants = normalizeRestaurantCardsIsolate(data.restaurants);
  
  
  return {
    'summary': summary,
    'locations': locations,
    'hotels': hotels,
    'flights': flights,
    'restaurants': restaurants,
  };
}


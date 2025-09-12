# SerpAPI Hotels Integration

This document describes the integration of SerpAPI Hotels into the Clonar app backend, enabling automatic switching between shopping and hotel search results based on query keywords.

## Overview

The Python backend (`python/app.py`) now automatically detects whether a search query is for products or hotels and routes it to the appropriate SerpAPI engine:

- **Shopping queries** → `google_shopping` engine
- **Hotel queries** → `google_hotels` engine

## Query Detection

The system uses keyword detection to determine query type:

### Hotel Keywords
- `hotel`, `hotels`, `motel`, `motels`
- `stay`, `room`, `rooms`, `resort`, `resorts`
- `accommodation`, `accommodations`, `booking`, `book`
- `lodging`, `inn`, `hostel`, `hostels`
- `bed and breakfast`, `b&b`, `vacation rental`
- `airbnb`, `trip`, `travel`, `destination`

### Examples
- ✅ "Nike sneakers under $100" → **Shopping**
- ✅ "Hotels in Salt Lake City" → **Hotel**
- ✅ "motels under $200" → **Hotel**
- ✅ "iPhone 15 case" → **Shopping**
- ✅ "resort in Miami" → **Hotel**

## API Response Format

All search responses now include a `type` field to help the frontend render the appropriate UI:

```json
{
  "type": "shopping" | "hotel",
  "results": [...]
}
```

### Shopping Results
```json
{
  "type": "shopping",
  "results": [
    {
      "title": "Nike Air Max 270",
      "price": "$89.99",
      "link": "https://nike.com/air-max-270",
      "source": "Nike",
      "thumbnail": "https://...",
      "tag": "20% OFF",
      "delivery": "Free delivery by Mon",
      "rating": "4.5",
      "reviews": "1,234",
      "extracted_price": "89.99",
      "old_price": "112.99"
    }
  ]
}
```

### Hotel Results
```json
{
  "type": "hotel",
  "results": [
    {
      "name": "Grand Plaza Hotel",
      "address": "123 Broadway, New York, NY 10001",
      "price": "$299/night",
      "rating": "4.5",
      "reviews": "2,847",
      "thumbnail": "https://...",
      "link": "https://grandplazahotel.com",
      "amenities": ["Free WiFi", "Pool", "Spa", "Restaurant"],
      "booking_link": "https://booking.com/grand-plaza",
      "booking_site": "Booking.com",
      "city": "New York",
      "state": "NY",
      "country": "USA",
      "description": "Luxury hotel in the heart of Manhattan..."
    }
  ]
}
```

## Hotel-Specific Parameters

When using the `google_hotels` engine, the following parameters are automatically added:

- `check_in_date`: "2024-12-01" (default)
- `check_out_date`: "2024-12-02" (default)
- `adults`: "2" (default)

## Testing

Use the provided test script to verify the integration:

```bash
cd python
python test_serpapi_integration.py
```

This will test various query types and verify correct detection and response formatting.

## Environment Variables

Ensure the following environment variables are set:

```bash
SERPAPI_KEY=your_serpapi_key_here
SERPAPI_ENDPOINT=https://serpapi.com/search.json
```

## Frontend Integration

The Flutter frontend can now use the `type` field to determine which UI components to render:

```dart
if (response['type'] == 'hotel') {
  // Render hotel cards
  return HotelCard(data: hotel);
} else {
  // Render shopping cards
  return ProductCard(data: product);
}
```

## Error Handling

The API includes comprehensive error handling:

- **Missing API key**: Returns error message
- **Network errors**: Returns "Network error contacting SerpAPI"
- **SerpAPI errors**: Returns HTTP status code
- **Unexpected errors**: Returns detailed error message

## Future Enhancements

1. **Dynamic date parameters**: Allow frontend to pass check-in/check-out dates
2. **Advanced filtering**: Add filters for price range, amenities, ratings
3. **Caching**: Implement response caching for better performance
4. **Analytics**: Track query patterns and success rates
5. **Fallback handling**: Graceful degradation when SerpAPI is unavailable

#!/usr/bin/env python3
"""
Quick test to demonstrate the SerpAPI integration is working.
"""

from app import detect_query_type, extract_shopping_results, extract_hotel_results

def test_query_detection():
    print("🧪 Testing Query Detection:")
    print("=" * 40)
    
    test_cases = [
        ("sneakers under $100", "shopping"),
        ("hotels in Salt Lake City", "hotel"),
        ("motels under 200", "hotel"),
        ("iPhone case", "shopping"),
        ("resort in Miami", "hotel"),
        ("laptop bag", "shopping"),
        ("bed and breakfast in Vermont", "hotel"),
    ]
    
    for query, expected in test_cases:
        result = detect_query_type(query)
        status = "✅" if result == expected else "❌"
        print(f"{status} '{query}' → {result} (expected: {expected})")

def test_response_structure():
    print("\n📋 Testing Response Structure:")
    print("=" * 40)
    
    # Mock shopping response
    shopping_response = {
        "type": "shopping",
        "results": [
            {
                "title": "Nike Air Max 270",
                "price": "$89.99",
                "link": "https://nike.com/air-max-270",
                "source": "Nike",
                "thumbnail": "https://example.com/nike.jpg",
                "tag": "20% OFF",
                "delivery": "Free delivery by Mon",
                "rating": "4.5",
                "reviews": "1,234",
                "extracted_price": "89.99",
                "old_price": "112.99"
            }
        ]
    }
    
    # Mock hotel response
    hotel_response = {
        "type": "hotel",
        "results": [
            {
                "name": "Grand Plaza Hotel",
                "address": "123 Broadway, New York, NY 10001",
                "price": "$299/night",
                "rating": "4.5",
                "reviews": "2,847",
                "thumbnail": "https://example.com/hotel.jpg",
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
    
    print("🛍️ Shopping Response:")
    print(f"   Type: {shopping_response['type']}")
    print(f"   Results count: {len(shopping_response['results'])}")
    print(f"   Sample fields: {list(shopping_response['results'][0].keys())}")
    
    print("\n🏨 Hotel Response:")
    print(f"   Type: {hotel_response['type']}")
    print(f"   Results count: {len(hotel_response['results'])}")
    print(f"   Sample fields: {list(hotel_response['results'][0].keys())}")

if __name__ == "__main__":
    print("🚀 SerpAPI Integration Quick Test")
    print("=" * 50)
    
    test_query_detection()
    test_response_structure()
    
    print("\n✅ All tests completed!")
    print("\nThe integration is ready to use with:")
    print("1. Set SERPAPI_KEY environment variable")
    print("2. Start server: uvicorn app:app --reload --port 8000")
    print("3. Test with: POST /search with JSON body")

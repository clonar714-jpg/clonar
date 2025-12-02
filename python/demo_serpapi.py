#!/usr/bin/env python3
"""
Demo script showing SerpAPI Hotels integration.
This script demonstrates the keyword detection and response formatting.
"""

from app import detect_query_type, extract_shopping_results, extract_hotel_results

def demo_query_detection():
    """Demonstrate query type detection."""
    print("🔍 Query Type Detection Demo")
    print("=" * 40)
    
    test_queries = [
        "Nike sneakers under $100",
        "Hotels in Salt Lake City", 
        "motels under $200",
        "iPhone 15 case",
        "resort in Miami",
        "laptop bag",
        "bed and breakfast in Vermont",
        "vacation rental in Hawaii"
    ]
    
    for query in test_queries:
        query_type = detect_query_type(query)
        emoji = "🏨" if query_type == "hotel" else "🛍️"
        print(f"{emoji} '{query}' → {query_type}")

def demo_response_formatting():
    """Demonstrate response formatting for both types."""
    print("\n📋 Response Formatting Demo")
    print("=" * 40)
    
    # Mock shopping results
    mock_shopping_data = [
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
            "extracted_price_old": "112.99"
        }
    ]
    
    # Mock hotel results
    mock_hotel_data = [
        {
            "name": "Grand Plaza Hotel",
            "address": "123 Broadway, New York, NY 10001",
            "price": "$299/night",
            "rating": "4.5",
            "reviews": "2,847",
            "thumbnail": "https://example.com/hotel.jpg",
            "link": "https://grandplazahotel.com",
            "amenities": ["Free WiFi", "Pool", "Spa", "Restaurant"],
            "booking": {
                "link": "https://booking.com/grand-plaza",
                "name": "Booking.com"
            },
            "location": {
                "city": "New York",
                "state": "NY", 
                "country": "USA"
            },
            "description": "Luxury hotel in the heart of Manhattan with stunning city views."
        }
    ]
    
    print("🛍️ Shopping Results Format:")
    shopping_results = extract_shopping_results(mock_shopping_data)
    for key, value in shopping_results[0].items():
        print(f"   {key}: {value}")
    
    print("\n🏨 Hotel Results Format:")
    hotel_results = extract_hotel_results(mock_hotel_data)
    for key, value in hotel_results[0].items():
        print(f"   {key}: {value}")

def demo_api_response():
    """Show the complete API response format."""
    print("\n🌐 Complete API Response Format")
    print("=" * 40)
    
    # Shopping response
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
    
    # Hotel response
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
                "description": "Luxury hotel in the heart of Manhattan with stunning city views."
            }
        ]
    }
    
    print("🛍️ Shopping API Response:")
    print(f"   Type: {shopping_response['type']}")
    print(f"   Results count: {len(shopping_response['results'])}")
    print(f"   Sample title: {shopping_response['results'][0]['title']}")
    
    print("\n🏨 Hotel API Response:")
    print(f"   Type: {hotel_response['type']}")
    print(f"   Results count: {len(hotel_response['results'])}")
    print(f"   Sample name: {hotel_response['results'][0]['name']}")

if __name__ == "__main__":
    print("🚀 SerpAPI Hotels Integration Demo")
    print("=" * 50)
    
    demo_query_detection()
    demo_response_formatting()
    demo_api_response()
    
    print("\n✅ Demo completed!")
    print("\nTo test with real SerpAPI data:")
    print("1. Set SERPAPI_KEY environment variable")
    print("2. Start the Python server: uvicorn app:app --reload --port 8000")
    print("3. Run: python test_serpapi_integration.py")

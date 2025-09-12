#!/usr/bin/env python3
"""
Test script to demonstrate API response format with dotenv.
"""

import os
from dotenv import load_dotenv
from app import detect_query_type, extract_shopping_results, extract_hotel_results

def test_api_responses():
    """Test the API response format."""
    print("🧪 Testing API Response Format")
    print("=" * 50)
    
    # Load environment variables
    load_dotenv()
    
    # Check if SerpAPI key is configured
    serpapi_key = os.getenv("SERPAPI_KEY")
    if not serpapi_key or serpapi_key == "your_real_serpapi_key_here":
        print("⚠️  SerpAPI key not configured - showing mock responses")
        print("   Configure your key in .env file for real API calls")
    else:
        print("✅ SerpAPI key configured - ready for real API calls")
    
    print("\n📋 Response Format Examples:")
    print("-" * 30)
    
    # Test shopping query
    shopping_query = "Nike sneakers under $100"
    query_type = detect_query_type(shopping_query)
    
    print(f"🔍 Query: '{shopping_query}'")
    print(f"📊 Detected Type: {query_type}")
    
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
    
    print(f"📤 Response: {shopping_response['type']} with {len(shopping_response['results'])} results")
    
    # Test hotel query
    hotel_query = "Hotels in Salt Lake City"
    query_type = detect_query_type(hotel_query)
    
    print(f"\n🔍 Query: '{hotel_query}'")
    print(f"📊 Detected Type: {query_type}")
    
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
    
    print(f"📤 Response: {hotel_response['type']} with {len(hotel_response['results'])} results")
    
    print("\n✅ API Response Format Test Complete!")
    print("\n🚀 Ready to start server:")
    print("   python demo_server.py")

if __name__ == "__main__":
    test_api_responses()

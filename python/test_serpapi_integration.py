#!/usr/bin/env python3
"""
Test script for SerpAPI Hotels integration.
Tests both shopping and hotel query detection and response formatting.
"""

import asyncio
import httpx
import json

# Test queries
TEST_QUERIES = [
    {
        "query": "Nike sneakers under $100",
        "expected_type": "shopping",
        "description": "Shopping query - should return shopping results"
    },
    {
        "query": "Hotels in Salt Lake City",
        "expected_type": "hotel", 
        "description": "Hotel query - should return hotel results"
    },
    {
        "query": "motels under $200",
        "expected_type": "hotel",
        "description": "Motel query - should return hotel results"
    },
    {
        "query": "iPhone 15 case",
        "expected_type": "shopping",
        "description": "Product query - should return shopping results"
    },
    {
        "query": "resort in Miami",
        "expected_type": "hotel",
        "description": "Resort query - should return hotel results"
    }
]

async def test_query(query_data, base_url="http://localhost:8000"):
    """Test a single query against the search endpoint."""
    query = query_data["query"]
    expected_type = query_data["expected_type"]
    description = query_data["description"]
    
    print(f"\n🧪 Testing: {description}")
    print(f"   Query: '{query}'")
    print(f"   Expected type: {expected_type}")
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{base_url}/search",
                json={"query": query},
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                actual_type = data.get("type", "unknown")
                results = data.get("results", [])
                
                print(f"   ✅ Response received")
                print(f"   📊 Type: {actual_type} (expected: {expected_type})")
                print(f"   📈 Results count: {len(results)}")
                
                # Check if type matches expectation
                if actual_type == expected_type:
                    print(f"   ✅ Type detection correct!")
                else:
                    print(f"   ❌ Type detection failed!")
                
                # Show sample result structure
                if results:
                    sample = results[0]
                    print(f"   📋 Sample result fields: {list(sample.keys())}")
                    
                    if actual_type == "hotel":
                        print(f"   🏨 Hotel name: {sample.get('name', 'N/A')}")
                        print(f"   📍 Address: {sample.get('address', 'N/A')}")
                        print(f"   💰 Price: {sample.get('price', 'N/A')}")
                        print(f"   ⭐ Rating: {sample.get('rating', 'N/A')}")
                    else:
                        print(f"   🛍️ Product title: {sample.get('title', 'N/A')}")
                        print(f"   💰 Price: {sample.get('price', 'N/A')}")
                        print(f"   🏪 Source: {sample.get('source', 'N/A')}")
                
            else:
                print(f"   ❌ HTTP Error: {response.status_code}")
                print(f"   📄 Response: {response.text}")
                
    except httpx.RequestError as e:
        print(f"   ❌ Network error: {e}")
    except Exception as e:
        print(f"   ❌ Unexpected error: {e}")

async def main():
    """Run all test queries."""
    print("🚀 Starting SerpAPI Integration Tests")
    print("=" * 50)
    
    # Check if server is running
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get("http://localhost:8000/", timeout=5.0)
            if response.status_code == 200:
                print("✅ Python server is running")
            else:
                print("❌ Python server responded with error")
                return
    except httpx.RequestError:
        print("❌ Python server is not running. Please start it with:")
        print("   cd python && python -m uvicorn app:app --reload --port 8000")
        return
    
    # Run all tests
    for query_data in TEST_QUERIES:
        await test_query(query_data)
    
    print("\n" + "=" * 50)
    print("🏁 Tests completed!")

if __name__ == "__main__":
    asyncio.run(main())

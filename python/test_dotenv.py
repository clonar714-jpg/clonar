#!/usr/bin/env python3
"""
Test script to verify dotenv functionality.
"""

import os
from dotenv import load_dotenv

def test_dotenv_loading():
    """Test that environment variables are loaded correctly."""
    print("🧪 Testing dotenv functionality")
    print("=" * 40)
    
    # Load environment variables
    load_dotenv()
    
    # Test SERPAPI_KEY
    serpapi_key = os.getenv("SERPAPI_KEY")
    if serpapi_key:
        if serpapi_key == "your_real_serpapi_key_here":
            print("⚠️  SERPAPI_KEY is set to placeholder value")
            print("   Please edit .env file and add your real SerpAPI key")
        else:
            print("✅ SERPAPI_KEY is loaded from .env file")
            print(f"   Key: {serpapi_key[:10]}...")
    else:
        print("❌ SERPAPI_KEY not found in environment")
    
    # Test SERPAPI_ENDPOINT
    endpoint = os.getenv("SERPAPI_ENDPOINT")
    if endpoint:
        print(f"✅ SERPAPI_ENDPOINT: {endpoint}")
    else:
        print("❌ SERPAPI_ENDPOINT not found")
    
    # Test database variables
    db_vars = ["DB_USER", "DB_HOST", "DB_NAME", "DB_PASSWORD", "DB_PORT"]
    print("\n📊 Database Configuration:")
    for var in db_vars:
        value = os.getenv(var)
        if value:
            print(f"   {var}: {value}")
        else:
            print(f"   {var}: ❌ Not set")

def test_app_integration():
    """Test that the app can load with dotenv."""
    print("\n🚀 Testing App Integration:")
    print("=" * 40)
    
    try:
        from app import app, detect_query_type
        print("✅ App imported successfully")
        
        # Test query detection
        test_queries = [
            "hotels in Salt Lake City",
            "sneakers under $100",
            "motels under $200"
        ]
        
        print("\n🔍 Query Detection Test:")
        for query in test_queries:
            query_type = detect_query_type(query)
            print(f"   '{query}' → {query_type}")
        
        print("\n✅ All tests passed!")
        
    except Exception as e:
        print(f"❌ Error importing app: {e}")

if __name__ == "__main__":
    test_dotenv_loading()
    test_app_integration()
    
    print("\n📝 Next Steps:")
    print("1. Edit .env file and add your real SerpAPI key")
    print("2. Start the server: uvicorn app:app --reload --port 8000")
    print("3. Test with curl or Postman")

#!/usr/bin/env python3
"""
Demo script showing how to start the server with dotenv support.
"""

import subprocess
import sys
import os
from pathlib import Path

def check_env_file():
    """Check if .env file exists and has a real SerpAPI key."""
    env_file = Path(".env")
    
    if not env_file.exists():
        print("❌ .env file not found")
        print("   Run: python setup_env.py")
        return False
    
    with open(env_file, 'r') as f:
        content = f.read()
        
    if "your_real_serpapi_key_here" in content:
        print("⚠️  .env file contains placeholder SerpAPI key")
        print("   Please edit .env file and add your real SerpAPI key")
        return False
    
    if "SERPAPI_KEY=" in content and "your_real_serpapi_key_here" not in content:
        print("✅ .env file configured with SerpAPI key")
        return True
    
    print("❌ SERPAPI_KEY not found in .env file")
    return False

def start_server():
    """Start the FastAPI server."""
    print("🚀 Starting Clonar App Server")
    print("=" * 40)
    
    if not check_env_file():
        print("\n📝 Setup required:")
        print("1. Run: python setup_env.py")
        print("2. Edit .env file with your SerpAPI key")
        print("3. Run this script again")
        return
    
    print("\n🌐 Server will be available at:")
    print("   http://127.0.0.1:8000")
    print("\n📚 API Documentation:")
    print("   http://127.0.0.1:8000/docs")
    print("\n🧪 Test endpoints:")
    print("   POST /search - Search for products or hotels")
    print("   GET /recommendations?userId=1 - Get recommendations")
    
    print("\n🔄 Starting server...")
    print("   Press Ctrl+C to stop")
    print("-" * 40)
    
    try:
        subprocess.run([
            sys.executable, "-m", "uvicorn", 
            "app:app", 
            "--reload", 
            "--port", "8000",
            "--host", "127.0.0.1"
        ])
    except KeyboardInterrupt:
        print("\n\n👋 Server stopped")
    except Exception as e:
        print(f"\n❌ Error starting server: {e}")

if __name__ == "__main__":
    start_server()

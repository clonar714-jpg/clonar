#!/usr/bin/env python3
"""
Setup script to create .env file for Clonar App.
Run this script to create the .env file with placeholder values.
"""

import os

def create_env_file():
    """Create .env file with placeholder values."""
    env_content = """# Clonar App Environment Variables
# Replace with your actual API keys

# SerpAPI Configuration
SERPAPI_KEY=your_real_serpapi_key_here
SERPAPI_ENDPOINT=https://serpapi.com/search.json

# Database Configuration (for Node.js)
DB_USER=postgres
DB_HOST=postgres
DB_NAME=clonar_db
DB_PASSWORD=password
DB_PORT=5432
"""
    
    env_file_path = ".env"
    
    if os.path.exists(env_file_path):
        print(f"✅ .env file already exists at {env_file_path}")
        print("   Please edit it manually to add your SerpAPI key.")
    else:
        try:
            with open(env_file_path, 'w') as f:
                f.write(env_content)
            print(f"✅ Created .env file at {env_file_path}")
            print("   Please edit it to add your SerpAPI key.")
        except Exception as e:
            print(f"❌ Error creating .env file: {e}")
            print("   Please create it manually with the following content:")
            print("\n" + "="*50)
            print(env_content)
            print("="*50)

if __name__ == "__main__":
    print("🚀 Setting up environment variables for Clonar App")
    print("=" * 50)
    create_env_file()
    print("\n📝 Next steps:")
    print("1. Edit .env file and add your SerpAPI key")
    print("2. Install dependencies: pip install -r requirements.txt")
    print("3. Start the server: uvicorn app:app --reload --port 8000")
    print("4. Test with: curl -X POST http://127.0.0.1:8000/search -H 'Content-Type: application/json' -d '{\"query\":\"hotels in Salt Lake City\"}'")

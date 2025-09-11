import requests
import json

def test_python_service():
    """Test the Python FastAPI service"""
    try:
        response = requests.get("http://localhost:8000/hello")
        print("✅ Python Service Response:")
        print(json.dumps(response.json(), indent=2))
        return True
    except Exception as e:
        print(f"❌ Error calling Python service: {e}")
        return False

def test_node_service():
    """Test the Node.js service (when it's running)"""
    try:
        response = requests.get("http://localhost:3000/")
        print("✅ Node Service Response:")
        print(response.text)
        return True
    except Exception as e:
        print(f"❌ Error calling Node service: {e}")
        return False

def test_cross_service_communication():
    """Test Node calling Python (when Node is running)"""
    try:
        response = requests.get("http://localhost:3000/python")
        print("✅ Cross-Service Communication Response:")
        print(json.dumps(response.json(), indent=2))
        return True
    except Exception as e:
        print(f"❌ Error with cross-service communication: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Testing Microservices...")
    print("=" * 50)
    
    # Test Python service
    test_python_service()
    print()
    
    # Test Node service (if running)
    test_node_service()
    print()
    
    # Test cross-service communication (if Node is running)
    test_cross_service_communication()
    print()
    
    print("=" * 50)
    print("✅ Testing complete!")


from fastapi import FastAPI, HTTPException
import httpx
import os
import random
from pydantic import BaseModel

app = FastAPI()

class SearchRequest(BaseModel):
    query: str

# Mock product data for recommendations
MOCK_PRODUCTS = [
    {"id": 1, "name": "Classic White T-Shirt", "price": 29.99, "image_url": "https://example.com/tshirt.jpg", "category": "tops"},
    {"id": 2, "name": "Blue Jeans", "price": 79.99, "image_url": "https://example.com/jeans.jpg", "category": "bottoms"},
    {"id": 3, "name": "Black Sneakers", "price": 129.99, "image_url": "https://example.com/sneakers.jpg", "category": "shoes"},
    {"id": 4, "name": "Red Dress", "price": 89.99, "image_url": "https://example.com/dress.jpg", "category": "dresses"},
    {"id": 5, "name": "Leather Jacket", "price": 199.99, "image_url": "https://example.com/jacket.jpg", "category": "outerwear"},
    {"id": 6, "name": "Striped Sweater", "price": 59.99, "image_url": "https://example.com/sweater.jpg", "category": "tops"},
    {"id": 7, "name": "Black Pants", "price": 69.99, "image_url": "https://example.com/pants.jpg", "category": "bottoms"},
    {"id": 8, "name": "White Sneakers", "price": 119.99, "image_url": "https://example.com/white-sneakers.jpg", "category": "shoes"},
    {"id": 9, "name": "Summer Dress", "price": 79.99, "image_url": "https://example.com/summer-dress.jpg", "category": "dresses"},
    {"id": 10, "name": "Denim Jacket", "price": 89.99, "image_url": "https://example.com/denim-jacket.jpg", "category": "outerwear"},
]

@app.get("/")
def root():
    return {"message": "Clonar AI Recommendations Service 🐍", "status": "healthy"}

@app.get("/recommendations")
async def get_recommendations(userId: int):
    """
    Get personalized product recommendations for a user.
    For now, returns mock recommendations based on user ID.
    Later this will integrate with embeddings and vector DB.
    """
    try:
        # Mock recommendation logic based on user ID
        # In a real implementation, this would use ML models, user preferences, etc.
        
        # Simple mock: return 3-5 random products with some "personalization"
        random.seed(userId)  # Make recommendations consistent for same user
        num_recommendations = random.randint(3, 5)
        recommended_products = random.sample(MOCK_PRODUCTS, num_recommendations)
        
        # Add some mock personalization metadata
        personalization_score = random.uniform(0.7, 0.95)
        
        return {
            "recommendations": recommended_products,
            "personalization_score": round(personalization_score, 2),
            "user_id": userId,
            "algorithm": "mock_content_based",
            "total_products": len(MOCK_PRODUCTS)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate recommendations: {str(e)}")

@app.post("/search")
async def search_products(request: SearchRequest):
    query = request.query
    api_key = os.getenv("SERPAPI_KEY")
    endpoint = os.getenv("SERPAPI_ENDPOINT", "https://serpapi.com/search.json")

    if not api_key:
        return {"error": "SerpAPI key not configured"}

    params = {
        "engine": "google_shopping",
        "q": query,
        "hl": "en",
        "gl": "us",
        "api_key": api_key
    }

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(endpoint, params=params, timeout=30.0)

            if response.status_code == 200:
                payload = response.json()
                raw_results = payload.get("shopping_results", [])

                results = [
                    {
                        "title": item.get("title", ""),
                        "price": item.get("price", ""),
                        "link": item.get("link") or item.get("product_link", ""),
                        "source": item.get("source", ""),
                        "thumbnail": item.get("thumbnail", ""),

                        # ✅ Extra fields for shopping UI
                        "tag": item.get("tag", ""),                   # e.g. "18% OFF"
                        "delivery": item.get("delivery", ""),         # e.g. "Free delivery by Mon"
                        "rating": item.get("rating", ""),             # numeric rating (e.g. "4.5")
                        "reviews": item.get("reviews", ""),           # review count (e.g. "12")
                        "extracted_price": item.get("extracted_price", ""),  # numeric price
                        "old_price": item.get("extracted_price_old", ""),    # crossed out old price
                    }
                    for item in raw_results
                ]

                return {"results": results}

            # 🚨 Important: never forward full SerpAPI dump
            return {"error": f"SerpAPI error {response.status_code}"}

    except httpx.RequestError:
        return {"error": "Network error contacting SerpAPI"}
    except Exception:
        return {"error": "Unexpected server error"}

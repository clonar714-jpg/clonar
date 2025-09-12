from fastapi import FastAPI, HTTPException
import httpx
import os
import random
import datetime
from pydantic import BaseModel
from dotenv import load_dotenv

# Force load the root .env file (one level up from /python)
dotenv_path = os.path.join(os.path.dirname(__file__), "..", ".env")
load_dotenv(dotenv_path=dotenv_path)

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

def detect_query_type(query: str) -> str:
    """
    Detect if query is for hotels or shopping based on keywords and brand names.
    Returns 'hotel' or 'shopping'.
    """
    hotel_keywords = [
        "hotel", "hotels", "motel", "motels", "stay", "room", "rooms",
        "resort", "resorts", "accommodation", "accommodations", "booking",
        "book", "lodging", "inn", "hostel", "hostels", "bed and breakfast",
        "b&b", "vacation rental", "airbnb", "trip", "travel", "destination"
    ]

    hotel_brands = [
        "marriott", "hilton", "hyatt", "sheraton", "ritz", "holiday inn",
        "westin", "fairfield", "courtyard", "hampton", "embassy suites",
        "doubletree", "st regis", "four seasons", "motel 6", "best western"
    ]

    query_lower = query.lower()

    # Check for explicit hotel-related words
    if any(keyword in query_lower for keyword in hotel_keywords):
        return "hotel"

    # Check for known hotel brand names
    if any(brand in query_lower for brand in hotel_brands):
        return "hotel"

    return "shopping"

def extract_shopping_results(raw_results):
    """Extract and format shopping results from SerpAPI response."""
    return [
        {
            "title": item.get("title", ""),
            "price": item.get("price", ""),
            "link": item.get("link") or item.get("product_link", ""),
            "source": item.get("source", ""),
            "thumbnail": item.get("thumbnail", ""),
            "tag": item.get("tag", ""),
            "delivery": item.get("delivery", ""),
            "rating": item.get("rating", ""),
            "reviews": item.get("reviews", ""),
            "extracted_price": item.get("extracted_price", ""),
            "old_price": item.get("extracted_price_old", ""),
        }
        for item in raw_results
    ]

def extract_hotel_results(raw_results):
    """Extract and format hotel results from SerpAPI response."""
    results = []
    
    for item in raw_results:
        # Extract basic hotel information with correct field mappings
        hotel_data = {
            "name": item.get("name", ""),
            "address": item.get("address", ""),
            "price": item.get("rate_per_night", {}).get("lowest", ""),
            "rating": item.get("overall_rating", ""),
            "reviews": item.get("reviews", ""),
            "thumbnail": item.get("thumbnail", ""),
            "link": item.get("link", ""),
        }
        
        # Extract images properly from the images array
        images = item.get("images", [])
        if images and isinstance(images, list):
            # Extract all thumbnail URLs from the images array
            image_urls = []
            for img in images:
                if isinstance(img, dict) and "thumbnail" in img:
                    thumbnail_url = img["thumbnail"]
                    if thumbnail_url and thumbnail_url.strip():
                        image_urls.append(thumbnail_url)
            
            # Set thumbnail to first image if available
            if image_urls:
                hotel_data["thumbnail"] = image_urls[0]
                hotel_data["images"] = image_urls
            else:
                hotel_data["images"] = []
        else:
            hotel_data["images"] = []
        
        # Extract amenities if available
        amenities = []
        if "amenities" in item:
            if isinstance(item["amenities"], list):
                amenities = item["amenities"]
            elif isinstance(item["amenities"], str):
                amenities = [item["amenities"]]
        
        hotel_data["amenities"] = amenities
        
        # Extract booking information
        booking_info = item.get("booking", {})
        if booking_info:
            hotel_data["booking_link"] = booking_info.get("link", "")
            hotel_data["booking_site"] = booking_info.get("name", "")
        
        # Add location details
        location = item.get("location", {})
        if location:
            hotel_data["city"] = location.get("city", "")
            hotel_data["state"] = location.get("state", "")
            hotel_data["country"] = location.get("country", "")
        
        # Add description if available
        hotel_data["description"] = item.get("description", "")
        
        results.append(hotel_data)
    
    return results

@app.post("/search")
async def search_products(request: SearchRequest):
    query = request.query
    api_key = os.getenv("SERPAPI_KEY")
    endpoint = os.getenv("SERPAPI_ENDPOINT", "https://serpapi.com/search.json")

    if not api_key:
        return {"error": "SerpAPI key not configured"}

    # Detect query type and set appropriate engine
    query_type = detect_query_type(query)
    engine = "google_hotels" if query_type == "hotel" else "google_shopping"

    params = {
        "engine": engine,
        "q": query,
        "hl": "en",
        "gl": "us",
        "api_key": api_key
    }

    # Add hotel-specific parameters
    if engine == "google_hotels":
        # Use dynamic dates: check-in 7 days from today, check-out 8 days from today
        today = datetime.date.today()
        check_in = today + datetime.timedelta(days=7)
        check_out = today + datetime.timedelta(days=8)
        
        params.update({
            "check_in_date": check_in.strftime("%Y-%m-%d"),
            "check_out_date": check_out.strftime("%Y-%m-%d"),
            "adults": "2",
            "currency": "USD",
            "gl": "us",
            "hl": "en"
        })

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(endpoint, params=params, timeout=30.0)

            if response.status_code == 200:
                payload = response.json()
                
                if query_type == "hotel":
                    # Debug: Log payload keys to understand what SerpAPI returns
                    print(f"Hotel query payload keys: {list(payload.keys())}")
                    
                    # Extract hotel results - check multiple possible keys
                    raw_results = (
                        payload.get("hotels")
                        or payload.get("properties")
                        or payload.get("organic_results")
                        or payload.get("hotel_results")
                        or []
                    )
                    print(f"Raw hotel results count: {len(raw_results)}")
                    
                    # If no results, try fallback with modified query
                    if not raw_results:
                        print(f"No hotel results found, trying fallback for query: {query}")
                        fallback_query = f"hotels {query}"
                        print(f"Fallback query: {fallback_query}")
                        
                        # Retry with fallback query
                        fallback_params = params.copy()
                        fallback_params["q"] = fallback_query
                        
                        try:
                            fallback_response = await client.get(endpoint, params=fallback_params, timeout=30.0)
                            if fallback_response.status_code == 200:
                                fallback_payload = fallback_response.json()
                                print(f"Fallback payload keys: {list(fallback_payload.keys())}")
                                raw_results = (
                                    fallback_payload.get("hotels")
                                    or fallback_payload.get("properties")
                                    or fallback_payload.get("organic_results")
                                    or fallback_payload.get("hotel_results")
                                    or []
                                )
                                print(f"Fallback hotel results count: {len(raw_results)}")
                        except Exception as e:
                            print(f"Fallback request failed: {str(e)}")
                    
                    results = extract_hotel_results(raw_results)
                else:
                    # Extract shopping results
                    raw_results = payload.get("shopping_results", [])
                    results = extract_shopping_results(raw_results)

                return {
                    "type": query_type,
                    "results": results
                }

            return {"error": f"SerpAPI error {response.status_code}"}

    except httpx.RequestError:
        return {"error": "Network error contacting SerpAPI"}
    except Exception as e:
        return {"error": f"Unexpected server error: {str(e)}"}

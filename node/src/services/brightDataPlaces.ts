// src/services/brightDataPlaces.ts
/**
 * BrightData Google Places Scraper Integration
 * 
 * This service interfaces with BrightData's Google Places scraper API
 * to fetch tourist attractions, landmarks, and places of interest.
 */

export interface PlaceItem {
  name: string;
  rating: number;
  reviews: number;
  category: string;
  photos: string[];
  geo: {
    lat: number;
    lng: number;
  };
  website?: string;
  phone?: string;
  google_url?: string;
  address?: string;
  description?: string;
}

export interface BrightDataPlacesResponse {
  success: boolean;
  places: PlaceItem[];
  error?: string;
}

/**
 * Extract location (city/country) from query
 */
export function extractLocationFromQuery(query: string): string | null {
  // Patterns: "places in Thailand", "things to do in Paris", "attractions in Tokyo"
  const match = query.match(/\b(in|at|near)\s+([A-Z][a-zA-Z\s]+)/i);
  if (match) {
    return match[2].trim();
  }
  
  // Fallback: check if query ends with a capitalized word (likely a place name)
  const words = query.split(/\s+/);
  const lastWord = words[words.length - 1];
  if (lastWord && lastWord[0] === lastWord[0].toUpperCase() && lastWord.length > 2) {
    return lastWord;
  }
  
  return null;
}

/**
 * Search places using BrightData API
 * 
 * Note: Replace with your actual BrightData API endpoint and credentials
 */
export async function searchPlaces(
  query: string,
  location?: string | null
): Promise<PlaceItem[]> {
  try {
    // Build final query with location
    const finalQuery = location 
      ? `${query} in ${location}`
      : query;

    // BrightData API endpoint (replace with your actual endpoint)
    const brightDataUrl = process.env.BRIGHTDATA_PLACES_URL || 
      "https://api.brightdata.com/google_places/search";
    
    const apiKey = process.env.BRIGHTDATA_API_KEY;
    
    if (!apiKey) {
      console.warn("⚠️ BrightData API key not configured, returning mock data");
      return getMockPlacesData(finalQuery);
    }

    const response = await fetch(brightDataUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        query: finalQuery,
        max_results: 30,
      }),
    });

    if (!response.ok) {
      console.error(`❌ BrightData API error: ${response.status}`);
      return getMockPlacesData(finalQuery);
    }

    const data = await response.json();
    
    // Parse BrightData response format
    if (data.places && Array.isArray(data.places)) {
      return data.places.map((p: any) => ({
        name: p.name || p.title || "",
        rating: p.rating || p.stars || 0,
        reviews: p.reviews || p.review_count || 0,
        category: p.category || p.type || "attraction",
        photos: p.photos || p.images || [],
        geo: {
          lat: p.lat || p.latitude || p.geo?.lat || 0,
          lng: p.lng || p.longitude || p.geo?.lng || 0,
        },
        website: p.website || p.url,
        phone: p.phone || p.phone_number,
        google_url: p.google_url || p.google_maps_url,
        address: p.address || p.location,
        description: p.description || p.summary,
      }));
    }

    return getMockPlacesData(finalQuery);
  } catch (err: any) {
    console.error("❌ BrightData places search error:", err.message);
    return getMockPlacesData(query);
  }
}

/**
 * Mock data for development/testing
 */
function getMockPlacesData(query: string): PlaceItem[] {
  const location = extractLocationFromQuery(query) || "Thailand";
  
  return [
    {
      name: "Erawan National Park",
      rating: 4.6,
      reviews: 15199,
      category: "national_park",
      photos: ["https://example.com/erawan.jpg"],
      geo: { lat: 14.3667, lng: 99.1333 },
      website: "https://example.com/erawan",
      address: "Kanchanaburi, Thailand",
      description: "Famous for its seven-tiered waterfall",
    },
    {
      name: "Wat Pho",
      rating: 4.7,
      reviews: 45231,
      category: "temple",
      photos: ["https://example.com/watpho.jpg"],
      geo: { lat: 13.7467, lng: 100.4944 },
      website: "https://example.com/watpho",
      address: "Bangkok, Thailand",
      description: "Temple of the Reclining Buddha",
    },
    {
      name: "Phi Phi Islands",
      rating: 4.8,
      reviews: 67890,
      category: "island",
      photos: ["https://example.com/phiphi.jpg"],
      geo: { lat: 7.7333, lng: 98.7667 },
      address: "Krabi, Thailand",
      description: "Stunning tropical islands with crystal-clear waters",
    },
  ];
}


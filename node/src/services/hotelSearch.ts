// src/services/hotelSearch.ts
import axios from "axios";
import { refineQuery } from "./llmQueryRefiner";
import { extractHotelThemes, hasThemeSupport } from "./hotelThemeExtractor";
import { generateHotelDescription } from "./hotelDescriptionGenerator";
import { repairQuery } from "./queryRepair";

// Helper to geocode an address using Google Maps Geocoding API
async function geocodeAddress(address: string): Promise<{ latitude: number; longitude: number } | null> {
  const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!apiKey || !address) return null;

  try {
    const geocodeUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${apiKey}`;
    const response = await axios.get(geocodeUrl);
    
    if (response.data.status === 'OK' && response.data.results && response.data.results.length > 0) {
      const location = response.data.results[0].geometry.location;
      return {
        latitude: location.lat,
        longitude: location.lng,
      };
    }
  } catch (error: any) {
    console.error(`❌ Geocoding error for "${address}":`, error.message);
  }
  
  return null;
}

function safeString(v: any): string {
  return v ? v.toString() : "";
}

function safeNumber(v: any): number {
  if (!v) return 0;
  const n = Number(String(v).replace(/[^\d.]/g, ""));
  return isNaN(n) ? 0 : n;
}

function safeImage(v: any): string {
  return typeof v === "string" ? v : "";
}

function safeNumberOrNull(v: any): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return isNaN(v) ? null : v;
  const parsed = parseFloat(String(v));
  return isNaN(parsed) ? null : parsed;
}

function normalizeHotel(item: any) {
  // Build images array - include thumbnail if not already in images
  const imageList: string[] = [];
  const thumbnail =
    safeImage(item.thumbnail) ||
    safeImage(item.image) ||
    (item.images?.[0] ? safeImage(item.images[0]?.original_image || item.images[0]) : "") ||
    "";
  
  if (thumbnail) {
    imageList.push(thumbnail);
  }
  if (item.images && Array.isArray(item.images)) {
    item.images.forEach((img: any) => {
      const imgUrl = safeImage(img?.original_image || img?.thumbnail || img);
      if (imgUrl && !imageList.includes(imgUrl)) {
        imageList.push(imgUrl);
      }
    });
  }
  const images = imageList.length > 0 ? imageList : (thumbnail ? [thumbnail] : []);

  // Extract GPS coordinates from SerpAPI response
  // SerpAPI may return coordinates in various formats:
  // - gps_coordinates: { latitude: X, longitude: Y }
  // - coordinates: { lat: X, lng: Y }
  // - latitude/longitude: direct fields
  // - geo: { lat: X, lng: Y }
  let gpsCoordinates: any = null;
  let latitude: number | null = null;
  let longitude: number | null = null;
  
  if (item.gps_coordinates) {
    gpsCoordinates = item.gps_coordinates;
    latitude = safeNumberOrNull(item.gps_coordinates.latitude);
    longitude = safeNumberOrNull(item.gps_coordinates.longitude);
  } else if (item.coordinates) {
    latitude = safeNumberOrNull(item.coordinates.lat || item.coordinates.latitude);
    longitude = safeNumberOrNull(item.coordinates.lng || item.coordinates.longitude);
    if (latitude !== null && longitude !== null) {
      gpsCoordinates = { latitude, longitude };
    }
  } else if (item.latitude !== undefined || item.longitude !== undefined) {
    latitude = safeNumberOrNull(item.latitude);
    longitude = safeNumberOrNull(item.longitude);
    if (latitude !== null && longitude !== null) {
      gpsCoordinates = { latitude, longitude };
    }
  } else if (item.geo) {
    latitude = safeNumberOrNull(item.geo.lat || item.geo.latitude);
    longitude = safeNumberOrNull(item.geo.lng || item.geo.longitude);
    if (latitude !== null && longitude !== null) {
      gpsCoordinates = { latitude, longitude };
    }
  }
  
  // If still no coordinates but we have an address, we'll geocode it later
  // (geocoding is async, so we'll do it in the searchHotels function)

  // Extract reviews for theme extraction
  const reviews = item.reviews || item.review_snippets || item.review_texts || [];
  
  return {
    name: safeString(item.name || item.hotel_name || item.property_name || "Unknown Hotel"),
    title: safeString(item.name || item.hotel_name || item.property_name || item.title || "Unknown Hotel"), // Keep 'title' for compatibility
    address: safeString(item.address || item.location),
    rating: safeNumber(item.rating || item.overall_rating || item.stars),
    price: safeString(item.price || item.rate_per_night?.lowest || item.extracted_price || "0"),
    thumbnail,
    images,
    link: safeString(item.link || item.url || item.booking_link),
    reviews: safeNumber(item.reviews || item.review_count),
    reviewTexts: Array.isArray(reviews) ? reviews : [], // Store review texts for theme extraction
    phone: safeString(item.phone),
    source: safeString(item.source || "Google Hotels"), // Keep for compatibility
    // Include GPS coordinates for map display
    gps_coordinates: gpsCoordinates,
    latitude: latitude,
    longitude: longitude,
    geo: latitude !== null && longitude !== null ? { lat: latitude, lng: longitude } : null,
    // Include raw data for theme extraction
    amenities: item.amenities,
    service: item.service || item.service_rating,
    rooms: item.rooms || item.rooms_rating,
    cleanliness: item.cleanliness || item.cleanliness_rating,
    value: item.value || item.value_rating,
  };
}

/**
 * 🚀 C6 PATCH #7 — Primary hotel search (SerpAPI)
 */
async function serpHotelSearch(query: string): Promise<any[]> {
  const serpUrl = "https://serpapi.com/search.json";
  const serpKey = process.env.SERPAPI_KEY;

  if (!serpKey) {
    throw new Error("Missing SERPAPI_KEY");
  }

  const today = new Date();
  const checkIn = new Date(today);
  checkIn.setDate(today.getDate() + 7);
  const checkOut = new Date(checkIn);
  checkOut.setDate(checkIn.getDate() + 1);

  const params: any = {
    engine: "google_hotels",
    q: query,
    hl: "en",
    gl: "us",
    api_key: serpKey,
    num: 20, // Increased from 10 to 20 to get more hotels (Perplexity shows ~13)
    check_in_date: checkIn.toISOString().split("T")[0],
    check_out_date: checkOut.toISOString().split("T")[0],
    adults: "2",
    currency: "USD",
  };

  const res = await axios.get(serpUrl, { params });
  const items = res.data.properties || [];
  
  // Debug: Log first item structure to see what SerpAPI returns
  if (items.length > 0) {
    console.log('🔍 SerpAPI hotel item keys:', Object.keys(items[0]));
    if (items[0].gps_coordinates) {
      console.log('✅ SerpAPI provides gps_coordinates:', items[0].gps_coordinates);
    } else if (items[0].coordinates) {
      console.log('✅ SerpAPI provides coordinates:', items[0].coordinates);
    } else {
      console.log('⚠️ SerpAPI does not provide coordinates in item');
    }
  }
  
  const normalized = items.map(normalizeHotel);
  console.log(`🏨 Normalized ${normalized.length} hotels from SerpAPI`);
  
  // Log coordinate status
  normalized.forEach((hotel, idx) => {
    if (hotel.latitude && hotel.longitude) {
      console.log(`✅ Hotel ${idx + 1} "${hotel.name}" has coordinates: ${hotel.latitude}, ${hotel.longitude}`);
    } else {
      console.log(`⚠️ Hotel ${idx + 1} "${hotel.name}" missing coordinates. Address: ${hotel.address || 'N/A'}`);
    }
  });
  
  // Geocode addresses for hotels without coordinates
  const geocodePromises = normalized.map(async (hotel) => {
    if (!hotel.latitude && !hotel.longitude && hotel.address) {
      console.log(`🌍 Geocoding address for "${hotel.name}": ${hotel.address}`);
      const coords = await geocodeAddress(hotel.address);
      if (coords) {
        hotel.latitude = coords.latitude;
        hotel.longitude = coords.longitude;
        hotel.gps_coordinates = coords;
        hotel.geo = { lat: coords.latitude, lng: coords.longitude };
        console.log(`✅ Geocoded "${hotel.name}": ${coords.latitude}, ${coords.longitude}`);
      } else {
        console.log(`❌ Failed to geocode "${hotel.name}"`);
      }
    }
    return hotel;
  });
  
  // Wait for all geocoding to complete (with timeout)
  await Promise.allSettled(geocodePromises);
  
  // Final check
  const hotelsWithCoords = normalized.filter(h => h.latitude && h.longitude);
  console.log(`📍 Final: ${hotelsWithCoords.length}/${normalized.length} hotels have coordinates`);
  
  return normalized;
}

/**
 * 🚀 C6 PATCH #7 — Fallback hotel APIs (placeholder for future integration)
 */
async function fallbackHotelAPIs(query: string): Promise<any[]> {
  // Placeholder for future APIs (Booking.com, Expedia, etc.)
  // For now, return empty array
  return [];
}

// ✅ Helper function to extract themes and generate descriptions for hotels
// ⚠️ This should ONLY be called AFTER filtering/reranking for final displayed results
export async function enrichHotelsWithThemesAndDescriptions(hotels: any[]): Promise<any[]> {
  if (hotels.length === 0) return hotels;
  
  console.log(`🏨 Enriching ${hotels.length} hotels with themes and descriptions...`);
  
  const enriched = await Promise.allSettled(
    hotels.slice(0, 20).map(async (hotel: any) => {
      try {
        // Add timeout wrapper for theme extraction (3 seconds max)
        const themesPromise = extractHotelThemes(
          hotel.name || "Hotel",
          hotel.reviewTexts || [],
          hotel
        );
        
        const timeoutPromise = new Promise<string[]>((resolve) => 
          setTimeout(() => resolve(inferDefaultThemes(hotel)), 3000)
        );
        
        const themes = await Promise.race([themesPromise, timeoutPromise]);
        
        // Filter themes to only include those with supporting data
        const supportedThemes = themes.filter((theme: string) => 
          hasThemeSupport(theme, hotel)
        );

        // ✅ Generate Perplexity-style description (with timeout)
        let description = '';
        try {
          const descriptionPromise = generateHotelDescription(
            hotel.name || "Hotel",
            hotel,
            undefined // sectionHeading - can be passed from search context if needed
          );
          
          const descriptionTimeout = new Promise<string>((resolve) => 
            setTimeout(() => resolve(''), 4000) // 4 second timeout
          );
          
          description = await Promise.race([descriptionPromise, descriptionTimeout]);
        } catch (descErr: any) {
          console.error(`❌ Error generating description for "${hotel.name}":`, descErr.message);
          // Continue without description on error
        }
        
        return {
          ...hotel,
          themes: supportedThemes.length > 0 ? supportedThemes : themes.slice(0, 3), // Fallback to first 3 if none supported
          description: description || hotel.description || '', // Use generated description or fallback
        };
      } catch (err: any) {
        console.error(`❌ Error processing "${hotel.name}":`, err.message);
        // Return hotel with default themes on error
        return {
          ...hotel,
          themes: inferDefaultThemes(hotel),
          description: hotel.description || '',
        };
      }
    })
  );
  
  // Extract successful results
  const results = enriched.map((result, index) => 
    result.status === 'fulfilled' ? result.value : {
      ...hotels[index],
      themes: inferDefaultThemes(hotels[index]),
      description: hotels[index].description || '',
    }
  );
  
  console.log(`✅ Theme and description generation complete for ${results.length} hotels`);
  return results;
}

/**
 * 🚀 C6 PATCH #7 — Multi-API fallback for hotels
 */
export async function searchHotels(query: string): Promise<any[]> {
  try {
    // 🔮 STEP 0: LLM Query Repair (Perplexity-style) - MUST happen FIRST
    const repairedQuery = await repairQuery(query, "hotels");
    console.log(`🔮 Query repair (hotels): "${query}" → "${repairedQuery}"`);
    console.log("🏨 Hotel search:", repairedQuery);

    const results: any[] = [];

    // Attempt 1 — Primary SerpAPI (use repaired query)
    try {
      const primary = await serpHotelSearch(repairedQuery);
      results.push(...primary);
      if (results.length >= 3) {
        console.log(`🏨 Found ${results.length} hotels (primary)`);
        // ⚠️ Description generation removed - will be done AFTER filtering in agent.ts
        return results.slice(0, 20);
      }
    } catch (err: any) {
      console.error("❌ Primary hotel search failed:", err.message);
    }

    // Attempt 2 — LLM-refined query (use repaired query as base)
    try {
      const refinedQuery = await refineQuery(repairedQuery, "hotels");
      const refined = await serpHotelSearch(refinedQuery);
      results.push(...refined);
      if (results.length >= 3) {
        console.log(`🏨 Found ${results.length} hotels (refined query)`);
        // ⚠️ Description generation removed - will be done AFTER filtering in agent.ts
        return results.slice(0, 20);
      }
    } catch (err: any) {
      console.error("❌ Refined hotel search failed:", err.message);
    }

    // Attempt 3 — Fallback APIs
    try {
      const fallback = await fallbackHotelAPIs(repairedQuery);
      results.push(...fallback);
    } catch (err: any) {
      console.error("❌ Fallback hotel APIs failed:", err.message);
    }

    // Deduplicate results
    const seen = new Set<string>();
    const merged = results.filter((h: any) => {
      const key = `${h.name || ""}_${h.address || ""}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });

    // ⚠️ Description generation removed - will be done AFTER filtering in agent.ts
    if (merged.length > 0) {
      return merged.slice(0, 20);
    }

    // ✅ C6 PATCH #8 — Never return empty cards
    console.warn("⚠️ No hotels found, returning error card");
    return [
      {
        name: "No hotels found",
        title: "No hotels found",
        address: "",
        rating: 0,
        price: "0",
        thumbnail: "",
        images: [],
        link: "",
        reviews: 0,
        phone: "",
        source: "Search",
      },
    ];
  } catch (err: any) {
    console.error("❌ Hotel search error:", err.message || err);
    // ✅ C6 PATCH #8 — Never return empty cards
    return [
      {
        name: "Error loading hotels",
        title: "Error loading hotels",
        address: "",
        rating: 0,
        price: "0",
        thumbnail: "",
        images: [],
        link: "",
        reviews: 0,
        phone: "",
        source: "Error",
      },
    ];
  }
}

/**
 * Fallback: Infer default themes from hotel metadata
 */
function inferDefaultThemes(hotel: any): string[] {
  const themes: string[] = [];

  if (hotel.address || hotel.location || hotel.geo) {
    themes.push("Location");
  }

  if (hotel.amenities && Array.isArray(hotel.amenities) && hotel.amenities.length > 0) {
    themes.push("Amenities");
  }

  if (hotel.service || hotel.service_rating) {
    themes.push("Service");
  }

  return themes.length > 0 ? themes : ["Location", "Amenities", "Service"];
}

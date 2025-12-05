// src/services/placesSearch.ts
import OpenAI from "openai";
import axios from "axios";
import { repairQuery } from "./queryRepair";

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    if (!process.env.OPENAI_API_KEY) {
      throw new Error("Missing OPENAI_API_KEY");
    }
    client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });
  }
  return client;
}

// Helper to geocode an address using Google Maps Geocoding API
async function geocodeAddress(address: string, placeName: string): Promise<{ latitude: number; longitude: number } | null> {
  const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!apiKey) {
    console.warn("⚠️ GOOGLE_MAPS_BACKEND_KEY not configured, skipping geocoding");
    return null;
  }

  try {
    // Build search query: "Place Name, Address" for better accuracy
    const searchQuery = address.includes(placeName) ? address : `${placeName}, ${address}`;
    const geocodeUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(searchQuery)}&key=${apiKey}`;
    
    const response = await axios.get(geocodeUrl, { timeout: 5000 });
    
    if (response.data.status === 'OK' && response.data.results && response.data.results.length > 0) {
      const location = response.data.results[0].geometry.location;
      return {
        latitude: location.lat,
        longitude: location.lng,
      };
    } else if (response.data.status === 'REQUEST_DENIED') {
      console.error(`❌ Geocoding API REQUEST_DENIED for "${placeName}": ${response.data.error_message || 'API key not authorized'}`);
      console.error(`   Make sure GOOGLE_MAPS_BACKEND_KEY has Geocoding API enabled in Google Cloud Console`);
    } else {
      console.warn(`⚠️ Geocoding failed for "${placeName}": Status ${response.data.status}`);
    }
  } catch (error: any) {
    console.error(`❌ Geocoding error for "${placeName}, ${address}":`, error.message);
  }
  
  return null;
}

// Helper to get place image, website, and phone from Google Places API
async function getPlaceDetails(placeName: string, location: string): Promise<{
  image: string | null;
  website: string | null;
  phone: string | null;
}> {
  const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!apiKey) {
    console.warn("⚠️ GOOGLE_MAPS_BACKEND_KEY not configured, skipping place details fetch");
    return { image: null, website: null, phone: null };
  }

  try {
    // First, find the place using Places API Text Search
    const searchQuery = `${placeName}, ${location}`;
    const placesUrl = `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(searchQuery)}&key=${apiKey}`;
    
    const searchResponse = await axios.get(placesUrl, { timeout: 5000 });
    
    if (searchResponse.data.status === 'OK' && searchResponse.data.results && searchResponse.data.results.length > 0) {
      const place = searchResponse.data.results[0];
      let imageUrl: string | null = null;
      
      // Try to get photo from search result first (faster)
      if (place.photos && place.photos.length > 0) {
        const photo = place.photos[0];
        imageUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${photo.photo_reference}&key=${apiKey}`;
      }
      
      // ✅ ENHANCEMENT: Get place details to access website, phone, and photos
      if (place.place_id) {
        // Request website, phone, and photos fields
        const detailsUrl = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${place.place_id}&fields=photos,website,formatted_phone_number,international_phone_number&key=${apiKey}`;
        const detailsResponse = await axios.get(detailsUrl, { timeout: 5000 });
        
        if (detailsResponse.data.status === 'OK' && detailsResponse.data.result) {
          const details = detailsResponse.data.result;
          
          // Get photo if we don't have one yet
          if (!imageUrl && details.photos && details.photos.length > 0) {
            const photo = details.photos[0];
            imageUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${photo.photo_reference}&key=${apiKey}`;
          }
          
          // Extract website and phone
          const website = details.website || null;
          const phone = details.formatted_phone_number || details.international_phone_number || null;
          
          return {
            image: imageUrl,
            website: website,
            phone: phone,
          };
        }
      }
      
      // If we got image but no details, return just the image
      return {
        image: imageUrl,
        website: null,
        phone: null,
      };
    } else if (searchResponse.data.status === 'REQUEST_DENIED') {
      console.error(`❌ Places API REQUEST_DENIED for "${placeName}": ${searchResponse.data.error_message || 'API key not authorized'}`);
      console.error(`   Make sure GOOGLE_MAPS_BACKEND_KEY has Places API enabled in Google Cloud Console`);
    }
  } catch (error: any) {
    // Don't log as error if it's just API not available
    if (error.response?.status !== 403 && error.response?.status !== 401) {
      console.error(`❌ Error fetching place details for "${placeName}":`, error.message);
    }
  }
  
  return { image: null, website: null, phone: null };
}

/**
 * STRUCTURE OF RESULTS RETURNED TO FRONTEND:
 *
 * [
 *   {
 *     name: "Erawan National Park",
 *     type: "nature",
 *     rating: "4.6",
 *     location: "Kanchanaburi, Thailand",
 *     description: "...",
 *     image: "https://...",
 *     section: "Nature & Adventure"
 *   },
 *   ...
 * ]
 */

export async function searchPlaces(query: string): Promise<any[]> {
  // 🔮 STEP 0: LLM Query Repair (Perplexity-style) - MUST happen FIRST
  const repairedQuery = await repairQuery(query, "places");
  console.log(`🔮 Query repair (places): "${query}" → "${repairedQuery}"`);
  
  const client = getClient();

  const system = `
You are a Places Engine used by an AI search engine (similar to Perplexity).

Your job:
1. Extract the main CITY / REGION from the query.

2. Identify what type of place the user wants:
   - places to visit
   - attractions
   - things to do
   - nature & adventure
   - museums
   - nightlife
   - beaches
   - landmarks
   - food spots (only if explicitly asked)

3. Return a JSON array of 8–15 recommended places with:
   - name
   - section (e.g., "Nature & Adventure", "Top Sights", "Museums")
   - type ("nature", "temple", "museum", "landmark", "island", etc.)
   - rating (fake but realistic, like 4.5, 4.7, etc.)
   - location (City, Country)
   - description (CRITICAL: Write detailed, informative descriptions like Perplexity)
   - image_url (stock image URL matching real place)

4. DESCRIPTION REQUIREMENTS (Perplexity-style - Balanced):
   - TARGET: 3-4 sentences (80-120 words) - Balanced length
   - Be informative, engaging, and specific
   - Structure should include:
     a) Opening sentence: What it is and its significance/status
     b) Key features: Specific attractions, landmarks, or notable elements
     c) Activities/experiences: What visitors can do there
     d) Why visit: What makes it special or unique (optional 4th sentence)
   - Use specific details: names of landmarks, types of activities, notable features
   - Write in third-person, objective tone
   - Avoid generic phrases - always be specific
   - Balance: More detailed than a one-liner, but concise enough to read quickly
   
   PERFECT EXAMPLES (Balanced Perplexity-style):
   
   Example 1 - Statue of Liberty:
   "An iconic symbol of freedom and democracy, the Statue of Liberty stands on Liberty Island in New York Harbor. Gifted by France in 1886, this neoclassical sculpture designed by Frédéric Auguste Bartholdi represents Libertas, the Roman goddess of freedom. Visitors can take ferries from Battery Park or Liberty State Park to reach the island, where they can explore the pedestal museum, climb to the crown (with advance reservations), or simply admire the statue from the grounds. The monument offers breathtaking panoramic views of the Manhattan skyline, Ellis Island, and the harbor."
   
   Example 2 - Central Park:
   "A sprawling 843-acre urban oasis in the heart of Manhattan, Central Park is one of the world's most famous public parks. Designed by Frederick Law Olmsted and Calvert Vaux in the 1850s, it features diverse landscapes including meadows, woodlands, lakes, and formal gardens. Visitors can enjoy numerous activities such as rowing on the Central Park Lake, ice skating at Wollman Rink, visiting the Central Park Zoo, or exploring attractions like Bethesda Fountain, Strawberry Fields, and the Great Lawn. The park hosts free concerts, theater performances, and seasonal events throughout the year."
   
   Example 3 - Metropolitan Museum of Art:
   "One of the world's largest and most comprehensive art museums, The Metropolitan Museum of Art houses over 2 million works spanning 5,000 years of world culture. Founded in 1870, the museum's vast collection includes ancient Egyptian artifacts, European paintings, American art, Asian art, Islamic art, and contemporary works. Visitors can explore themed collections including the Temple of Dendur, the American Wing, the Costume Institute, and the Arms and Armor collection. The museum also features special exhibitions, educational programs, and the rooftop garden offering stunning views of Central Park."
   
   BAD EXAMPLES (TOO SHORT):
   - "An iconic symbol of freedom, the Statue of Liberty offers breathtaking views of the New York skyline and a rich history."
   - "A sprawling urban park in the heart of Manhattan, Central Park is perfect for picnics, walks, and outdoor activities."
   
   REMEMBER: Aim for 3-4 sentences that are informative and specific, but not overwhelming.

5. MUST return pure JSON only. No markdown.
`;

  const user = `
Query: "${repairedQuery}"

Return ONLY JSON array of place objects. No wrapper.
`;

  try {
    const resp = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: system },
        { role: "user", content: user }
      ],
      temperature: 0.4,
      max_tokens: 3000, // ✅ Balanced to allow for detailed but concise descriptions
    });

    let content = resp.choices?.[0]?.message?.content || "[]";

    // Clean up markdown code blocks if present
    content = content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();

    console.log(`🔍 Places LLM raw response (first 200 chars):`, content.substring(0, 200));

    // Ensure valid JSON
    try {
      const json = JSON.parse(content);
      if (Array.isArray(json)) {
        // Validate and normalize structure
        const normalized = json.map((item: any) => ({
          name: item.name || item.title || "",
          type: item.type || item.category || "attraction",
          rating: item.rating || item.stars || "4.5",
          location: item.location || item.address || "",
          description: item.description || item.summary || "",
          image_url: item.image_url || item.image || item.photo || "",
          section: item.section || "Top Sights",
          geo: item.geo || null,
          website: item.website || null,
          phone: item.phone || null,
        }));
        console.log(`✅ Parsed ${normalized.length} places successfully`);
        
        // ✅ ENHANCEMENT: Geocode addresses and fetch images for places
        // Process in batches to avoid rate limits
        const enriched = await Promise.all(
          normalized.map(async (place: any, index: number) => {
            // Add small delay to avoid rate limits (stagger requests)
            if (index > 0) {
              await new Promise(resolve => setTimeout(resolve, index * 100)); // 100ms delay between requests
            }
            
            // ✅ FIX: Always geocode if geo is missing or invalid (even if LLM provided fake geo)
            const hasValidGeo = place.geo && 
              typeof place.geo === 'object' &&
              (place.geo.latitude || place.geo.lat) &&
              (place.geo.longitude || place.geo.lng) &&
              place.geo.latitude !== 0 && place.geo.longitude !== 0;
            
            if (!hasValidGeo && place.location) {
              console.log(`📍 [${index + 1}/${normalized.length}] Geocoding: ${place.name}, ${place.location}`);
              try {
                const coords = await geocodeAddress(place.location, place.name);
                if (coords && coords.latitude && coords.longitude) {
                  place.geo = {
                    latitude: coords.latitude,
                    longitude: coords.longitude,
                  };
                  console.log(`✅ Geocoded ${place.name}: ${coords.latitude}, ${coords.longitude}`);
                } else {
                  console.warn(`⚠️ Failed to geocode ${place.name} - coords returned:`, coords);
                }
              } catch (err: any) {
                console.error(`❌ Geocoding error for ${place.name}:`, err.message);
              }
            } else if (hasValidGeo) {
              console.log(`ℹ️ ${place.name} already has valid geo:`, place.geo);
            } else {
              console.warn(`⚠️ ${place.name} has no location to geocode`);
            }
            
            // ✅ FIX: Check if image_url is fake/example URL and replace with real image
            // ✅ ENHANCEMENT: Also fetch website and phone from Google Places API
            const isFakeImageUrl = place.image_url && (
              place.image_url.includes('example.com') ||
              place.image_url.includes('placeholder') ||
              place.image_url.includes('dummy') ||
              !place.image_url.startsWith('http')
            );
            
            // Fetch place details (image, website, phone) if missing OR if it's a fake URL
            if ((!place.image_url || isFakeImageUrl || !place.website || !place.phone) && place.name && place.location) {
              console.log(`🔍 [${index + 1}/${normalized.length}] Fetching place details for: ${place.name}${isFakeImageUrl ? ' (replacing fake URL)' : ''}`);
              try {
                const placeDetails = await getPlaceDetails(place.name, place.location);
                
                // Update image if we got one
                if (placeDetails.image) {
                  place.image_url = placeDetails.image;
                  const preview = placeDetails.image.length > 60 ? placeDetails.image.substring(0, 60) + '...' : placeDetails.image;
                  console.log(`✅ Got image for ${place.name}: ${preview}`);
                } else if (isFakeImageUrl) {
                  // Remove fake URL if we couldn't get a real one
                  place.image_url = '';
                  console.warn(`⚠️ No image found for ${place.name}, removed fake URL`);
                }
                
                // Update website if we got one and don't have it
                if (placeDetails.website && !place.website) {
                  place.website = placeDetails.website;
                  console.log(`✅ Got website for ${place.name}: ${placeDetails.website}`);
                }
                
                // Update phone if we got one and don't have it
                if (placeDetails.phone && !place.phone) {
                  place.phone = placeDetails.phone;
                  console.log(`✅ Got phone for ${place.name}: ${placeDetails.phone}`);
                }
              } catch (err: any) {
                console.error(`❌ Place details fetch error for ${place.name}:`, err.message);
                // Remove fake URL on error
                if (isFakeImageUrl) {
                  place.image_url = '';
                }
              }
            } else if (place.image_url && !isFakeImageUrl) {
              const preview = place.image_url.length > 50 ? place.image_url.substring(0, 50) + '...' : place.image_url;
              console.log(`ℹ️ ${place.name} already has real image: ${preview}`);
            } else {
              console.warn(`⚠️ ${place.name} has no location to fetch place details`);
            }
            
            return place;
          })
        );
        
        return enriched;
      } else {
        console.error("❌ LLM response is not an array:", typeof json);
      }
    } catch (err: any) {
      console.error("❌ Invalid JSON from places search:", err.message);
      console.error("❌ Content that failed to parse:", content.substring(0, 500));
    }

    return [];
  } catch (err: any) {
    console.error("❌ Places LLM Error:", err?.message);
    return [];
  }
}


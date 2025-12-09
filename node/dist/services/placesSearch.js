// src/services/placesSearch.ts
import OpenAI from "openai";
import axios from "axios";
import { repairQuery } from "./queryRepair";
let client = null;
function getClient() {
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
// ✅ PHASE 3: Redis cache for geocoding and place details (with in-memory fallback)
import { getCached, setCached } from './redisCache';
const CACHE_TTL = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
function getCacheKey(placeName, location) {
    return `${placeName.toLowerCase().trim()}|${location.toLowerCase().trim()}`;
}
// Helper to geocode an address using Google Maps Geocoding API
async function geocodeAddress(address, placeName) {
    // ✅ PHASE 3: Check Redis cache first (with in-memory fallback)
    const cacheKey = `geocode:${getCacheKey(placeName, address)}`;
    const cached = await getCached(cacheKey);
    if (cached) {
        console.log(`💾 Cache hit for geocoding: ${placeName}`);
        return cached;
    }
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
            const result = {
                latitude: location.lat,
                longitude: location.lng,
            };
            // ✅ PHASE 3: Cache the result in Redis (with in-memory fallback)
            await setCached(cacheKey, result, CACHE_TTL);
            return result;
        }
        else if (response.data.status === 'REQUEST_DENIED') {
            console.error(`❌ Geocoding API REQUEST_DENIED for "${placeName}": ${response.data.error_message || 'API key not authorized'}`);
            console.error(`   Make sure GOOGLE_MAPS_BACKEND_KEY has Geocoding API enabled in Google Cloud Console`);
        }
        else {
            console.warn(`⚠️ Geocoding failed for "${placeName}": Status ${response.data.status}`);
        }
    }
    catch (error) {
        console.error(`❌ Geocoding error for "${placeName}, ${address}":`, error.message);
    }
    return null;
}
// Helper to get place images, website, and phone from Google Places API
// ✅ PHASE 4: Optimized to only call Details API if website/phone/images is needed
async function getPlaceDetails(placeName, location, needWebsite = false, needPhone = false, needImages = true // ✅ FIX: Always fetch images by default to get all photos
) {
    // ✅ PHASE 3: Check Redis cache first (with in-memory fallback)
    const cacheKey = `place_details:${getCacheKey(placeName, location)}`;
    const cached = await getCached(cacheKey);
    if (cached) {
        console.log(`💾 Cache hit for place details: ${placeName}`);
        return cached;
    }
    const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
    if (!apiKey) {
        console.warn("⚠️ GOOGLE_MAPS_BACKEND_KEY not configured, skipping place details fetch");
        return { image: null, images: [], website: null, phone: null };
    }
    try {
        // First, find the place using Places API Text Search
        const searchQuery = `${placeName}, ${location}`;
        const placesUrl = `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(searchQuery)}&key=${apiKey}`;
        const searchResponse = await axios.get(placesUrl, { timeout: 5000 });
        if (searchResponse.data.status === 'OK' && searchResponse.data.results && searchResponse.data.results.length > 0) {
            const place = searchResponse.data.results[0];
            let imageUrl = null;
            const allImages = [];
            // Try to get photos from search result first (faster)
            if (place.photos && place.photos.length > 0) {
                // Get first photo as primary image
                const firstPhoto = place.photos[0];
                imageUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${firstPhoto.photo_reference}&key=${apiKey}`;
                // Get all photos (up to 10 to avoid too many requests)
                const maxPhotos = Math.min(place.photos.length, 10);
                for (let i = 0; i < maxPhotos; i++) {
                    const photo = place.photos[i];
                    const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${photo.photo_reference}&key=${apiKey}`;
                    allImages.push(photoUrl);
                }
            }
            // ✅ PHASE 4: Call Details API if we need website, phone, or images
            // ✅ FIX: Always call Details API to get all photos (up to 10), not just 1 from Text Search
            let website = null;
            let phone = null;
            if (place.place_id && (needWebsite || needPhone || needImages)) {
                // Request fields we need
                const fields = ['photos']; // ✅ FIX: Always request photos to get all images
                if (needWebsite) {
                    fields.push('website');
                }
                if (needPhone) {
                    fields.push('formatted_phone_number', 'international_phone_number');
                }
                const detailsUrl = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${place.place_id}&fields=${fields.join(',')}&key=${apiKey}`;
                const detailsResponse = await axios.get(detailsUrl, { timeout: 5000 });
                if (detailsResponse.data.status === 'OK' && detailsResponse.data.result) {
                    const details = detailsResponse.data.result;
                    // ✅ FIX: Always get photos from Details API (has more photos than Text Search)
                    if (details.photos && details.photos.length > 0) {
                        // Get first photo as primary image if we don't have one
                        if (!imageUrl) {
                            const firstPhoto = details.photos[0];
                            imageUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${firstPhoto.photo_reference}&key=${apiKey}`;
                        }
                        // ✅ FIX: Get all photos (up to 10) from Details API (more complete than Text Search)
                        allImages.length = 0; // Clear Text Search photos, use Details photos instead
                        const maxPhotos = Math.min(details.photos.length, 10);
                        for (let i = 0; i < maxPhotos; i++) {
                            const photo = details.photos[i];
                            const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=${photo.photo_reference}&key=${apiKey}`;
                            allImages.push(photoUrl);
                        }
                        // If we have imageUrl from first photo, ensure it's first in the array
                        if (imageUrl && !allImages.includes(imageUrl)) {
                            allImages.unshift(imageUrl);
                        }
                    }
                    // Extract website and phone
                    if (needWebsite) {
                        website = details.website || null;
                    }
                    if (needPhone) {
                        phone = details.formatted_phone_number || details.international_phone_number || null;
                    }
                }
            }
            const result = {
                image: imageUrl,
                images: allImages,
                website: website,
                phone: phone,
            };
            // ✅ PHASE 3: Cache the result in Redis (with in-memory fallback)
            await setCached(cacheKey, result, CACHE_TTL);
            return result;
        }
        else if (searchResponse.data.status === 'REQUEST_DENIED') {
            console.error(`❌ Places API REQUEST_DENIED for "${placeName}": ${searchResponse.data.error_message || 'API key not authorized'}`);
            console.error(`   Make sure GOOGLE_MAPS_BACKEND_KEY has Places API enabled in Google Cloud Console`);
        }
    }
    catch (error) {
        // Don't log as error if it's just API not available
        if (error.response?.status !== 403 && error.response?.status !== 401) {
            console.error(`❌ Error fetching place details for "${placeName}":`, error.message);
        }
    }
    return { image: null, images: [], website: null, phone: null };
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
export async function searchPlaces(query) {
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

4. DESCRIPTION REQUIREMENTS (Perplexity-style - Concise):
   - TARGET: 1-2 sentences (40-60 words) - Concise length
   - Be informative, engaging, and specific
   - Structure should include:
     a) Opening sentence: What it is and its significance/status
     b) Key features or activities: One notable feature or what visitors can do there (optional 2nd sentence)
   - Use specific details: names of landmarks, types of activities, notable features
   - Write in third-person, objective tone
   - Avoid generic phrases - always be specific
   - Keep it concise and easy to read quickly
   
   PERFECT EXAMPLES (Concise Perplexity-style):
   
   Example 1 - Statue of Liberty:
   "An iconic symbol of freedom and democracy, the Statue of Liberty stands on Liberty Island in New York Harbor. Visitors can take ferries to reach the island, explore the pedestal museum, or climb to the crown for panoramic views of Manhattan."
   
   Example 2 - Central Park:
   "A sprawling 843-acre urban oasis in the heart of Manhattan, Central Park features diverse landscapes including meadows, woodlands, and lakes. Visitors can enjoy activities such as rowing, ice skating, visiting the zoo, or exploring attractions like Bethesda Fountain and Strawberry Fields."
   
   Example 3 - Metropolitan Museum of Art:
   "One of the world's largest art museums, The Metropolitan Museum of Art houses over 2 million works spanning 5,000 years of world culture. The collection includes ancient Egyptian artifacts, European paintings, American art, and contemporary works, with special exhibitions and a rooftop garden offering views of Central Park."
   
   BAD EXAMPLES (TOO SHORT):
   - "An iconic symbol of freedom, the Statue of Liberty offers breathtaking views."
   - "A sprawling urban park in Manhattan, Central Park is perfect for picnics."
   
   REMEMBER: Aim for 1-2 sentences that are informative and specific, keeping it concise.

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
            max_tokens: 2000, // ✅ Reduced to allow for concise descriptions (1-2 sentences per place)
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
                const normalized = json.map((item) => ({
                    name: item.name || item.title || "",
                    type: item.type || item.category || "attraction",
                    rating: item.rating || item.stars || "4.5",
                    location: item.location || item.address || "",
                    description: item.description || item.summary || "",
                    image_url: item.image_url || item.image || item.photo || "",
                    images: item.images || [], // Array of all images
                    photos: item.photos || [], // Alternative photos array
                    section: item.section || "Top Sights",
                    geo: item.geo || null,
                    website: item.website || null,
                    phone: item.phone || null,
                }));
                console.log(`✅ Parsed ${normalized.length} places successfully`);
                // ✅ PHASE 1: Process all places in parallel (removed artificial delays)
                // ✅ ENHANCEMENT: Geocode addresses and fetch images for places
                const enriched = await Promise.all(normalized.map(async (place, index) => {
                    // ✅ FIX: Always geocode if geo is missing or invalid (even if LLM provided fake geo)
                    const hasValidGeo = place.geo &&
                        typeof place.geo === 'object' &&
                        (place.geo.latitude || place.geo.lat) &&
                        (place.geo.longitude || place.geo.lng) &&
                        place.geo.latitude !== 0 && place.geo.longitude !== 0;
                    // ✅ PHASE 1: Run geocoding and place details in parallel
                    const [geocodeResult, placeDetailsResult] = await Promise.allSettled([
                        // Geocoding task
                        (async () => {
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
                                    }
                                    else {
                                        console.warn(`⚠️ Failed to geocode ${place.name} - coords returned:`, coords);
                                    }
                                }
                                catch (err) {
                                    console.error(`❌ Geocoding error for ${place.name}:`, err.message);
                                }
                            }
                            else if (hasValidGeo) {
                                console.log(`ℹ️ ${place.name} already has valid geo:`, place.geo);
                            }
                            else {
                                console.warn(`⚠️ ${place.name} has no location to geocode`);
                            }
                        })(),
                        // Place details task
                        (async () => {
                            // ✅ FIX: Check if image_url is fake/example URL and replace with real image
                            const isFakeImageUrl = place.image_url && (place.image_url.includes('example.com') ||
                                place.image_url.includes('placeholder') ||
                                place.image_url.includes('dummy') ||
                                !place.image_url.startsWith('http'));
                            // ✅ PHASE 4: Only fetch website/phone if missing
                            const needWebsite = !place.website;
                            const needPhone = !place.phone;
                            // ✅ FIX: Always fetch images (we need multiple photos, not just 1)
                            const needImages = true; // Always fetch to get all photos
                            // Fetch place details (image, images array, website, phone) if missing OR if it's a fake URL
                            if ((!place.image_url || isFakeImageUrl || needWebsite || needPhone || needImages) && place.name && place.location) {
                                console.log(`🔍 [${index + 1}/${normalized.length}] Fetching place details for: ${place.name}${isFakeImageUrl ? ' (replacing fake URL)' : ''}`);
                                try {
                                    // ✅ FIX: Always request images to get all photos (up to 10)
                                    const placeDetails = await getPlaceDetails(place.name, place.location, needWebsite, needPhone, needImages);
                                    // Update image if we got one
                                    if (placeDetails.image) {
                                        place.image_url = placeDetails.image;
                                        const preview = placeDetails.image.length > 60 ? placeDetails.image.substring(0, 60) + '...' : placeDetails.image;
                                        console.log(`✅ Got image for ${place.name}: ${preview}`);
                                    }
                                    else if (isFakeImageUrl) {
                                        // Remove fake URL if we couldn't get a real one
                                        place.image_url = '';
                                        console.warn(`⚠️ No image found for ${place.name}, removed fake URL`);
                                    }
                                    // ✅ NEW: Add all photos to images array
                                    if (placeDetails.images && placeDetails.images.length > 0) {
                                        place.images = placeDetails.images;
                                        console.log(`✅ Got ${placeDetails.images.length} photos for ${place.name}`);
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
                                }
                                catch (err) {
                                    console.error(`❌ Place details fetch error for ${place.name}:`, err.message);
                                    // Remove fake URL on error
                                    if (isFakeImageUrl) {
                                        place.image_url = '';
                                    }
                                }
                            }
                            else if (place.image_url && !isFakeImageUrl) {
                                const preview = place.image_url.length > 50 ? place.image_url.substring(0, 50) + '...' : place.image_url;
                                console.log(`ℹ️ ${place.name} already has real image: ${preview}`);
                            }
                            else {
                                console.warn(`⚠️ ${place.name} has no location to fetch place details`);
                            }
                        })(),
                    ]);
                    return place;
                }));
                return enriched;
            }
            else {
                console.error("❌ LLM response is not an array:", typeof json);
            }
        }
        catch (err) {
            console.error("❌ Invalid JSON from places search:", err.message);
            console.error("❌ Content that failed to parse:", content.substring(0, 500));
        }
        return [];
    }
    catch (err) {
        console.error("❌ Places LLM Error:", err?.message);
        return [];
    }
}

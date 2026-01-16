/**
 * ✅ Agent-Style Place Widget
 * Uses LLM to extract intent and fetches from multiple APIs (Google Maps Places, SerpAPI)
 * Merges all sources with deduplication - no fallback needed
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';
import { search } from '../searchService';
import z from 'zod';

// Intent extraction schema
const placeIntentSchema = z.object({
  placeName: z.string().nullable().describe('Place name or type (e.g., "restaurants", "museums", "coffee shops")'),
  location: z.string().nullable().describe('City or location name (e.g., "Houston, TX")'),
  category: z.string().nullable().optional().describe('Place category: restaurant, cafe, museum, park, attraction, etc.'),
  type: z.string().nullable().optional().describe('Place type: restaurant, cafe, store, museum, park, etc.'),
  rating: z.number().nullable().optional().describe('Minimum rating (e.g., 4.0)'),
  priceRange: z.enum(['$', '$$', '$$$', '$$$$']).nullable().optional().describe('Price range for restaurants'),
});

interface PlaceIntent {
  placeName: string | null;
  location: string | null;
  category?: string | null;
  type?: string | null;
  rating?: number | null;
  priceRange?: '$' | '$$' | '$$$' | '$$$$' | null;
}

// Geocode location using Google Maps Geocoding API
async function geocodeLocation(location: string): Promise<{ lat: number; lng: number } | null> {
  const googleMapsKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!googleMapsKey) {
    console.warn('⚠️ GOOGLE_MAPS_BACKEND_KEY not found - skipping geocoding');
    return null;
  }

  try {
    const axios = (await import('axios')).default;
    const response = await axios.get('https://maps.googleapis.com/maps/api/geocode/json', {
      params: {
        address: location,
        key: googleMapsKey,
      },
      timeout: 5000,
    });

    if (response.data.results && response.data.results.length > 0) {
      const location = response.data.results[0].geometry.location;
      return {
        lat: location.lat,
        lng: location.lng,
      };
    }
    return null;
  } catch (error: any) {
    console.warn('⚠️ Geocoding failed:', error.message);
    return null;
  }
}

// Fetch places from Google Maps Places API (Text Search)
async function fetchFromGoogleMaps(
  location: string,
  intent: PlaceIntent
): Promise<any[]> {
  const googleMapsKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!googleMapsKey) {
    console.warn('⚠️ GOOGLE_MAPS_BACKEND_KEY not found - skipping Google Maps API');
    return [];
  }

  try {
    const axios = (await import('axios')).default;
    
    // Build query: "{placeName} in {location}" or "{type} in {location}"
    let query = '';
    if (intent.placeName) {
      query = `${intent.placeName} in ${location}`;
    } else if (intent.type || intent.category) {
      query = `${intent.type || intent.category} in ${location}`;
    } else {
      query = `places in ${location}`;
    }

    // Determine place type for Google Maps API
    let placeType: string | undefined;
    if (intent.type || intent.category) {
      const typeMap: { [key: string]: string } = {
        'restaurant': 'restaurant',
        'cafe': 'cafe',
        'coffee': 'cafe',
        'museum': 'museum',
        'park': 'park',
        'store': 'store',
        'shopping': 'shopping_mall',
        'attraction': 'tourist_attraction',
        'hotel': 'lodging',
        'bar': 'bar',
        'nightclub': 'night_club',
        'gym': 'gym',
        'hospital': 'hospital',
        'pharmacy': 'pharmacy',
        'gas': 'gas_station',
        'bank': 'bank',
        'atm': 'atm',
      };
      const normalizedType = (intent.type || intent.category || '').toLowerCase();
      placeType = typeMap[normalizedType];
    }

    // Step 1: Text Search to find places
    const textSearchResponse = await axios.get('https://maps.googleapis.com/maps/api/place/textsearch/json', {
      params: {
        query: query,
        key: googleMapsKey,
        type: placeType, // Optional: filter by place type
      },
      timeout: 10000,
    });

    if (!textSearchResponse.data.results || textSearchResponse.data.results.length === 0) {
      return [];
    }

    let places = textSearchResponse.data.results.slice(0, 15); // Limit to 15

    // Filter by rating if specified
    if (intent.rating) {
      places = places.filter((place: any) => place.rating && place.rating >= intent.rating!);
    }

    // Step 2: Get detailed info for each place (photos, reviews, etc.)
    const detailedPlaces = await Promise.all(
      places.map(async (place: any) => {
        try {
          const detailsResponse = await axios.get('https://maps.googleapis.com/maps/api/place/details/json', {
            params: {
              place_id: place.place_id,
              key: googleMapsKey,
              fields: 'name,formatted_address,geometry,rating,user_ratings_total,photos,reviews,website,formatted_phone_number,types,price_level,opening_hours',
            },
            timeout: 5000,
          });

          const details = detailsResponse.data.result;
          
          // Build photos array
          const photos: string[] = [];
          if (details.photos && details.photos.length > 0) {
            // Get first 5 photos
            details.photos.slice(0, 5).forEach((photo: any) => {
              photos.push(`https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsKey}`);
            });
          }

          return {
            name: details.name,
            address: details.formatted_address,
            coordinates: {
              lat: details.geometry.location.lat,
              lng: details.geometry.location.lng,
            },
            rating: details.rating,
            reviewCount: details.user_ratings_total,
            photos: photos,
            thumbnail: photos[0] || undefined,
            link: details.website,
            phone: details.formatted_phone_number,
            place_id: place.place_id,
            types: details.types || [],
            priceLevel: details.price_level, // 0-4 for restaurants
            openingHours: details.opening_hours?.weekday_text,
            source: 'google_maps',
          };
        } catch (error: any) {
          console.warn(`⚠️ Failed to get details for place ${place.place_id}:`, error.message);
          // Return basic info if details fail
          return {
            name: place.name,
            address: place.formatted_address,
            coordinates: {
              lat: place.geometry.location.lat,
              lng: place.geometry.location.lng,
            },
            rating: place.rating,
            reviewCount: place.user_ratings_total,
            photos: place.photos ? place.photos.slice(0, 5).map((p: any) => 
              `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${p.photo_reference}&key=${googleMapsKey}`
            ) : [],
            thumbnail: place.photos?.[0] ? 
              `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${place.photos[0].photo_reference}&key=${googleMapsKey}` : undefined,
            link: undefined,
            place_id: place.place_id,
            types: place.types || [],
            source: 'google_maps',
          };
        }
      })
    );

    return detailedPlaces;
  } catch (error: any) {
    console.warn('⚠️ Google Maps API failed:', error.message);
    return [];
  }
}

// Fetch places from SerpAPI
async function fetchFromSerpAPI(
  location: string,
  intent: PlaceIntent
): Promise<any[]> {
  try {
    // Build search query
    let query = '';
    if (intent.placeName) {
      query = `${intent.placeName} in ${location}`;
    } else if (intent.type || intent.category) {
      query = `${intent.type || intent.category} in ${location}`;
    } else {
      query = `places in ${location}`;
    }

    // Use the search service to get SerpAPI results
    const searchResult = await search(query.trim(), [], {
      maxResults: 15,
      searchType: 'web',
    });

    // Extract place data from SerpAPI rawResponse
    const placeResults = searchResult.rawResponse?.places_results || 
                        searchResult.rawResponse?.local_results ||
                        searchResult.rawResponse?.organic_results?.filter((r: any) => 
                          r.type === 'place' || r.type === 'local' || r.gps_coordinates
                        ) || [];

    // Transform to consistent format
    return placeResults.map((place: any) => ({
      name: place.title || place.name,
      address: place.address || (place.address_lines ? (Array.isArray(place.address_lines) ? place.address_lines.join(', ') : place.address_lines) : undefined),
      coordinates: place.gps_coordinates ? {
        lat: place.gps_coordinates.latitude,
        lng: place.gps_coordinates.longitude,
      } : place.coordinates ? {
        lat: place.coordinates.latitude || place.coordinates.lat,
        lng: place.coordinates.longitude || place.coordinates.lng,
      } : undefined,
      rating: place.rating ? parseFloat(place.rating.toString()) : undefined,
      reviewCount: place.reviews ? parseInt(place.reviews.toString()) : undefined,
      photos: place.images || (place.thumbnail ? [place.thumbnail] : []),
      thumbnail: place.thumbnail || place.image,
      link: place.website || place.gmaps_link || place.url,
      phone: place.phone || place.phone_number,
      description: place.description || place.snippet,
      type: place.type || place.category,
      place_id: place.place_id,
      source: 'serpapi',
    }));
  } catch (error: any) {
    console.warn('⚠️ SerpAPI search failed:', error.message);
    return [];
  }
}

// Decide which data sources to use based on intent
function decideDataSources(intent: PlaceIntent): {
  useGoogleMaps: boolean;
  useSerpAPI: boolean;
} {
  return {
    useGoogleMaps: !!intent.location, // Always use if location provided
    useSerpAPI: true, // Always use SerpAPI as one of the sources
  };
}

// Merge place data from multiple sources, deduplicating by name + location
function mergePlaceData(
  googleMapsData: any[],
  serpAPIData: any[]
): any[] {
  const merged: any[] = [];
  const seen = new Set<string>();
  
  // Helper to generate unique key for deduplication
  const getKey = (place: any): string => {
    const name = (place.name || place.title || '').toLowerCase().trim();
    const address = (place.address || place.formatted_address || '').toLowerCase().trim();
    return `${name}::${address}`;
  };
  
  // Priority 1: Google Maps data (most authoritative - coordinates, photos, reviews)
  googleMapsData.forEach(place => {
    const key = getKey(place);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push({
        ...place,
        source: place.source || 'google_maps',
      });
    }
  });
  
  // Priority 2: SerpAPI data (supplement with additional info)
  serpAPIData.forEach(place => {
    const key = getKey(place);
    if (seen.has(key)) {
      // Merge with existing place
      const existing = merged.find(p => getKey(p) === key);
      if (existing) {
        // Only add missing fields (don't overwrite authoritative sources)
        if (!existing.description && place.description) existing.description = place.description;
        if (!existing.thumbnail && place.thumbnail) existing.thumbnail = place.thumbnail;
        if (!existing.link && place.link) existing.link = place.link;
        if (!existing.phone && place.phone) existing.phone = place.phone;
        if (!existing.type && place.type) existing.type = place.type;
        existing.source = existing.source ? `${existing.source}+serpapi` : 'serpapi';
      }
    } else {
      seen.add(key);
      merged.push({
        ...place,
        source: place.source || 'serpapi',
      });
    }
  });
  
  return merged;
}

// Separate evidence (factual) from commerce (booking/reservation) data
function formatPlaceCards(places: any[]): any[] {
  return places.map(place => ({
    // Evidence (factual, non-commercial)
    id: place.place_id || place.id || (place.coordinates ? `${place.coordinates.lat}-${place.coordinates.lng}` : `place-${Math.random()}`),
    name: place.name || place.title || 'Unknown Place',
    address: place.address || place.formatted_address,
    coordinates: place.coordinates ? {
      lat: place.coordinates.lat || place.coordinates.latitude,
      lng: place.coordinates.lng || place.coordinates.longitude,
    } : undefined,
    rating: place.rating ? parseFloat(place.rating.toString()) : undefined,
    reviews: place.reviewCount || place.reviews,
    photos: place.photos || place.images || (place.thumbnail ? [place.thumbnail] : []),
    thumbnail: place.thumbnail || place.image || (place.photos?.[0] || ''),
    description: place.description || place.snippet,
    type: place.type || place.category || (place.types?.[0] || undefined),
    phone: place.phone || place.formatted_phone_number,
    openingHours: place.openingHours,
    
    // Commerce (booking/reservation-related)
    link: place.link || place.website,
    bookingLinks: {
      googleMaps: place.place_id ? `https://www.google.com/maps/place/?q=place_id:${place.place_id}` : undefined,
      website: place.website || place.link,
      reservation: place.reservation_link,
    },
    priceLevel: place.priceLevel, // For restaurants: 0-4
  }));
}

const placeWidget: WidgetInterface = {
  type: 'place',

  shouldExecute(classification?: any): boolean {
    // ✅ Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showPlaceWidget) {
      return true;
    }
    
    // Check if place widget should execute based on classification
    if (classification?.widgetTypes?.includes('place')) {
      return true;
    }
    
    // Fallback: check intent/domains
    const detectedDomains = classification?.detectedDomains || [];
    const intent = classification?.intent || '';
    return detectedDomains.includes('place') || intent === 'place';
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget, classification, rawResponse, followUp, llm } = input;
    
    // ✅ CRITICAL: LLM is required for agent-style widget (intent extraction)
    if (!llm) {
      return {
        type: 'place',
        data: [],
        success: false,
        error: 'LLM required for agent-style place widget (intent extraction)',
      };
    }

    try {
      // Step 1: Extract structured intent using LLM
      const query = followUp || classification?.query || classification?.queryRefinement || widget?.params?.query || '';
      
      if (!query) {
        return {
          type: 'place',
          data: [],
          success: false,
          error: 'No query provided for intent extraction',
        };
      }

      console.log('🔍 Extracting place intent from query:', query);
      
      // Use generateObject if available, otherwise fall back to generateText + JSON parsing
      let intentOutput: { object: PlaceIntent };
      
      if (typeof llm.generateObject === 'function') {
        intentOutput = await llm.generateObject({
          messages: [
            {
              role: 'system',
              content: 'Extract place search intent from user query. Return ONLY valid JSON with structured data containing placeName, location, category, type, rating, and priceRange. If information is not provided, use null.',
            },
            {
              role: 'user',
              content: query,
            },
          ],
          schema: placeIntentSchema,
        });
      } else {
        // Fallback: use generateText and parse JSON
        const response = await llm.generateText({
          messages: [
            {
              role: 'system',
              content: 'Extract place search intent from user query. Return ONLY valid JSON matching this schema: { placeName: string | null, location: string | null, category?: string | null, type?: string | null, rating?: number | null, priceRange?: "$" | "$$" | "$$$" | "$$$$" | null }. If information is not provided, use null.',
            },
            {
              role: 'user',
              content: query,
            },
          ],
        });
        
        const text = typeof response === 'string' ? response : response.text || '';
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          intentOutput = { object: JSON.parse(jsonMatch[0]) };
        } else {
          throw new Error('Could not parse intent from LLM response');
        }
      }

      const intent: PlaceIntent = intentOutput.object;
      
      // ✅ Normalize null values (no arrays in place intent, scalars can stay null)
      // No arrays to normalize in place intent
      
      console.log('✅ Extracted place intent:', intent);

      // Step 2: Validate location
      if (!intent.location) {
        return {
          type: 'place',
          data: [],
          success: false,
          error: 'Could not extract location from query',
        };
      }

      // Step 3: Geocode location (optional - for better accuracy)
      let coordinates: { lat: number; lng: number } | null = null;
      try {
        coordinates = await geocodeLocation(intent.location);
      } catch (error: any) {
        console.warn('⚠️ Geocoding failed:', error.message);
        // Continue without coordinates
      }

      // Step 4: Decide which data sources to use
      const sources = decideDataSources(intent);
      console.log('📊 Data sources decision:', sources);

      // Step 5: Fetch from ALL sources in parallel (no fallback - all are data sources)
      const fetchPromises: Promise<any[]>[] = [];
      
      if (sources.useGoogleMaps) {
        fetchPromises.push(
          fetchFromGoogleMaps(intent.location, intent)
            .catch(error => {
              console.warn('⚠️ Google Maps API failed:', error.message);
              return []; // Return empty array, continue with other sources
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      if (sources.useSerpAPI) {
        fetchPromises.push(
          fetchFromSerpAPI(intent.location, intent)
            .catch(error => {
              console.warn('⚠️ SerpAPI failed:', error.message);
              return []; // Return empty array, continue with other sources
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      const [googleMapsData, serpAPIData] = await Promise.all(fetchPromises);

      // Step 6: Merge data from all sources
      const mergedPlaces = mergePlaceData(googleMapsData, serpAPIData);
      console.log(`✅ Merged ${mergedPlaces.length} places from ${googleMapsData.length} Google Maps, ${serpAPIData.length} SerpAPI`);

      // Step 7: Format place cards with evidence/commerce separation
      const placeCards = formatPlaceCards(mergedPlaces);

      if (placeCards.length === 0) {
        return {
          type: 'place',
          data: [],
          success: false,
          error: 'No places found from any data source (Google Maps, SerpAPI)',
        };
      }

      return {
        type: 'place',
        data: placeCards,
        success: true,
        llmContext: `Found ${placeCards.length} places${intent.placeName ? ` matching "${intent.placeName}"` : ''}${intent.type ? ` of type ${intent.type}` : ''} in ${intent.location} from multiple sources`,
      };
    } catch (error: any) {
      console.error('❌ Agent-style place widget error:', error);
      
      // No fallback - return error (all sources are already included in the widget)
      return {
        type: 'place',
        data: [],
        success: false,
        error: error.message || 'Failed to fetch place data from all sources',
      };
    }
  },
};

export default placeWidget;

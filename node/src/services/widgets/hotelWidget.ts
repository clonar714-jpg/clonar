/**
 * ✅ Agent-Style Hotel Widget
 * Uses LLM to extract intent and fetches from multiple APIs (Google Maps, Booking.com, SerpAPI)
 * Merges all sources with deduplication - no fallback needed
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';
import { search } from '../searchService';
import axios from 'axios';
import z from 'zod';

// Intent extraction schema
const hotelIntentSchema = z.object({
  location: z.string().nullable().describe('City or location name (e.g., "Houston, TX")'),
  checkIn: z.string().nullable().optional().describe('Check-in date in YYYY-MM-DD format'),
  checkOut: z.string().nullable().optional().describe('Check-out date in YYYY-MM-DD format'),
  guests: z.number().nullable().optional().describe('Number of guests'),
  priceRange: z.object({
    min: z.number().nullable().optional(),
    max: z.number().nullable().optional(),
  }).nullable().optional().describe('Price range per night'),
  hotelType: z.string().nullable().optional().describe('Hotel type: luxury, budget, boutique, resort, etc.'),
  amenities: z.array(z.string()).nullable().optional().describe('Desired amenities: pool, gym, wifi, parking, etc.'),
});

interface HotelIntent {
  location: string | null;
  checkIn?: string | null;
  checkOut?: string | null;
  guests?: number | null;
  priceRange?: { min?: number | null; max?: number | null } | null;
  hotelType?: string | null;
  amenities?: string[] | null;
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

// Fetch hotels from Google Maps Places API (Text Search)
async function fetchFromGoogleMaps(
  location: string,
  intent: HotelIntent
): Promise<any[]> {
  const googleMapsKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!googleMapsKey) {
    console.warn('⚠️ GOOGLE_MAPS_BACKEND_KEY not found - skipping Google Maps API');
    return [];
  }

  try {
    const axios = (await import('axios')).default;
    
    // Build query: "hotels in {location}" with optional filters
    let query = `hotels in ${location}`;
    if (intent.hotelType) {
      query = `${intent.hotelType} ${query}`;
    }

    // Step 1: Text Search to find hotels
    const textSearchResponse = await axios.get('https://maps.googleapis.com/maps/api/place/textsearch/json', {
      params: {
        query: query,
        key: googleMapsKey,
        type: 'lodging', // Hotels only
      },
      timeout: 10000,
    });

    if (!textSearchResponse.data.results || textSearchResponse.data.results.length === 0) {
      return [];
    }

    const places = textSearchResponse.data.results.slice(0, 10); // Limit to 10

    // Step 2: Get detailed info for each place (photos, reviews, etc.)
    const detailedPlaces = await Promise.all(
      places.map(async (place: any) => {
        try {
          const detailsResponse = await axios.get('https://maps.googleapis.com/maps/api/place/details/json', {
            params: {
              place_id: place.place_id,
              key: googleMapsKey,
              fields: 'name,formatted_address,geometry,rating,user_ratings_total,photos,reviews,website,formatted_phone_number,types',
            },
            timeout: 10000, // Increased from 5000 to 10000 for better reliability
          });

          const details = detailsResponse.data.result;
          
          // Build photos array
          const photos: string[] = [];
          if (details.photos && details.photos.length > 0) {
            // Get first 5 photos
            details.photos.slice(0, 5).forEach((photo: any) => {
              if (photo.photo_reference) {
                photos.push(`https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsKey}`);
              }
            });
          }
          
          // Debug logging
          if (photos.length === 0 && details.photos) {
            console.warn(`⚠️ Hotel ${details.name} has photos field but no photo_reference found`);
          } else if (photos.length > 0) {
            console.log(`✅ Extracted ${photos.length} photos for ${details.name}`);
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
            source: 'google_maps',
          };
        } catch (error: any) {
          console.warn(`⚠️ Failed to get details for place ${place.place_id}:`, error.message);
          // Return basic info if details fail
          // Note: Text Search results may not always have photos in the same format
          const fallbackPhotos: string[] = [];
          if (place.photos && Array.isArray(place.photos)) {
            place.photos.slice(0, 5).forEach((p: any) => {
              if (p && p.photo_reference) {
                fallbackPhotos.push(`https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${p.photo_reference}&key=${googleMapsKey}`);
              }
            });
          }
          
          if (fallbackPhotos.length === 0) {
            console.warn(`⚠️ No photos available for ${place.name} (fallback from Text Search)`);
          }
          
          return {
            name: place.name,
            address: place.formatted_address,
            coordinates: {
              lat: place.geometry.location.lat,
              lng: place.geometry.location.lng,
            },
            rating: place.rating,
            reviewCount: place.user_ratings_total,
            photos: fallbackPhotos,
            thumbnail: fallbackPhotos[0] || undefined,
            link: undefined,
            place_id: place.place_id,
            source: 'google_maps',
          };
        }
      })
    );

    const placesWithPhotos = detailedPlaces.filter(p => p.photos && p.photos.length > 0);
    console.log(`✅ Google Maps: Found ${detailedPlaces.length} hotels, ${placesWithPhotos.length} with photos`);
    
    return detailedPlaces;
  } catch (error: any) {
    console.warn('⚠️ Google Maps API failed:', error.message);
    return [];
  }
}

// Fetch hotels from Booking.com API (requires dates)
async function fetchFromBookingCom(
  intent: HotelIntent
): Promise<any[]> {
  // TODO: Implement Booking.com API call
  // - Requires checkIn, checkOut, guests
  // - Returns real-time prices and availability
  // - Note: Booking.com API requires partnership/affiliate program
  console.warn('⚠️ Booking.com API not implemented - will use other sources');
  return [];
}

// Fetch hotels from SerpAPI using google_hotels engine
async function fetchFromSerpAPI(
  location: string,
  intent: HotelIntent
): Promise<any[]> {
  try {
    const serpKey = process.env.SERPAPI_KEY;
    if (!serpKey) {
      console.warn('⚠️ SERPAPI_KEY not found - skipping SerpAPI hotel search');
      return [];
    }

    // Build search query
    let query = `hotels in ${location}`;
    if (intent.hotelType) {
      query = `${intent.hotelType} ${query}`;
    }

    // Prepare SerpAPI parameters for google_hotels engine
    const params: any = {
      engine: 'google_hotels',
      q: query,
      api_key: serpKey,
      hl: 'en',
      gl: 'us',
      num: 20, // Get more results for better selection
    };

    // Add dates if provided
    if (intent.checkIn && intent.checkOut) {
      params.check_in_date = intent.checkIn;
      params.check_out_date = intent.checkOut;
    } else {
      // Default to 7 days from now, 1 night stay
      const today = new Date();
      const checkIn = new Date(today);
      checkIn.setDate(today.getDate() + 7);
      const checkOut = new Date(checkIn);
      checkOut.setDate(checkIn.getDate() + 1);
      params.check_in_date = checkIn.toISOString().split('T')[0];
      params.check_out_date = checkOut.toISOString().split('T')[0];
    }

    // Add guests if provided
    if (intent.guests) {
      params.adults = intent.guests.toString();
    } else {
      params.adults = '2'; // Default
    }

    params.currency = 'USD';

    // Make direct API call to SerpAPI google_hotels engine
    const response = await axios.get('https://serpapi.com/search.json', {
      params,
      timeout: 10000,
    });

    // Extract hotel data from properties array (google_hotels engine returns this)
    const hotelResults = response.data.properties || [];

    if (hotelResults.length === 0) {
      console.warn('⚠️ SerpAPI returned no hotel results');
      return [];
    }

    // Transform to consistent format
    return hotelResults.map((hotel: any) => {
      // Extract images properly from SerpAPI hotel response
      const images: string[] = [];
      if (hotel.images && Array.isArray(hotel.images)) {
        hotel.images.forEach((img: any) => {
          if (typeof img === 'string') {
            images.push(img);
          } else if (img && img.thumbnail) {
            images.push(img.thumbnail);
          }
        });
      }
      
      // Get thumbnail (first image or dedicated thumbnail field)
      const thumbnail = hotel.thumbnail || 
                       (images.length > 0 ? images[0] : undefined) ||
                       hotel.image ||
                       hotel.photo;

      // Extract price from rate_per_night object if available
      let price: string | undefined;
      if (hotel.rate_per_night) {
        if (typeof hotel.rate_per_night === 'object') {
          price = hotel.rate_per_night.lowest || hotel.rate_per_night.extracted || hotel.rate_per_night;
        } else {
          price = hotel.rate_per_night.toString();
        }
      } else if (hotel.price) {
        price = typeof hotel.price === 'object' ? hotel.price.lowest : hotel.price.toString();
      }

      return {
        name: hotel.name || hotel.title,
        address: hotel.address || hotel.location || hotel.address_lines?.join(', '),
        coordinates: hotel.gps_coordinates ? {
          lat: hotel.gps_coordinates.latitude,
          lng: hotel.gps_coordinates.longitude,
        } : hotel.coordinates ? {
          lat: hotel.coordinates.latitude || hotel.coordinates.lat,
          lng: hotel.coordinates.longitude || hotel.coordinates.lng,
        } : undefined,
        rating: hotel.overall_rating ? parseFloat(hotel.overall_rating.toString()) : 
                hotel.rating ? parseFloat(hotel.rating.toString()) : undefined,
        reviewCount: hotel.reviews ? parseInt(hotel.reviews.toString()) : undefined,
        photos: images.length > 0 ? images : (thumbnail ? [thumbnail] : []),
        thumbnail: thumbnail,
        link: hotel.link || hotel.website,
        price: price,
        description: hotel.description || hotel.snippet,
        source: 'serpapi',
      };
    });
  } catch (error: any) {
    console.warn('⚠️ SerpAPI hotel search failed:', error.message);
    return [];
  }
}

// Decide which data sources to use based on intent
function decideDataSources(intent: HotelIntent): {
  useGoogleMaps: boolean;
  useBookingCom: boolean;
  useSerpAPI: boolean;
} {
  const hasDates = !!(intent.checkIn && intent.checkOut);
  
  return {
    useGoogleMaps: !!intent.location, // Always use if location provided
    useBookingCom: hasDates, // Only if dates provided
    useSerpAPI: true, // Always use SerpAPI as one of the sources
  };
}

// Merge hotel data from multiple sources, deduplicating by name + location
function mergeHotelData(
  googleMapsData: any[],
  bookingData: any[],
  serpAPIData: any[]
): any[] {
  const merged: any[] = [];
  const seen = new Set<string>();
  
  // Helper to generate unique key for deduplication
  const getKey = (hotel: any): string => {
    const name = (hotel.name || hotel.title || '').toLowerCase().trim();
    const address = (hotel.address || hotel.location || '').toLowerCase().trim();
    return `${name}::${address}`;
  };
  
  // Priority 1: Google Maps data (most authoritative - coordinates, photos, reviews)
  googleMapsData.forEach(hotel => {
    const key = getKey(hotel);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push({
        ...hotel,
        source: hotel.source || 'google_maps',
      });
    }
  });
  
  // Priority 2: Booking.com data (real-time prices, availability)
  bookingData.forEach(hotel => {
    const key = getKey(hotel);
    if (seen.has(key)) {
      // Merge with existing hotel
      const existing = merged.find(h => getKey(h) === key);
      if (existing) {
        existing.bookingComLink = hotel.bookingLink;
        existing.prices = hotel.prices;
        existing.availability = hotel.availability;
        existing.source = existing.source ? `${existing.source}+booking` : 'booking';
      }
    } else {
      seen.add(key);
      merged.push({
        ...hotel,
        source: hotel.source || 'booking',
      });
    }
  });
  
  // Priority 3: SerpAPI data (supplement with additional info)
  serpAPIData.forEach(hotel => {
    const key = getKey(hotel);
    if (seen.has(key)) {
      // Merge with existing hotel
      const existing = merged.find(h => getKey(h) === key);
      if (existing) {
        // Only add missing fields (don't overwrite authoritative sources)
        if (!existing.description && hotel.description) existing.description = hotel.description;
        if (!existing.thumbnail && hotel.thumbnail) existing.thumbnail = hotel.thumbnail;
        if (!existing.link && hotel.link) existing.link = hotel.link;
        if (!existing.price && hotel.price) existing.price = hotel.price;
        existing.source = existing.source ? `${existing.source}+serpapi` : 'serpapi';
      }
    } else {
      seen.add(key);
      merged.push({
        ...hotel,
        source: hotel.source || 'serpapi',
      });
    }
  });
  
  return merged;
}

// Separate evidence (factual) from commerce (booking) data
function formatHotelCards(hotels: any[]): any[] {
  return hotels.map(hotel => ({
    // Evidence (factual, non-commercial)
    id: hotel.place_id || hotel.hotel_id || hotel.property_id || hotel.id || hotel.link,
    name: hotel.name || hotel.title || 'Unknown Hotel',
    address: hotel.address || hotel.location || hotel.address_lines?.join(', '),
    coordinates: hotel.gps_coordinates ? {
      lat: hotel.gps_coordinates.latitude,
      lng: hotel.gps_coordinates.longitude,
    } : hotel.coordinates ? {
      lat: hotel.coordinates.latitude || hotel.coordinates.lat,
      lng: hotel.coordinates.longitude || hotel.coordinates.lng,
    } : undefined,
    rating: hotel.rating ? parseFloat(hotel.rating.toString()) : undefined,
    reviews: hotel.reviews ? parseInt(hotel.reviews.toString()) : undefined,
    photos: hotel.photos || hotel.images || (hotel.thumbnail ? [hotel.thumbnail] : []),
    amenities: hotel.amenities || [],
    description: hotel.description || hotel.snippet,
    thumbnail: hotel.thumbnail || hotel.image || hotel.photo || '',
    
    // Commerce (booking-related)
    link: hotel.link || hotel.website,
    bookingLinks: {
      bookingCom: hotel.bookingComLink || hotel.booking_link,
      expedia: hotel.expediaLink,
      direct: hotel.directLink || hotel.website,
    },
    prices: hotel.prices || (hotel.price || hotel.rate || hotel.rate_per_night ? {
      bookingCom: hotel.price || hotel.rate || hotel.rate_per_night,
      currency: hotel.currency || 'USD',
    } : undefined),
    availability: hotel.availability,
  }));
}

const hotelWidget: WidgetInterface = {
  type: 'hotel',

  shouldExecute(classification?: any): boolean {
    // ✅ Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showHotelWidget) {
      return true;
    }
    
    // Check if hotel widget should execute based on classification
    if (classification?.widgetTypes?.includes('hotel')) {
      return true;
    }
    
    // Fallback: check intent/domains
    const detectedDomains = classification?.detectedDomains || [];
    const intent = classification?.intent || '';
    return detectedDomains.includes('hotel') || intent === 'hotel';
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget, classification, rawResponse, followUp, llm } = input;
    
    // ✅ CRITICAL: LLM is required for agent-style widget (intent extraction)
    if (!llm) {
      return {
        type: 'hotel',
        data: [],
        success: false,
        error: 'LLM required for agent-style hotel widget (intent extraction)',
      };
    }

    try {
      // Step 1: Extract structured intent using LLM
      const query = followUp || classification?.query || classification?.queryRefinement || '';
      
      if (!query) {
        return {
          type: 'hotel',
          data: [],
          success: false,
          error: 'No query provided for intent extraction',
        };
      }

      console.log('🔍 Extracting hotel intent from query:', query);
      
      // Use generateObject if available, otherwise fall back to generateText + JSON parsing
      let intentOutput: { object: HotelIntent };
      
      if (typeof llm.generateObject === 'function') {
        intentOutput = await llm.generateObject({
          messages: [
            {
              role: 'system',
              content: 'Extract hotel booking intent from user query. Return ONLY valid JSON with structured data containing location, dates, guests, price range, hotel type, and amenities. If information is not provided, use null.',
            },
            {
              role: 'user',
              content: query,
            },
          ],
          schema: hotelIntentSchema,
        });
      } else {
        // Fallback: use generateText and parse JSON
        const response = await llm.generateText({
          messages: [
            {
              role: 'system',
              content: 'Extract hotel booking intent from user query. Return ONLY valid JSON matching this schema: { location: string | null, checkIn?: string | null, checkOut?: string | null, guests?: number | null, priceRange?: { min?: number, max?: number } | null, hotelType?: string | null, amenities?: string[] }. If information is not provided, use null.',
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

      const intent: HotelIntent = intentOutput.object;
      
      // ✅ Normalize null arrays to empty arrays for easier handling
      if (intent.amenities === null) {
        intent.amenities = [];
      }
      
      console.log('✅ Extracted hotel intent:', intent);

      // Step 2: Validate location
      if (!intent.location) {
        return {
          type: 'hotel',
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
      
      if (sources.useBookingCom && intent.checkIn && intent.checkOut) {
        fetchPromises.push(
          fetchFromBookingCom(intent)
            .catch(error => {
              console.warn('⚠️ Booking.com API failed:', error.message);
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

      const [googleMapsData, bookingData, serpAPIData] = await Promise.all(fetchPromises);

      // Step 6: Merge data from all sources
      const mergedHotels = mergeHotelData(googleMapsData, bookingData, serpAPIData);
      console.log(`✅ Merged ${mergedHotels.length} hotels from ${googleMapsData.length} Google Maps, ${bookingData.length} Booking.com, ${serpAPIData.length} SerpAPI`);

      // Step 8: Format hotel cards with evidence/commerce separation
      const hotelCards = formatHotelCards(mergedHotels);

      if (hotelCards.length === 0) {
        return {
          type: 'hotel',
          data: [],
          success: false,
          error: 'No hotels found from any data source (Google Maps, Booking.com, SerpAPI)',
        };
      }

      return {
        type: 'hotel',
        data: hotelCards,
        success: true,
        llmContext: `Found ${hotelCards.length} hotels in ${intent.location}${intent.checkIn && intent.checkOut ? ` for ${intent.checkIn} to ${intent.checkOut}` : ''} from multiple sources`,
      };
    } catch (error: any) {
      console.error('❌ Agent-style hotel widget error:', error);
      
      // No fallback - return error (all sources are already included in the widget)
      return {
        type: 'hotel',
        data: [],
        success: false,
        error: error.message || 'Failed to fetch hotel data from all sources',
      };
    }
  },
};

export default hotelWidget;


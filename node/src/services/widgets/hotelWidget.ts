

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';
import { search } from '../searchService';
import axios from 'axios';
import z from 'zod';


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
    
   
    let query = `hotels in ${location}`;
    if (intent.hotelType) {
      query = `${intent.hotelType} ${query}`;
    }

    
    const textSearchResponse = await axios.get('https://maps.googleapis.com/maps/api/place/textsearch/json', {
      params: {
        query: query,
        key: googleMapsKey,
        type: 'lodging', 
      },
      timeout: 10000,
    });

    if (!textSearchResponse.data.results || textSearchResponse.data.results.length === 0) {
      return [];
    }

    const places = textSearchResponse.data.results.slice(0, 10); 

    
    const detailedPlaces = await Promise.all(
      places.map(async (place: any) => {
        try {
          const detailsResponse = await axios.get('https://maps.googleapis.com/maps/api/place/details/json', {
            params: {
              place_id: place.place_id,
              key: googleMapsKey,
              fields: 'name,formatted_address,geometry,rating,user_ratings_total,photos,reviews,website,formatted_phone_number,types',
            },
            timeout: 10000, 
          });

          const details = detailsResponse.data.result;
          
          
          const photos: string[] = [];
          if (details.photos && details.photos.length > 0) {
            
            details.photos.slice(0, 5).forEach((photo: any) => {
              if (photo.photo_reference) {
                photos.push(`https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsKey}`);
              }
            });
          }
          
          
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


async function fetchFromBookingCom(
  intent: HotelIntent
): Promise<any[]> {
  
  console.warn('⚠️ Booking.com API not implemented - will use other sources');
  return [];
}


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

    
    let query = `hotels in ${location}`;
    if (intent.hotelType) {
      query = `${intent.hotelType} ${query}`;
    }

    
    const params: any = {
      engine: 'google_hotels',
      q: query,
      api_key: serpKey,
      hl: 'en',
      gl: 'us',
      num: 20, 
    };

    
    if (intent.checkIn && intent.checkOut) {
      params.check_in_date = intent.checkIn;
      params.check_out_date = intent.checkOut;
    } else {
      
      const today = new Date();
      const checkIn = new Date(today);
      checkIn.setDate(today.getDate() + 7);
      const checkOut = new Date(checkIn);
      checkOut.setDate(checkIn.getDate() + 1);
      params.check_in_date = checkIn.toISOString().split('T')[0];
      params.check_out_date = checkOut.toISOString().split('T')[0];
    }

   
    if (intent.guests) {
      params.adults = intent.guests.toString();
    } else {
      params.adults = '2'; 
    }

    params.currency = 'USD';

    
    const response = await axios.get('https://serpapi.com/search.json', {
      params,
      timeout: 10000,
    });

    
    const hotelResults = response.data.properties || [];

    if (hotelResults.length === 0) {
      console.warn('⚠️ SerpAPI returned no hotel results');
      return [];
    }

    
    return hotelResults.map((hotel: any) => {
      
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
      
      
      const thumbnail = hotel.thumbnail || 
                       (images.length > 0 ? images[0] : undefined) ||
                       hotel.image ||
                       hotel.photo;

      
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


function decideDataSources(intent: HotelIntent): {
  useGoogleMaps: boolean;
  useBookingCom: boolean;
  useSerpAPI: boolean;
} {
  const hasDates = !!(intent.checkIn && intent.checkOut);
  
  return {
    useGoogleMaps: !!intent.location, 
    useBookingCom: hasDates, 
    useSerpAPI: true, 
  };
}


function mergeHotelData(
  googleMapsData: any[],
  bookingData: any[],
  serpAPIData: any[]
): any[] {
  const merged: any[] = [];
  const seen = new Set<string>();
  
  
  const getKey = (hotel: any): string => {
    const name = (hotel.name || hotel.title || '').toLowerCase().trim();
    const address = (hotel.address || hotel.location || '').toLowerCase().trim();
    return `${name}::${address}`;
  };
  
  
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
  
  
  bookingData.forEach(hotel => {
    const key = getKey(hotel);
    if (seen.has(key)) {
      
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
  
  
  serpAPIData.forEach(hotel => {
    const key = getKey(hotel);
    if (seen.has(key)) {
      
      const existing = merged.find(h => getKey(h) === key);
      if (existing) {
        
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


function formatHotelCards(hotels: any[]): any[] {
  return hotels.map(hotel => ({
   
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
   
    if (classification?.classification?.showHotelWidget) {
      return true;
    }
    
    
    if (classification?.widgetTypes?.includes('hotel')) {
      return true;
    }
    
    
    const detectedDomains = classification?.detectedDomains || [];
    const intent = classification?.intent || '';
    return detectedDomains.includes('hotel') || intent === 'hotel';
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget, classification, rawResponse, followUp, llm } = input;
    
    
    if (!llm) {
      return {
        type: 'hotel',
        data: [],
        success: false,
        error: 'LLM required for agent-style hotel widget (intent extraction)',
      };
    }

    try {
      
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
      
      
      if (intent.amenities === null) {
        intent.amenities = [];
      }
      
      console.log('✅ Extracted hotel intent:', intent);

     
      if (!intent.location) {
        return {
          type: 'hotel',
          data: [],
          success: false,
          error: 'Could not extract location from query',
        };
      }

      
      let coordinates: { lat: number; lng: number } | null = null;
      try {
        coordinates = await geocodeLocation(intent.location);
      } catch (error: any) {
        console.warn('⚠️ Geocoding failed:', error.message);
       
      }

      
      const sources = decideDataSources(intent);
      console.log('📊 Data sources decision:', sources);

      
      const fetchPromises: Promise<any[]>[] = [];
      
      if (sources.useGoogleMaps) {
        fetchPromises.push(
          fetchFromGoogleMaps(intent.location, intent)
            .catch(error => {
              console.warn('⚠️ Google Maps API failed:', error.message);
              return []; 
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
              return []; 
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
              return []; 
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      const [googleMapsData, bookingData, serpAPIData] = await Promise.all(fetchPromises);

      
      const mergedHotels = mergeHotelData(googleMapsData, bookingData, serpAPIData);
      console.log(`✅ Merged ${mergedHotels.length} hotels from ${googleMapsData.length} Google Maps, ${bookingData.length} Booking.com, ${serpAPIData.length} SerpAPI`);

      
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


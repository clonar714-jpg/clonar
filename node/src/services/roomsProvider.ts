// src/services/roomsProvider.ts
import { Room, RoomSearchParams, RoomProviderResponse } from '../types/rooms';

/**
 * 🏨 Room Inventory Provider
 * 
 * This class is designed to work with ANY hotel booking API:
 * - Selfbook
 * - Booking.com
 * - Expedia Rapid API
 * - Amadeus
 * - Priceline Partner Network
 * - Any other booking engine
 * 
 * To integrate a real API:
 * 1. Replace fetchRooms() implementation with actual API call
 * 2. Update transformApiResponse() to map API response to Room interface
 * 3. Add API credentials to environment variables
 */

export class RoomInventoryProvider {
  /**
   * Fetch rooms from booking API
   * 
   * TODO: Replace with actual API call
   * 
   * Example for Selfbook:
   * const response = await axios.get(
   *   `https://api.selfbook.com/v1/hotels/${hotelId}/rooms`,
   *   {
   *     params: { checkIn, checkOut, guests },
   *     headers: { 'Authorization': `Bearer ${process.env.SELFBOOK_API_KEY}` }
   *   }
   * );
   * 
   * Example for Booking.com:
   * const response = await axios.get(
   *   `https://distribution-xml.booking.com/2.0/json/hotelAvailability`,
   *   {
   *     params: { hotel_ids: hotelId, checkin: checkIn, checkout: checkOut, guests: guests },
   *     headers: { 'Authorization': `Bearer ${process.env.BOOKING_API_KEY}` }
   *   }
   * );
   */
  async fetchRooms(params: RoomSearchParams): Promise<RoomProviderResponse> {
    const { hotelId, checkIn, checkOut, guests } = params;

    // TODO: Replace this with actual API call
    // For now, return mocked data
    console.log(`🏨 Fetching rooms for hotel ${hotelId} (${checkIn} to ${checkOut}, ${guests} guests)`);
    
    // Simulate API delay
    await new Promise(resolve => setTimeout(resolve, 500));

    // Return mocked rooms
    const rooms = this.getMockRooms();
    
    return {
      rooms,
      hotelId,
      checkIn,
      checkOut,
      guests,
      currency: 'USD',
    };
  }

  /**
   * Transform raw API response to normalized Room[] format
   * 
   * TODO: Map your actual API response structure to Room interface
   * 
   * Example mapping:
   * - API field "room_name" → Room.name
   * - API field "base_price" → Room.price
   * - API field "total_price" → Room.priceWithTaxes
   * - API field "photos" → Room.images
   * - API field "bed_configuration" → Room.bedType
   * - API field "room_amenities" → Room.amenities
   */
  transformApiResponse(rawApiData: any): Room[] {
    // TODO: Implement actual transformation logic
    // This is a placeholder that will be replaced with real API mapping
    
    if (!rawApiData || !Array.isArray(rawApiData)) {
      return [];
    }

    return rawApiData.map((item: any) => {
      return {
        id: item.id || item.room_id || String(Math.random()),
        name: item.name || item.room_name || item.title || 'Standard Room',
        description: item.description || item.room_description,
        price: this.normalizePrice(item.price || item.base_price || item.rate_per_night),
        priceWithTaxes: this.normalizePrice(item.total_price || item.price_with_taxes || item.final_price),
        images: this.normalizeRoomImages(item.images || item.photos || item.room_images),
        bedType: this.normalizeBedTypes(item.bed_type || item.bed_configuration || item.beds),
        amenities: this.normalizeAmenities(item.amenities || item.room_amenities || item.features),
        refundable: item.refundable !== undefined ? item.refundable : item.cancellation_policy?.includes('free'),
        available: this.normalizeRoomAvailability(item.available || item.availability !== 'unavailable'),
        roomSize: item.room_size || item.size || item.square_feet,
        maxOccupancy: item.max_occupancy || item.max_guests || item.capacity,
        cancellationPolicy: item.cancellation_policy || item.cancellation,
      };
    });
  }

  /**
   * Normalize price to number
   */
  private normalizePrice(price: any): number {
    if (typeof price === 'number') return price;
    if (typeof price === 'string') {
      // Remove currency symbols and commas
      const cleaned = price.replace(/[^0-9.]/g, '');
      const parsed = parseFloat(cleaned);
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  /**
   * Normalize room images array
   */
  private normalizeRoomImages(images: any): string[] {
    if (!images) return [];
    if (Array.isArray(images)) {
      return images
        .map(img => typeof img === 'string' ? img : (img?.url || img?.src || String(img)))
        .filter(url => url && url.startsWith('http'));
    }
    if (typeof images === 'string') {
      return [images];
    }
    return [];
  }

  /**
   * Normalize bed types
   */
  private normalizeBedTypes(beds: any): string[] {
    if (!beds) return [];
    if (Array.isArray(beds)) {
      return beds.map(bed => {
        if (typeof bed === 'string') return bed;
        if (bed?.type && bed?.count) {
          return `${bed.count} ${bed.type} Bed${bed.count > 1 ? 's' : ''}`;
        }
        return String(bed);
      });
    }
    if (typeof beds === 'string') {
      return [beds];
    }
    return [];
  }

  /**
   * Normalize amenities
   */
  private normalizeAmenities(amenities: any): string[] {
    if (!amenities) return [];
    if (Array.isArray(amenities)) {
      return amenities.map(a => typeof a === 'string' ? a : (a?.name || String(a)));
    }
    if (typeof amenities === 'string') {
      return amenities.split(',').map(a => a.trim());
    }
    return [];
  }

  /**
   * Normalize room availability
   */
  private normalizeRoomAvailability(available: any): boolean {
    if (typeof available === 'boolean') return available;
    if (typeof available === 'string') {
      return available.toLowerCase() !== 'unavailable' && available.toLowerCase() !== 'sold out';
    }
    return true; // Default to available if unknown
  }

  /**
   * Mock rooms for testing UI
   * 
   * TODO: Remove this when real API is integrated
   */
  private getMockRooms(): Room[] {
    return [
      {
        id: 'suite123',
        name: 'Executive Suite',
        description: 'Spacious suite with separate living area',
        price: 309.00,
        priceWithTaxes: 363.14,
        images: [
          'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800',
          'https://images.unsplash.com/photo-1590490360182-c33d57733427?w=800',
        ],
        bedType: ['1 King Bed'],
        amenities: ['AM/FM radio', 'Alarm clock', 'Bathrobe', 'Desk'],
        refundable: true,
        available: true,
        roomSize: '650 sq ft',
        maxOccupancy: 4,
      },
      {
        id: 'premier456',
        name: 'Premier Room',
        description: 'Modern room with city views',
        price: 299.00,
        priceWithTaxes: 351.38,
        images: [
          'https://images.unsplash.com/photo-1590490360182-c33d57733427?w=800',
          'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800',
        ],
        bedType: ['1 King Bed'],
        amenities: ['AM/FM radio', 'Bathrobe', 'Desk', 'Mini fridge'],
        refundable: true,
        available: true,
        roomSize: '350 sq ft',
        maxOccupancy: 2,
      },
      {
        id: 'standard789',
        name: 'Accessible Standard Room',
        description: 'Comfortable accessible room',
        price: 349.00,
        priceWithTaxes: 410.14,
        images: [
          'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800',
        ],
        bedType: ['2 Queen Bed'],
        amenities: ['AM/FM radio', 'Alarm clock', 'Accessible features'],
        refundable: false,
        available: true,
        roomSize: '300 sq ft',
        maxOccupancy: 4,
      },
    ];
  }
}


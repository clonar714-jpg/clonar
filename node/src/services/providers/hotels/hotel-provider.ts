// src/services/providers/hotels/hotel-provider.ts
import { HotelFilters } from '@/types/verticals';

export interface Hotel {
  id: string;
  name: string;
  pricePerNight: number;
  currency: string;
  rating?: number;
  reviewCount?: number;
  location: string;
  thumbnailUrl?: string;
  bookingUrl?: string;       // link or deeplink to booking flow
  lat?: number;
  lng?: number;
}

export interface HotelProvider {
  name: string;
  searchHotels(filters: HotelFilters): Promise<Hotel[]>;
}

// src/services/providers/hotels/hotel-provider.ts
// Canonical hotel shape for all providers. Aligns with what Perplexity/ChatGPT/Booking
// show: ratings, location+coordinates, amenities, description, policies, media.
import { HotelFilters } from '@/types/verticals';

export interface Hotel {
  id: string;
  name: string;
  pricePerNight: number;
  currency: string;
  /** Guest rating (e.g. 0–5 or 0–10); display in cards and detail. */
  rating?: number;
  reviewCount?: number;
  /** Official star classification (1–5). */
  starRating?: number;
  /** Display location (e.g. "Downtown NYC", "Near Times Square"). */
  location: string;
  /** Full street address when available. */
  address?: string;
  /** Coordinates for map; required for showMap in UI decision. */
  lat?: number;
  lng?: number;
  /** Primary image for list/card. */
  thumbnailUrl?: string;
  /** Additional images for detail/gallery (Perplexity-style). */
  imageUrls?: string[];
  /** Link or deeplink to booking flow. */
  bookingUrl?: string;
  /** Hotel’s own website (for "website" action). */
  websiteUrl?: string;
  /** Phone for "call" action. */
  phone?: string;
  /** Short summary or "why we recommend" (Perplexity/ChatGPT style). */
  description?: string;
  /** Amenities (e.g. "Free WiFi", "Pool", "Parking") for filters and badges. */
  amenities?: string[];
  /** Badges/themes (e.g. "Family-friendly", "Business") for card chips. */
  themes?: string[];
  /** Check-in time (e.g. "3:00 PM"). */
  checkInTime?: string;
  /** Check-out time (e.g. "11:00 AM"). */
  checkOutTime?: string;
}

export interface HotelProvider {
  name: string;
  searchHotels(filters: HotelFilters): Promise<Hotel[]>;
}

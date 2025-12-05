/**
 * 📚 Example Providers for All Fields
 * These are templates showing how to implement providers for any field type
 * Copy and modify these when you get new APIs (Shopify, TripAdvisor, Kiwi, etc.)
 */

import { BaseProvider, FieldType, SearchOptions } from "./baseProvider";
import axios from "axios";

// ============================================================================
// SHOPPING PROVIDERS
// ============================================================================

/**
 * Example: Shopify Provider
 * Copy this template when you get Shopify API credentials
 */
export class ShopifyProvider implements BaseProvider {
  name = "Shopify";
  fieldType: FieldType = "shopping";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Replace with actual Shopify API
    // const apiKey = process.env.SHOPIFY_API_KEY;
    // const shop = process.env.SHOPIFY_SHOP;
    // 
    // const response = await axios.get(
    //   `https://${shop}.myshopify.com/admin/api/2024-01/products.json`,
    //   {
    //     headers: { 'X-Shopify-Access-Token': apiKey },
    //     params: { title: query, limit: options?.limit || 20 }
    //   }
    // );
    // 
    // return response.data.products.map((p: any) => ({
    //   title: p.title,
    //   price: p.variants[0]?.price || "0",
    //   // ... map to standard format
    // }));

    console.warn("⚠️ Shopify provider not yet implemented");
    return [];
  }
}

/**
 * Example: Amazon Provider
 * Copy this template when you get Amazon API credentials
 */
export class AmazonProvider implements BaseProvider {
  name = "Amazon";
  fieldType: FieldType = "shopping";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Implement Amazon Product Advertising API
    // const apiKey = process.env.AMAZON_API_KEY;
    // const secretKey = process.env.AMAZON_SECRET_KEY;
    // 
    // const response = await axios.get(
    //   "https://webservices.amazon.com/paapi5/searchitems",
    //   {
    //     headers: { /* Amazon API headers */ },
    //     params: { Keywords: query, ItemCount: options?.limit || 20 }
    //   }
    // );
    // 
    // return response.data.SearchResult.Items.map((item: any) => ({
    //   title: item.ItemInfo.Title.DisplayValue,
    //   price: item.Offers.Listings[0]?.Price.DisplayAmount || "0",
    //   // ... map to standard format
    // }));

    console.warn("⚠️ Amazon provider not yet implemented");
    return [];
  }
}

// ============================================================================
// HOTEL PROVIDERS
// ============================================================================

/**
 * Example: TripAdvisor Provider
 * Copy this template when you get TripAdvisor API credentials
 */
export class TripAdvisorProvider implements BaseProvider {
  name = "TripAdvisor";
  fieldType: FieldType = "hotels";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Replace with actual TripAdvisor API
    // const apiKey = process.env.TRIPADVISOR_API_KEY;
    // 
    // const response = await axios.get(
    //   "https://api.tripadvisor.com/api/partner/2.0/location/search",
    //   {
    //     headers: { 'X-TripAdvisor-API-Key': apiKey },
    //     params: {
    //       searchQuery: query,
    //       category: 'hotels',
    //       limit: options?.limit || 20
    //     }
    //   }
    // );
    // 
    // return response.data.data.map((hotel: any) => ({
    //   name: hotel.name,
    //   rating: hotel.rating || 0,
    //   location: hotel.location_string || "",
    //   // ... map to standard format
    // }));

    console.warn("⚠️ TripAdvisor provider not yet implemented");
    return [];
  }
}

/**
 * Example: Booking.com Provider
 * Copy this template when you get Booking.com API credentials
 */
export class BookingProvider implements BaseProvider {
  name = "Booking.com";
  fieldType: FieldType = "hotels";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Implement Booking.com API
    console.warn("⚠️ Booking.com provider not yet implemented");
    return [];
  }
}

// ============================================================================
// FLIGHT PROVIDERS
// ============================================================================

/**
 * Example: Kiwi.com Provider
 * Copy this template when you get Kiwi API credentials
 */
export class KiwiProvider implements BaseProvider {
  name = "Kiwi";
  fieldType: FieldType = "flights";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Replace with actual Kiwi API
    // const apiKey = process.env.KIWI_API_KEY;
    // 
    // const response = await axios.get(
    //   "https://api.skypicker.com/flights",
    //   {
    //     headers: { 'apikey': apiKey },
    //     params: {
    //       flyFrom: options?.location || query,
    //       to: options?.filters?.destination,
    //       dateFrom: options?.departureDate,
    //       dateTo: options?.returnDate,
    //       limit: options?.limit || 20
    //     }
    //   }
    // );
    // 
    // return response.data.data.map((flight: any) => ({
    //   airline: flight.airline,
    //   price: flight.price || "0",
    //   departure: flight.dTime,
    //   arrival: flight.aTime,
    //   // ... map to standard format
    // }));

    console.warn("⚠️ Kiwi provider not yet implemented");
    return [];
  }
}

/**
 * Example: Amadeus Provider
 * Copy this template when you get Amadeus API credentials
 */
export class AmadeusProvider implements BaseProvider {
  name = "Amadeus";
  fieldType: FieldType = "flights";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Implement Amadeus API
    console.warn("⚠️ Amadeus provider not yet implemented");
    return [];
  }
}

// ============================================================================
// RESTAURANT PROVIDERS
// ============================================================================

/**
 * Example: Yelp Provider
 * Copy this template when you get Yelp API credentials
 */
export class YelpProvider implements BaseProvider {
  name = "Yelp";
  fieldType: FieldType = "restaurants";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Replace with actual Yelp API
    // const apiKey = process.env.YELP_API_KEY;
    // 
    // const response = await axios.get(
    //   "https://api.yelp.com/v3/businesses/search",
    //   {
    //     headers: { 'Authorization': `Bearer ${apiKey}` },
    //     params: {
    //       term: query,
    //       location: options?.location,
    //       limit: options?.limit || 20
    //     }
    //   }
    // );
    // 
    // return response.data.businesses.map((restaurant: any) => ({
    //   name: restaurant.name,
    //   rating: restaurant.rating || 0,
    //   location: restaurant.location.display_address.join(", "),
    //   // ... map to standard format
    // }));

    console.warn("⚠️ Yelp provider not yet implemented");
    return [];
  }
}

// ============================================================================
// PLACES PROVIDERS
// ============================================================================

/**
 * Example: Google Places Provider (alternative to current implementation)
 * This shows how to use the unified system for places
 */
export class GooglePlacesProvider implements BaseProvider {
  name = "Google Places";
  fieldType: FieldType = "places";

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // TODO: Implement Google Places API using unified interface
    // const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
    // 
    // const response = await axios.get(
    //   "https://maps.googleapis.com/maps/api/place/textsearch/json",
    //   {
    //     params: {
    //       query: query,
    //       key: apiKey,
    //       maxResults: options?.limit || 20
    //     }
    //   }
    // );
    // 
    // return response.data.results.map((place: any) => ({
    //   name: place.name,
    //   rating: place.rating || 0,
    //   location: place.formatted_address,
    //   // ... map to standard format
    // }));

    console.warn("⚠️ Google Places provider (unified) not yet implemented");
    return [];
  }
}


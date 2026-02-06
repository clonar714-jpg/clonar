/**
 * Contract for MCP capability tools: input args and normalized JSON result shape.
 * App calls tools by CAPABILITY (product_search, hotel_search, flight_search).
 * Provider selection, auth, request formatting, and response normalization live inside MCP servers.
 */

import type { ProductFilters, HotelFilters, FlightFilters, MovieTicketFilters } from '@/types/verticals';
import type { Product } from '@/services/providers/catalog/catalog-provider';
import type { Hotel } from '@/services/providers/hotels/hotel-provider';
import type { Flight } from '@/services/providers/flights/flight-provider';
import type { MovieShowtime } from '@/services/providers/movies/movie-provider';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';

export type { ProductFilters, HotelFilters, FlightFilters, MovieTicketFilters };

/** Input for product_search tool (capability: product search). */
export interface ProductSearchToolInput {
  query: string;
  rewrittenQuery: string;
  category?: string;
  budgetMin?: number;
  budgetMax?: number;
  brands?: string[];
  attributes?: Record<string, string | number | boolean>;
  preferenceContext?: string | string[];
}

/** Normalized result from product_search tool. */
export interface ProductSearchToolResult {
  products: Product[];
  snippets: RetrievedSnippet[];
}

/** Input for hotel_search tool (capability: hotel search). */
export interface HotelSearchToolInput {
  rewrittenQuery: string;
  destination: string;
  checkIn: string;
  checkOut: string;
  guests: number;
  budgetMin?: number;
  budgetMax?: number;
  area?: string;
  amenities?: string[];
  preferenceContext?: string | string[];
}

/** Normalized result from hotel_search tool. */
export interface HotelSearchToolResult {
  hotels: Hotel[];
  snippets: RetrievedSnippet[];
}

/** Input for flight_search tool (capability: flight search). */
export interface FlightSearchToolInput {
  rewrittenQuery: string;
  origin: string;
  destination: string;
  departDate: string;
  returnDate?: string;
  adults: number;
  cabin?: 'economy' | 'premium' | 'business' | 'first';
  preferenceContext?: string | string[];
}

/** Normalized result from flight_search tool. */
export interface FlightSearchToolResult {
  flights: Flight[];
  snippets: RetrievedSnippet[];
}

/** Input for movie_search tool (capability: movie/showtimes search). */
export interface MovieSearchToolInput {
  rewrittenQuery: string;
  city: string;
  date: string;
  movieTitle?: string;
  timeWindow?: string;
  tickets: number;
  format?: string;
  preferenceContext?: string | string[];
}

/** Normalized result from movie_search tool. */
export interface MovieSearchToolResult {
  showtimes: MovieShowtime[];
  snippets: RetrievedSnippet[];
}

/** Structured weather result for weather_search tool. */
export interface WeatherResult {
  location: string;
  date: string;
  temperature: {
    min: number;
    max: number;
    unit: 'celsius' | 'fahrenheit';
  };
  condition: string;
  precipitation: {
    type: 'rain' | 'snow' | 'sleet' | 'none';
    probability: number;
  };
}

/** Input for weather_search tool (capability: weather). */
export interface WeatherSearchToolInput {
  location: string;
  date: string; // YYYY-MM-DD
}

/** Normalized result from weather_search tool. */
export interface WeatherSearchToolResult {
  weather: WeatherResult;
  snippets: RetrievedSnippet[];
}

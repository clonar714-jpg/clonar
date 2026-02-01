// src/types/verticals.ts
import { BasePlan } from './core';

export type { PlanCandidate } from './core';

export interface ProductFilters {
  query: string;
  category?: string;
  budgetMin?: number;
  budgetMax?: number;
  brands?: string[];
  attributes?: Record<string, string | number | boolean>;
}

export interface HotelFilters {
  destination: string;
  checkIn: string;   // ISO date
  checkOut: string;  // ISO date
  guests: number;
  budgetMin?: number;
  budgetMax?: number;
  area?: string;
  amenities?: string[];
}

export interface FlightFilters {
  origin: string;         // "SFO"
  destination: string;   // "JFK"
  departDate: string;    // YYYY-MM-DD
  returnDate?: string;   // optional
  adults: number;
  cabin?: 'economy' | 'premium' | 'business' | 'first';
}

export interface MovieTicketFilters {
  city: string;            // e.g. "San Francisco"
  movieTitle?: string;     // "Dune 2"
  date: string;            // YYYY-MM-DD
  timeWindow?: string;     // "evening", "afternoon"
  tickets: number;         // number of seats
  format?: string;         // "IMAX", "3D", "2D"
}

export type VerticalPlan =
  | (BasePlan & { vertical: 'product'; product: ProductFilters })
  | (BasePlan & { vertical: 'hotel';   hotel:   HotelFilters })
  | (BasePlan & { vertical: 'flight';  flight:  FlightFilters })
  | (BasePlan & { vertical: 'movie';   movie:   MovieTicketFilters })
  | (BasePlan & { vertical: 'other' });

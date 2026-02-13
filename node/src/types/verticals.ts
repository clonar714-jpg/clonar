
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
  checkIn: string;   
  checkOut: string;  
  guests: number;
  budgetMin?: number;
  budgetMax?: number;
  area?: string;
  amenities?: string[];
}

export interface FlightFilters {
  origin: string;         
  destination: string;  
  departDate: string;    
  returnDate?: string;   
  adults: number;
  cabin?: 'economy' | 'premium' | 'business' | 'first';
}

export interface MovieTicketFilters {
  city: string;           
  movieTitle?: string;     
  date: string;            
  timeWindow?: string;     
  tickets: number;         
  format?: string;         
}

export type VerticalPlan =
  | (BasePlan & { vertical: 'product'; product: ProductFilters })
  | (BasePlan & { vertical: 'hotel';   hotel:   HotelFilters })
  | (BasePlan & { vertical: 'flight';  flight:  FlightFilters })
  | (BasePlan & { vertical: 'movie';   movie:   MovieTicketFilters })
  | (BasePlan & { vertical: 'other' });

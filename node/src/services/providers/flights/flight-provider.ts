// src/services/providers/flights/flight-provider.ts
import { FlightFilters } from '@/types/verticals';

export interface Flight {
  id: string;
  carrier: string;
  flightNumber: string;
  origin: string;
  destination: string;
  departTime: string;   // ISO datetime
  arriveTime: string;   // ISO datetime
  durationMinutes: number;
  price: number;
  currency: string;
  cabin: string;
  bookingUrl?: string;
}

export interface FlightProvider {
  name: string;
  searchFlights(filters: FlightFilters): Promise<Flight[]>;
}

// src/services/providers/flights/flight-provider.ts
// Canonical flight shape for all providers. Aligns with Perplexity/ChatGPT/OTA display:
// carrier, times, stops, aircraft, terminal, baggage.
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
  /** Aircraft type (e.g. "A321", "B737"). */
  aircraftType?: string;
  /** 0 = direct, 1+ = number of stops. */
  stops?: number;
  /** Origin terminal/gate when available. */
  originTerminal?: string;
  destinationTerminal?: string;
  /** Carrier logo URL for UI. */
  carrierLogoUrl?: string;
  /** Baggage allowance summary (e.g. "1 carry-on included"). */
  baggageInfo?: string;
}

export interface FlightProvider {
  name: string;
  searchFlights(filters: FlightFilters): Promise<Flight[]>;
}

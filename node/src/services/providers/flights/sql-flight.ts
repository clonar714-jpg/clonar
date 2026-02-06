// Stub SQL flight provider. Replace with real DB or flight API in production.
import { FlightFilters } from '@/types/verticals';
import { Flight, FlightProvider } from './flight-provider';

export class SqlFlightProvider implements FlightProvider {
  readonly name = 'sql-flight';

  async searchFlights(_filters: FlightFilters): Promise<Flight[]> {
    return [];
  }
}

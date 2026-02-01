import { FlightFilters } from '@/types/verticals';
import { Flight } from './flight-provider';
import type { RetrievedSnippet } from '../retrieval-types';

export interface FlightRetriever {
  searchFlights(
    filters: FlightFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{
    flights: Flight[];
    snippets: RetrievedSnippet[];
  }>;
  getMaxItems?(): number;
}

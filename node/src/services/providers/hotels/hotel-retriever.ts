import { HotelFilters } from '@/types/verticals';
import { Hotel } from './hotel-provider';
import type { RetrievedSnippet } from '../retrieval-types';

export interface HotelRetriever {
  searchHotels(
    filters: HotelFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{
    hotels: Hotel[];
    snippets: RetrievedSnippet[];
  }>;
  getMaxItems?(): number;
}

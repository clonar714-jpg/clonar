// Stub SQL hotel provider. Replace with real DB in production.
import { HotelFilters } from '@/types/verticals';
import { Hotel, HotelProvider } from './hotel-provider';

export class SqlHotelProvider implements HotelProvider {
  readonly name = 'sql-hotel';

  async searchHotels(_filters: HotelFilters): Promise<Hotel[]> {
    return [];
  }
}

// Stub SQL movie provider. Replace with real DB or movie API in production.
import { MovieTicketFilters } from '@/types/verticals';
import { MovieShowtime, MovieProvider } from './movie-provider';

export class SqlMovieProvider implements MovieProvider {
  readonly name = 'sql-movie';

  async searchShowtimes(_filters: MovieTicketFilters): Promise<MovieShowtime[]> {
    return [];
  }
}

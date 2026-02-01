import type { UiDecision } from '@/types/core';
import type { MovieShowtime } from '@/services/providers/movies/movie-provider';

export function buildMovieUiDecision(
  _query: string,
  showtimes: MovieShowtime[],
): UiDecision {
  if (!showtimes.length) {
    return {
      layout: 'list',
      showMap: false,
      highlightImages: false,
      showCards: false,
      primaryActions: [],
    };
  }

  const cinemaNames = new Set(showtimes.map((s) => s.cinemaName).filter(Boolean));
  const singleCinema = cinemaNames.size === 1;
  const first = showtimes[0];

  return {
    layout: singleCinema ? 'detail' : 'list',
    showMap: singleCinema && first?.lat != null && first?.lng != null,
    highlightImages: true,
    showCards: true,
    primaryActions: ['watch'],
  };
}

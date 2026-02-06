// src/services/providers/movies/movie-provider.ts
// Canonical movie showtime shape for all providers. Aligns with Perplexity/ChatGPT/cinema
// display: poster, runtime, genre, rating, cinema address, end time.
import { MovieTicketFilters } from '@/types/verticals';

export interface MovieShowtime {
  id: string;
  movieTitle: string;
  cinemaName: string;
  city: string;
  date: string;          // YYYY-MM-DD
  startTime: string;     // HH:MM, local
  format: string;        // IMAX, 3D, 2D
  pricePerTicket: number;
  currency: string;
  availableSeats: number;
  bookingUrl?: string;
  /** Movie poster image URL. */
  posterUrl?: string;
  /** Runtime in minutes. */
  runtimeMinutes?: number;
  /** Genre(s), e.g. "Action", "Drama". */
  genre?: string[];
  /** Content rating (e.g. "PG-13", "R"). */
  contentRating?: string;
  /** Cinema address for directions. */
  cinemaAddress?: string;
  /** End time (HH:MM) when available. */
  endTime?: string;
  /** Screen or theater name. */
  screenName?: string;
}

export interface MovieProvider {
  name: string;
  searchShowtimes(filters: MovieTicketFilters): Promise<MovieShowtime[]>;
}

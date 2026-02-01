// src/services/providers/movies/movie-provider.ts
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
  lat?: number;
  lng?: number;
}

export interface MovieProvider {
  name: string;
  searchShowtimes(filters: MovieTicketFilters): Promise<MovieShowtime[]>;
}

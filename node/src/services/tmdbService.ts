/**
 * Stub TMDB service so /api/movies routes load.
 * Replace with real TMDB API calls (TMDB_API_KEY) for production.
 */

export async function searchMovies(_query: string, _page: number = 1) {
  return { results: [], page: 1, total_pages: 0, total_results: 0 };
}

export async function getMovieDetails(_movieId: string | number) {
  return null;
}

export async function getPopularMovies(_page: number = 1) {
  return { results: [], page: 1, total_pages: 0, total_results: 0 };
}

export async function getTrendingMovies(_timeWindow: string = 'week') {
  return { results: [], page: 1, total_pages: 0, total_results: 0 };
}

export async function getMovieCredits(_movieId: string | number) {
  return { cast: [], crew: [] };
}

export async function getMovieVideos(_movieId: string | number) {
  return { results: [] };
}

export async function getMovieImages(_movieId: string | number) {
  return { backdrops: [], posters: [] };
}

export async function getMovieReviews(_movieId: string | number, _page: number = 1) {
  return { results: [], page: 1, total_pages: 0, total_results: 0 };
}

export async function getPersonDetails(_personId: string | number) {
  return null;
}

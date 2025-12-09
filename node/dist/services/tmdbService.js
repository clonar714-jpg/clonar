/**
 * TMDB (The Movie Database) Service
 * Handles movie-related API calls using TMDB API
 */
/**
 * Get TMDB API key from environment variables
 * @throws Error if TMDB_API_KEY is not set
 */
export function getTMDBApiKey() {
    const apiKey = process.env.TMDB_API_KEY;
    if (!apiKey) {
        throw new Error("Missing TMDB_API_KEY environment variable");
    }
    return apiKey;
}
/**
 * TMDB API base URL
 */
const TMDB_BASE_URL = "https://api.themoviedb.org/3";
/**
 * Search for movies using TMDB API
 * @param query - Search query
 * @param page - Page number (default: 1)
 * @returns Promise with movie search results
 */
export async function searchMovies(query, page = 1) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/search/movie?api_key=${apiKey}&query=${encodeURIComponent(query)}&page=${page}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error searching movies:", error);
        throw error;
    }
}
/**
 * Get movie details by ID
 * @param movieId - TMDB movie ID
 * @returns Promise with movie details
 */
export async function getMovieDetails(movieId) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/movie/${movieId}?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching movie details:", error);
        throw error;
    }
}
/**
 * Get popular movies
 * @param page - Page number (default: 1)
 * @returns Promise with popular movies
 */
export async function getPopularMovies(page = 1) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/movie/popular?api_key=${apiKey}&page=${page}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching popular movies:", error);
        throw error;
    }
}
/**
 * Get trending movies
 * @param timeWindow - 'day' or 'week' (default: 'day')
 * @returns Promise with trending movies
 */
export async function getTrendingMovies(timeWindow = 'day') {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/trending/movie/${timeWindow}?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching trending movies:", error);
        throw error;
    }
}
/**
 * Get movie credits (cast and crew)
 * @param movieId - TMDB movie ID
 * @returns Promise with movie credits
 */
export async function getMovieCredits(movieId) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/movie/${movieId}/credits?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching movie credits:", error);
        throw error;
    }
}
/**
 * Get movie videos (trailers, teasers, etc.)
 * @param movieId - TMDB movie ID
 * @returns Promise with movie videos
 */
export async function getMovieVideos(movieId) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/movie/${movieId}/videos?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching movie videos:", error);
        throw error;
    }
}
/**
 * Get movie images (posters, backdrops)
 * @param movieId - TMDB movie ID
 * @returns Promise with movie images
 */
export async function getMovieImages(movieId) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/movie/${movieId}/images?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching movie images:", error);
        throw error;
    }
}
/**
 * Get movie reviews
 * @param movieId - TMDB movie ID
 * @param page - Page number (default: 1)
 * @returns Promise with movie reviews
 */
export async function getMovieReviews(movieId, page = 1) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/movie/${movieId}/reviews?api_key=${apiKey}&page=${page}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching movie reviews:", error);
        throw error;
    }
}
/**
 * Get movies currently playing in theaters
 * @param page - Page number (default: 1)
 * @param region - ISO 3166-1 country code (optional, e.g., 'US')
 * @returns Promise with movies currently in theaters
 */
export async function getNowPlayingMovies(page = 1, region) {
    const apiKey = getTMDBApiKey();
    let url = `${TMDB_BASE_URL}/movie/now_playing?api_key=${apiKey}&page=${page}`;
    if (region) {
        url += `&region=${region}`;
    }
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching now playing movies:", error);
        throw error;
    }
}
/**
 * Get person details by ID (includes biography)
 * @param personId - TMDB person ID
 * @returns Promise with person details including biography
 */
export async function getPersonDetails(personId) {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/person/${personId}?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching person details:", error);
        throw error;
    }
}

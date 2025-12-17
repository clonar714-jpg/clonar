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
        const data = await response.json();
        // Log review count for debugging
        const reviewCount = data?.results?.length ?? 0;
        const totalPages = data?.total_pages ?? 0;
        console.log(`📝 Movie ${movieId} reviews: ${reviewCount} reviews on page ${page} (total pages: ${totalPages})`);
        // If no reviews on first page, try fetching multiple pages (up to 3) to get more reviews
        if (reviewCount === 0 && page === 1 && totalPages > 1) {
            console.log(`📝 No reviews on page 1, trying to fetch from multiple pages...`);
            const allReviews = [];
            // Fetch up to 3 pages to get more reviews
            for (let p = 1; p <= Math.min(3, totalPages); p++) {
                try {
                    const pageUrl = `${TMDB_BASE_URL}/movie/${movieId}/reviews?api_key=${apiKey}&page=${p}`;
                    const pageResponse = await fetch(pageUrl);
                    if (pageResponse.ok) {
                        const pageData = await pageResponse.json();
                        if (pageData?.results && Array.isArray(pageData.results)) {
                            allReviews.push(...pageData.results);
                        }
                    }
                }
                catch (err) {
                    console.warn(`⚠️ Failed to fetch reviews from page ${p}:`, err);
                }
            }
            if (allReviews.length > 0) {
                console.log(`✅ Found ${allReviews.length} reviews across ${Math.min(3, totalPages)} pages`);
                return {
                    ...data,
                    results: allReviews,
                    total_results: allReviews.length,
                };
            }
        }
        return data;
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
/**
 * Get list of movie genres
 * @returns Promise with genre list
 */
export async function getMovieGenres() {
    const apiKey = getTMDBApiKey();
    const url = `${TMDB_BASE_URL}/genre/movie/list?api_key=${apiKey}`;
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error fetching movie genres:", error);
        throw error;
    }
}
/**
 * Discover movies by genre, year, and other filters
 * @param genreId - Genre ID (optional)
 * @param year - Release year (optional)
 * @param page - Page number (default: 1)
 * @param sortBy - Sort by (default: 'popularity.desc')
 * @returns Promise with discovered movies
 */
export async function discoverMovies(options) {
    const apiKey = getTMDBApiKey();
    const { genreId, year, page = 1, sortBy = 'popularity.desc' } = options;
    let url = `${TMDB_BASE_URL}/discover/movie?api_key=${apiKey}&page=${page}&sort_by=${sortBy}`;
    if (genreId) {
        url += `&with_genres=${genreId}`;
    }
    if (year) {
        url += `&primary_release_year=${year}`;
    }
    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`TMDB API error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }
    catch (error) {
        console.error("❌ Error discovering movies:", error);
        throw error;
    }
}

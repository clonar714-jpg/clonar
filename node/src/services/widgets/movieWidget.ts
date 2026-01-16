/**
 * ✅ Agent-Style Movie Widget
 * Uses LLM to extract intent and fetches from multiple APIs (TMDB, SerpAPI)
 * Merges all sources with deduplication - no fallback needed
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';
import { search } from '../searchService';
import { searchMovies, getMovieDetails, getMovieImages, getMovieVideos } from '../tmdbService';
import z from 'zod';

// Intent extraction schema
const movieIntentSchema = z.object({
  title: z.string().nullable().optional().describe('Movie title or name'),
  year: z.number().nullable().optional().describe('Release year'),
  genre: z.string().nullable().optional().describe('Genre: action, comedy, drama, horror, sci-fi, etc.'),
  actor: z.string().nullable().optional().describe('Actor name'),
  director: z.string().nullable().optional().describe('Director name'),
  type: z.preprocess(
    (val) => {
      // ✅ FIX: Normalize invalid enum values to 'movie'
      if (val === null || val === undefined) return null;
      const str = String(val).toLowerCase();
      if (str === 'movie' || str === 'tv' || str === 'both') {
        return str;
      }
      // Invalid value (e.g., "theater") -> default to 'movie'
      return 'movie';
    },
    z.enum(['movie', 'tv', 'both']).nullable().optional()
  ).describe('Content type: "movie" for movies, "tv" for TV shows, "both" for either. Do NOT use "theater" or other values.'),
  streaming: z.boolean().nullable().optional().describe('Whether user wants streaming availability info'),
});

interface MovieIntent {
  title: string | null;
  year?: number | null;
  genre?: string | null;
  actor?: string | null;
  director?: string | null;
  type?: 'movie' | 'tv' | 'both' | null;
  streaming?: boolean | null;
}

// Fetch movies from TMDB API
async function fetchFromTMDB(
  intent: MovieIntent
): Promise<any[]> {
  try {
    // Build search query
    let query = intent.title || '';
    if (intent.actor) {
      query = `${query} ${intent.actor}`;
    }
    if (intent.director) {
      query = `${query} ${intent.director}`;
    }

    if (!query.trim()) {
      return [];
    }

    // Search movies
    const tmdbResponse = await searchMovies(query.trim(), 1);
    
    if (!tmdbResponse?.results || !Array.isArray(tmdbResponse.results)) {
      return [];
    }

    let movies = tmdbResponse.results.slice(0, 10);

    // Filter by year if specified
    if (intent.year) {
      movies = movies.filter((movie: any) => {
        const releaseYear = movie.release_date ? new Date(movie.release_date).getFullYear() : null;
        return releaseYear === intent.year;
      });
    }

    // Get detailed info for each movie (images, videos, etc.)
    const detailedMovies = await Promise.all(
      movies.map(async (movie: any) => {
        try {
          // Fetch additional details in parallel
          const [details, images, videos] = await Promise.all([
            getMovieDetails(movie.id).catch(() => null),
            getMovieImages(movie.id).catch(() => null),
            getMovieVideos(movie.id).catch(() => null),
          ]);

          // Build photos array from images
          const photos: string[] = [];
          if (images?.posters && images.posters.length > 0) {
            images.posters.slice(0, 5).forEach((poster: any) => {
              photos.push(`https://image.tmdb.org/t/p/w500${poster.file_path}`);
            });
          }
          if (images?.backdrops && images.backdrops.length > 0) {
            images.backdrops.slice(0, 3).forEach((backdrop: any) => {
              photos.push(`https://image.tmdb.org/t/p/w1280${backdrop.file_path}`);
            });
          }

          // Get trailer URL
          const trailer = videos?.results?.find((v: any) => 
            v.type === 'Trailer' && v.site === 'YouTube'
          );
          const trailerUrl = trailer ? `https://www.youtube.com/watch?v=${trailer.key}` : undefined;

          return {
            id: movie.id,
            title: movie.title || movie.name,
            releaseDate: movie.release_date,
            year: movie.release_date ? new Date(movie.release_date).getFullYear() : undefined,
            rating: movie.vote_average ? parseFloat(movie.vote_average.toString()) : undefined,
            reviewCount: movie.vote_count,
            description: movie.overview || details?.overview,
            genre: movie.genre_ids || details?.genres?.map((g: any) => g.name) || [],
            photos: photos,
            thumbnail: movie.poster_path ? `https://image.tmdb.org/t/p/w500${movie.poster_path}` : photos[0],
            backdrop: movie.backdrop_path ? `https://image.tmdb.org/t/p/w1280${movie.backdrop_path}` : undefined,
            trailer: trailerUrl,
            runtime: details?.runtime,
            budget: details?.budget,
            revenue: details?.revenue,
            imdbId: details?.imdb_id,
            source: 'tmdb',
          };
        } catch (error: any) {
          console.warn(`⚠️ Failed to get details for movie ${movie.id}:`, error.message);
          // Return basic info if details fail
          return {
            id: movie.id,
            title: movie.title || movie.name,
            releaseDate: movie.release_date,
            year: movie.release_date ? new Date(movie.release_date).getFullYear() : undefined,
            rating: movie.vote_average ? parseFloat(movie.vote_average.toString()) : undefined,
            reviewCount: movie.vote_count,
            description: movie.overview,
            genre: movie.genre_ids || [],
            photos: movie.poster_path ? [`https://image.tmdb.org/t/p/w500${movie.poster_path}`] : [],
            thumbnail: movie.poster_path ? `https://image.tmdb.org/t/p/w500${movie.poster_path}` : undefined,
            backdrop: movie.backdrop_path ? `https://image.tmdb.org/t/p/w1280${movie.backdrop_path}` : undefined,
            source: 'tmdb',
          };
        }
      })
    );

    return detailedMovies;
  } catch (error: any) {
    console.warn('⚠️ TMDB API failed:', error.message);
    return [];
  }
}

// Fetch movies from SerpAPI
async function fetchFromSerpAPI(
  intent: MovieIntent
): Promise<any[]> {
  try {
    // Build search query
    let query = '';
    if (intent.title) {
      query = intent.title;
    }
    if (intent.year) {
      query = `${query} ${intent.year}`;
    }
    if (intent.actor) {
      query = `${query} ${intent.actor}`;
    }
    if (intent.director) {
      query = `${query} ${intent.director}`;
    }
    if (intent.genre) {
      query = `${query} ${intent.genre} movie`;
    }
    if (!query.trim()) {
      query = 'movies';
    }

    // Use the search service to get SerpAPI results
    const searchResult = await search(query.trim(), [], {
      maxResults: 10,
      searchType: 'web',
    });

    // Extract movie data from SerpAPI rawResponse
    const movieResults = searchResult.rawResponse?.movies || 
                        searchResult.rawResponse?.movie_results ||
                        searchResult.rawResponse?.organic_results?.filter((r: any) => 
                          r.type === 'movie' || r.title?.toLowerCase().includes('movie')
                        ) || [];

    // Transform to consistent format
    return movieResults.map((movie: any) => ({
      id: movie.movie_id || movie.id || movie.link,
      title: movie.title || movie.name,
      releaseDate: movie.release_date || movie.year,
      year: movie.year ? parseInt(movie.year.toString()) : undefined,
      rating: movie.rating ? parseFloat(movie.rating.toString()) : undefined,
      reviewCount: movie.reviews ? parseInt(movie.reviews.toString()) : undefined,
      description: movie.description || movie.snippet || movie.overview,
      genre: movie.genre || (Array.isArray(movie.genres) ? movie.genres : []),
      photos: movie.images || movie.posters || (movie.thumbnail ? [movie.thumbnail] : []),
      thumbnail: movie.thumbnail || movie.poster || movie.image,
      backdrop: movie.backdrop || movie.background_image,
      trailer: movie.trailer || movie.trailer_url,
      streaming: movie.streaming || movie.where_to_watch,
      link: movie.link || movie.url || movie.website,
      source: 'serpapi',
    }));
  } catch (error: any) {
    console.warn('⚠️ SerpAPI search failed:', error.message);
    return [];
  }
}

// Decide which data sources to use based on intent
function decideDataSources(intent: MovieIntent): {
  useTMDB: boolean;
  useSerpAPI: boolean;
} {
  return {
    useTMDB: !!intent.title || !!intent.actor || !!intent.director, // Use if we have search criteria
    useSerpAPI: true, // Always use SerpAPI as one of the sources
  };
}

// Merge movie data from multiple sources, deduplicating by title + year
function mergeMovieData(
  tmdbData: any[],
  serpAPIData: any[]
): any[] {
  const merged: any[] = [];
  const seen = new Set<string>();
  
  // Helper to generate unique key for deduplication
  const getKey = (movie: any): string => {
    const title = (movie.title || movie.name || '').toLowerCase().trim();
    const year = movie.year || (movie.releaseDate ? new Date(movie.releaseDate).getFullYear() : '');
    return `${title}::${year}`;
  };
  
  // Priority 1: TMDB data (most authoritative - detailed info, images, videos)
  tmdbData.forEach(movie => {
    const key = getKey(movie);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push({
        ...movie,
        source: movie.source || 'tmdb',
      });
    }
  });
  
  // Priority 2: SerpAPI data (streaming info, additional links)
  serpAPIData.forEach(movie => {
    const key = getKey(movie);
    if (seen.has(key)) {
      // Merge with existing movie
      const existing = merged.find(m => getKey(m) === key);
      if (existing) {
        // Only add missing fields (don't overwrite authoritative sources)
        if (!existing.description && movie.description) existing.description = movie.description;
        if (!existing.thumbnail && movie.thumbnail) existing.thumbnail = movie.thumbnail;
        if (!existing.backdrop && movie.backdrop) existing.backdrop = movie.backdrop;
        if (!existing.trailer && movie.trailer) existing.trailer = movie.trailer;
        if (!existing.streaming && movie.streaming) existing.streaming = movie.streaming;
        if (!existing.link && movie.link) existing.link = movie.link;
        existing.source = existing.source ? `${existing.source}+serpapi` : 'serpapi';
      }
    } else {
      seen.add(key);
      merged.push({
        ...movie,
        source: movie.source || 'serpapi',
      });
    }
  });
  
  return merged;
}

// Separate evidence (factual) from commerce (streaming/tickets) data
function formatMovieCards(movies: any[]): any[] {
  return movies.map(movie => ({
    // Evidence (factual, non-commercial)
    id: movie.id || movie.movie_id || movie.link,
    title: movie.title || movie.name || 'Unknown Movie',
    releaseDate: movie.releaseDate || movie.release_date,
    year: movie.year || (movie.releaseDate ? new Date(movie.releaseDate).getFullYear() : undefined),
    rating: movie.rating ? parseFloat(movie.rating.toString()) : undefined,
    reviews: movie.reviewCount || movie.reviews || movie.vote_count,
    description: movie.description || movie.overview || movie.snippet,
    genre: movie.genre || movie.genres || [],
    photos: movie.photos || movie.images || (movie.thumbnail ? [movie.thumbnail] : []),
    thumbnail: movie.thumbnail || movie.poster || movie.image || '',
    backdrop: movie.backdrop || movie.background_image,
    trailer: movie.trailer || movie.trailer_url,
    runtime: movie.runtime,
    budget: movie.budget,
    revenue: movie.revenue,
    imdbId: movie.imdbId || movie.imdb_id,
    
    // Commerce (streaming/ticket-related)
    link: movie.link || movie.url || movie.website,
    streaming: movie.streaming || movie.where_to_watch,
    streamingLinks: movie.streamingLinks || (movie.streaming ? {
      netflix: movie.streaming.netflix,
      hulu: movie.streaming.hulu,
      amazon: movie.streaming.amazon,
      disney: movie.streaming.disney,
      hbo: movie.streaming.hbo,
    } : undefined),
    ticketLinks: movie.ticketLinks || (movie.link ? {
      fandango: movie.link.includes('fandango') ? movie.link : undefined,
      amc: movie.link.includes('amc') ? movie.link : undefined,
      regal: movie.link.includes('regal') ? movie.link : undefined,
    } : undefined),
  }));
}

const movieWidget: WidgetInterface = {
  type: 'movie',

  shouldExecute(classification?: any): boolean {
    // ✅ Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showMovieWidget) {
      return true;
    }
    
    // Check if movie widget should execute based on classification
    if (classification?.widgetTypes?.includes('movie')) {
      return true;
    }
    
    // Fallback: check intent/domains
    const detectedDomains = classification?.detectedDomains || [];
    const intent = classification?.intent || '';
    return detectedDomains.includes('movie') || intent === 'movie';
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget, classification, rawResponse, followUp, llm } = input;
    
    // ✅ CRITICAL: LLM is required for agent-style widget (intent extraction)
    if (!llm) {
      return {
        type: 'movie',
        data: [],
        success: false,
        error: 'LLM required for agent-style movie widget (intent extraction)',
      };
    }

    try {
      // Step 1: Extract structured intent using LLM
      const query = followUp || classification?.query || classification?.queryRefinement || widget?.params?.query || '';
      
      if (!query) {
        return {
          type: 'movie',
          data: [],
          success: false,
          error: 'No query provided for intent extraction',
        };
      }

      console.log('🔍 Extracting movie intent from query:', query);
      
      // Use generateObject if available, otherwise fall back to generateText + JSON parsing
      let intentOutput: { object: MovieIntent };
      
      if (typeof llm.generateObject === 'function') {
        try {
          intentOutput = await llm.generateObject({
            messages: [
              {
                role: 'system',
                content: 'Extract movie search intent from user query. Return ONLY valid JSON with structured data. For "type" field, use ONLY "movie", "tv", or "both" - do NOT use "theater" or other values. If information is not provided, use null.',
              },
              {
                role: 'user',
                content: query,
              },
            ],
            schema: movieIntentSchema,
          });
        } catch (error: any) {
          // ✅ FIX: Handle schema validation errors gracefully
          if (error?.issues) {
            console.warn('⚠️ Movie intent extraction schema error, using fallback:', error.issues);
            // Return a safe fallback intent
            intentOutput = {
              object: {
                title: null,
                type: 'movie', // Default to 'movie' for invalid type values
              },
            };
          } else {
            throw error;
          }
        }
      } else {
        // Fallback: use generateText and parse JSON
        const response = await llm.generateText({
          messages: [
            {
              role: 'system',
              content: 'Extract movie search intent from user query. Return ONLY valid JSON matching this schema: { title: string | null, year?: number | null, genre?: string | null, actor?: string | null, director?: string | null, type?: "movie" | "tv" | "both", streaming?: boolean }. If information is not provided, use null.',
            },
            {
              role: 'user',
              content: query,
            },
          ],
        });
        
        const text = typeof response === 'string' ? response : response.text || '';
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          intentOutput = { object: JSON.parse(jsonMatch[0]) };
        } else {
          throw new Error('Could not parse intent from LLM response');
        }
      }

      const intent: MovieIntent = intentOutput.object;
      
      // ✅ Normalize null values (no arrays in movie intent, scalars can stay null)
      // No arrays to normalize in movie intent
      
      console.log('✅ Extracted movie intent:', intent);

      // Step 2: Validate that we have at least some search criteria
      if (!intent.title && !intent.actor && !intent.director && !intent.genre) {
        return {
          type: 'movie',
          data: [],
          success: false,
          error: 'Could not extract movie search criteria from query (need title, actor, director, or genre)',
        };
      }

      // Step 3: Decide which data sources to use
      const sources = decideDataSources(intent);
      console.log('📊 Data sources decision:', sources);

      // Step 4: Fetch from ALL sources in parallel (no fallback - all are data sources)
      const fetchPromises: Promise<any[]>[] = [];
      
      if (sources.useTMDB) {
        fetchPromises.push(
          fetchFromTMDB(intent)
            .catch(error => {
              console.warn('⚠️ TMDB API failed:', error.message);
              return []; // Return empty array, continue with other sources
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      if (sources.useSerpAPI) {
        fetchPromises.push(
          fetchFromSerpAPI(intent)
            .catch(error => {
              console.warn('⚠️ SerpAPI failed:', error.message);
              return []; // Return empty array, continue with other sources
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      const [tmdbData, serpAPIData] = await Promise.all(fetchPromises);

      // Step 5: Merge data from all sources
      const mergedMovies = mergeMovieData(tmdbData, serpAPIData);
      console.log(`✅ Merged ${mergedMovies.length} movies from ${tmdbData.length} TMDB, ${serpAPIData.length} SerpAPI`);

      // Step 6: Format movie cards with evidence/commerce separation
      const movieCards = formatMovieCards(mergedMovies);

      if (movieCards.length === 0) {
        return {
          type: 'movie',
          data: [],
          success: false,
          error: 'No movies found from any data source (TMDB, SerpAPI)',
        };
      }

      return {
        type: 'movie',
        data: movieCards,
        success: true,
        llmContext: `Found ${movieCards.length} movies${intent.title ? ` matching "${intent.title}"` : ''}${intent.year ? ` from ${intent.year}` : ''} from multiple sources`,
      };
    } catch (error: any) {
      console.error('❌ Agent-style movie widget error:', error);
      
      // No fallback - return error (all sources are already included in the widget)
      return {
        type: 'movie',
        data: [],
        success: false,
        error: error.message || 'Failed to fetch movie data from all sources',
      };
    }
  },
};

export default movieWidget;

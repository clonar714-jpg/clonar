
import axios from "axios";


export interface Document {
  title: string;
  url: string;
  content: string;
  summary?: string;
  /** Source freshness: date or last_updated from provider (e.g. Perplexity). */
  date?: string;
  last_updated?: string;
  images?: string[]; 
  thumbnail?: string; 
  video?: { url: string; thumbnail?: string; title?: string }; 
  mapData?: { latitude: number; longitude: number; title: string }; 
}

export interface SearchOptions {
  needsMultipleSources?: boolean;
  needsFreshness?: boolean;
  maxResults?: number;
  searchType?: "web" | "images" | "videos";
  abortSignal?: AbortSignal; 
}

export interface SearchResult {
  documents: Document[];
  rawResponse: any;
  images?: Array<{ url: string; title?: string; source?: string }>;
  videos?: Array<{ url: string; thumbnail?: string; title?: string }>;
}


export interface PerplexityWebSearchResult {
  title: string;
  url: string;
  content?: string;
  author?: string;
  thumbnail?: string;
  images?: string[]; 
}

export interface PerplexityWebSearchResponse {
  results: PerplexityWebSearchResult[];
  suggestions: string[];
}


export async function searchWebPerplexity(
  query: string | string[],
  options?: {
    needsFreshness?: boolean;
    maxResults?: number;
    abortSignal?: AbortSignal;
  }
): Promise<PerplexityWebSearchResponse> {
  try {
    // Perplexity supports both single query (string) and multi-query (string[])
    // Type assertion needed because search() accepts string | string[]
    const searchResult = await search(query as string | string[], [], {
      needsMultipleSources: (options?.maxResults || 5) > 5,
      needsFreshness: options?.needsFreshness,
      maxResults: options?.maxResults || 5,
      searchType: 'web',
      abortSignal: options?.abortSignal,
    });

    
    const results: PerplexityWebSearchResult[] = searchResult.documents.map((doc) => ({
      title: doc.title,
      url: doc.url,
      content: doc.content,
      author: undefined,
      thumbnail: doc.thumbnail,
      images: doc.images, 
    }));

    
    // Perplexity API doesn't return suggestions in the standard response
    // Suggestions would need to be generated separately if needed
    const suggestions: string[] = [];

    return { results, suggestions };
  } catch (error: any) {
    if (error.name === 'AbortError' || error.message === 'Web search aborted' || error.message === 'Search aborted') {
      throw error; 
    }
    console.error('❌ Perplexity web search error:', error.message);
    return { results: [], suggestions: [] };
  }
}


export async function search(
  query: string | string[],
  conversationHistory: any[] = [],
  options: SearchOptions = {}
): Promise<SearchResult> {
  const perplexityKey = process.env.PERPLEXITY_API_KEY;
  if (!perplexityKey) {
    console.warn("⚠️ PERPLEXITY_API_KEY not found, skipping search");
    return { documents: [], rawResponse: null };
  }

  try {
    // Perplexity Search API handles query optimization internally
    // No need for manual query generation - trust Perplexity's intelligence
    const maxDocs = options.maxResults || (options.needsMultipleSources ? 7 : 5);
    const searchType = options.searchType || "web";

    console.log(`🔍 Searching ${searchType} for: "${query}"`);
    
   
    if (options.abortSignal?.aborted) {
      throw new Error('Search aborted');
    }
    
    
    const controller = new AbortController();
    if (options.abortSignal) {
      
      options.abortSignal.addEventListener('abort', () => {
        controller.abort();
      });
    }
    
    // Perplexity Search API endpoint
    const perplexityEndpoint = "https://api.perplexity.ai/search";
    
    // Ensure max_results is within valid range (1-20)
    const maxResults = Math.min(Math.max(maxDocs, 1), 20);
    
    // Perplexity API supports both string and string[] for query parameter
    const requestBody: any = {
      query: query, // Can be string or string[] - Perplexity handles optimization
      max_results: maxResults,
      ...(options.needsFreshness ? { search_recency_filter: "day" } : {}),
    };

    const response = await axios.post(perplexityEndpoint, requestBody, {
      headers: {
        'Authorization': `Bearer ${perplexityKey}`,
        'Content-Type': 'application/json',
      },
      timeout: 10000,
      signal: controller.signal,
    });
    
    const documents: Document[] = [];
    const images: Array<{ url: string; title?: string; source?: string }> = [];
    const videos: Array<{ url: string; thumbnail?: string; title?: string }> = [];

    // Perplexity API returns results in the format: { "results": [{ "title", "url", "snippet", "date", "last_updated" }] }
    const results = response.data?.results || [];

    if (searchType === "images") {
      // Note: Perplexity Search API doesn't have separate image search
      // Images would need to be extracted from web results or use a different endpoint
      console.warn("⚠️ Image search not directly supported by Perplexity Search API");
    } else if (searchType === "videos") {
      // Note: Perplexity Search API doesn't have separate video search
      // Videos would need to be extracted from web results or use a different endpoint
      console.warn("⚠️ Video search not directly supported by Perplexity Search API");
    } else {
      // Handle web search results from Perplexity
      // Perplexity API response format: { title, url, snippet, date, last_updated }
      for (const result of results) {
        if (result.title && result.url) {
          documents.push({
            title: result.title,
            url: result.url,
            content: result.snippet || '',
            summary: result.snippet, // Use snippet as summary
            date: result.date,
            last_updated: result.last_updated ?? result.date,
            // Note: Perplexity API doesn't return thumbnail/images/video in standard response
          });
        }
      }
    }

    console.log(`✅ Found ${documents.length} search results, ${images.length} images, ${videos.length} videos`);
    
    return { documents, rawResponse: response.data, images, videos };
  } catch (error: any) {
    
    if (error.name === 'AbortError' || error.name === 'CanceledError') {
      throw error; 
    }
    console.error("❌ Search failed:", error.message);
    return { documents: [], rawResponse: null };
  }
}


export async function searchWeb(
  query: string,
  conversationHistory: any[] = [],
  options?: { needsMultipleSources?: boolean; needsFreshness?: boolean }
): Promise<{ documents: Document[]; rawResponse: any }> {
  const result = await search(query, conversationHistory, {
    ...options,
    searchType: "web",
  });
  return { documents: result.documents, rawResponse: result.rawResponse };
}


export async function searchImages(
  query: string,
  conversationHistory: any[] = [],
  options?: { maxResults?: number }
): Promise<Array<{ url: string; title?: string; source?: string }>> {
  try {
    let optimizedQuery = query;
    
    // Try to optimize query if generator exists (optional)
    try {
      const imageQueryGen = await import("./imageSearchQueryGenerator");
      if (imageQueryGen.shouldGenerateImageQuery && imageQueryGen.shouldGenerateImageQuery(query, conversationHistory)) {
        try {
          optimizedQuery = await imageQueryGen.generateImageSearchQuery(query, conversationHistory);
          console.log(`🖼️ Image query optimized: "${query}" → "${optimizedQuery}"`);
        } catch (error: any) {
          console.warn("⚠️ Image query generation failed, using original:", error.message);
        }
      }
    } catch {
      // Query generator not available, use original query
    }
    
    
    const result = await search(optimizedQuery, conversationHistory, {
      ...options,
      searchType: "images",
    });
    
    return result.images || [];
  } catch (error: any) {
    console.error("❌ Image search error:", error);
    
    try {
      const result = await search(query, conversationHistory, {
        ...options,
        searchType: "images",
      });
      return result.images || [];
    } catch (fallbackError: any) {
      console.error("❌ Image search fallback also failed:", fallbackError);
      return []; 
    }
  }
}


export async function searchVideos(
  query: string,
  conversationHistory: any[] = [],
  options?: { maxResults?: number }
): Promise<Array<{ url: string; thumbnail?: string; title?: string }>> {
  try {
    let optimizedQuery = query;
    
    // Try to optimize query if generator exists (optional)
    try {
      const videoQueryGen = await import("./videoSearchQueryGenerator");
      if (videoQueryGen.shouldGenerateVideoQuery && videoQueryGen.shouldGenerateVideoQuery(query, conversationHistory)) {
        try {
          optimizedQuery = await videoQueryGen.generateVideoSearchQuery(query, conversationHistory);
          console.log(`🎥 Video query optimized: "${query}" → "${optimizedQuery}"`);
        } catch (error: any) {
          console.warn("⚠️ Video query generation failed, using original:", error.message);
        }
      }
    } catch {
      // Query generator not available, use original query
    }
    
    
    const result = await search(optimizedQuery, conversationHistory, {
      ...options,
      searchType: "videos",
    });
    
    return result.videos || [];
  } catch (error: any) {
    console.error("❌ Video search error:", error);
    
    try {
      const result = await search(query, conversationHistory, {
        ...options,
        searchType: "videos",
      });
      return result.videos || [];
    } catch (fallbackError: any) {
      console.error("❌ Video search fallback also failed:", fallbackError);
      return []; 
    }
  }
}


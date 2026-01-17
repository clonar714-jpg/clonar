
import axios from "axios";


export interface Document {
  title: string;
  url: string;
  content: string;
  summary?: string;
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


export interface SerpAPIWebSearchResult {
  title: string;
  url: string;
  content?: string;
  author?: string;
  thumbnail?: string;
  images?: string[]; 
}

export interface SerpAPIWebSearchResponse {
  results: SerpAPIWebSearchResult[];
  suggestions: string[];
}


export async function searchWebSerpAPI(
  query: string,
  options?: {
    needsFreshness?: boolean;
    maxResults?: number;
    abortSignal?: AbortSignal;
  }
): Promise<SerpAPIWebSearchResponse> {
  try {
   
    const searchResult = await search(query, [], {
      needsMultipleSources: (options?.maxResults || 5) > 5,
      needsFreshness: options?.needsFreshness,
      maxResults: options?.maxResults || 5,
      searchType: 'web',
      abortSignal: options?.abortSignal,
    });

    
    const results: SerpAPIWebSearchResult[] = searchResult.documents.map((doc) => ({
      title: doc.title,
      url: doc.url,
      content: doc.content,
      author: undefined,
      thumbnail: doc.thumbnail,
      images: doc.images, 
    }));

    
    const suggestions: string[] = searchResult.rawResponse?.related_questions?.map((q: any) => q.question) || 
                                   searchResult.rawResponse?.related_searches?.map((s: any) => s.query) || 
                                   [];

    return { results, suggestions };
  } catch (error: any) {
    if (error.name === 'AbortError' || error.message === 'Web search aborted' || error.message === 'Search aborted') {
      throw error; 
    }
    console.error('❌ SerpAPI web search error:', error.message);
    return { results: [], suggestions: [] };
  }
}


export async function search(
  query: string,
  conversationHistory: any[] = [],
  options: SearchOptions = {}
): Promise<SearchResult> {
  const serpKey = process.env.SERPAPI_KEY;
  if (!serpKey) {
    console.warn("⚠️ SERPAPI_KEY not found, skipping search");
    return { documents: [], rawResponse: null };
  }

  try {
    
    let searchQuery = query;
    const { generateSearchQuery, shouldGenerateQuery } = await import("./queryGenerator");
    if (shouldGenerateQuery(query, conversationHistory)) {
      try {
        searchQuery = await generateSearchQuery(query, conversationHistory);
        console.log(`🔍 Query generation: "${query}" → "${searchQuery}"`);
      } catch (err: any) {
        console.warn("⚠️ Query generation failed, using original query:", err.message);
      }
    }

    
    const maxDocs = options.maxResults || (options.needsMultipleSources ? 7 : 5);
    const searchType = options.searchType || "web";

    
    const params: any = {
      engine: searchType === "images" ? "google_images" : searchType === "videos" ? "youtube" : "google",
      q: searchQuery,
      api_key: serpKey,
      num: maxDocs,
      hl: "en",
      gl: "us",
      ...(options.needsFreshness ? { tbs: "qdr:d" } : {}),
    };

    console.log(`🔍 Searching ${searchType} for: "${query}"${searchQuery !== query ? ` → "${searchQuery}"` : ''}`);
    
   
    if (options.abortSignal?.aborted) {
      throw new Error('Search aborted');
    }
    
    
    const controller = new AbortController();
    if (options.abortSignal) {
      
      options.abortSignal.addEventListener('abort', () => {
        controller.abort();
      });
    }
    
    const response = await axios.get("https://serpapi.com/search.json", { 
      params, 
      timeout: 10000,
      signal: controller.signal,
    });
    
    const documents: Document[] = [];
    const images: Array<{ url: string; title?: string; source?: string }> = [];
    const videos: Array<{ url: string; thumbnail?: string; title?: string }> = [];

    if (searchType === "images") {
      
      const imageResults = response.data.images_results || [];
      for (const img of imageResults.slice(0, maxDocs)) {
        if (img.thumbnail || img.original) {
          images.push({
            url: img.original || img.thumbnail,
            title: img.title,
            source: img.link,
          });
        }
      }
    } else if (searchType === "videos") {
      
      const videoResults = response.data.video_results || [];
      for (const video of videoResults.slice(0, maxDocs)) {
        if (video.link) {
          videos.push({
            url: video.link,
            thumbnail: video.thumbnail,
            title: video.title,
          });
        }
      }
    } else {
      
      const organicResults = response.data.organic_results || [];

      
      for (const result of organicResults.slice(0, maxDocs)) {
        if (result.title && result.link && result.snippet) {
          
          const resultImages: string[] = [];
          if (result.thumbnail) resultImages.push(result.thumbnail);
          if (result.images && Array.isArray(result.images)) {
            resultImages.push(...result.images.slice(0, 3));
          }
          
          
          let video: { url: string; thumbnail?: string; title?: string } | undefined;
          if (result.video) {
            video = {
              url: result.video.link || result.video.url || '',
              thumbnail: result.video.thumbnail,
              title: result.video.title || result.title,
            };
            videos.push(video);
          }
          
          
          let mapData: { latitude: number; longitude: number; title: string } | undefined;
          if (result.gps_coordinates) {
            mapData = {
              latitude: result.gps_coordinates.latitude,
              longitude: result.gps_coordinates.longitude,
              title: result.title,
            };
          } else if (result.coordinates) {
            mapData = {
              latitude: result.coordinates.lat || result.coordinates.latitude,
              longitude: result.coordinates.lng || result.coordinates.longitude,
              title: result.title,
            };
          }
          
          documents.push({
            title: result.title,
            url: result.link,
            content: result.snippet,
            thumbnail: result.thumbnail,
            images: resultImages.length > 0 ? resultImages : undefined,
            video: video?.url ? video : undefined,
            mapData: mapData,
          });
        }
      }

     
      const videoResults = response.data.video_results || [];
      if (videoResults.length > 0) {
        for (const video of videoResults.slice(0, 3)) {
          if (video.title && video.link) {
            videos.push({
              url: video.link,
              thumbnail: video.thumbnail,
              title: video.title,
            });
            
            documents.push({
              title: video.title,
              url: video.link,
              content: video.snippet || video.description || video.title,
              thumbnail: video.thumbnail,
              video: {
                url: video.link,
                thumbnail: video.thumbnail,
                title: video.title,
              },
            });
          }
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
    
    const { 
      generateImageSearchQuery, 
      shouldGenerateImageQuery 
    } = await import("./imageSearchQueryGenerator");
    
    let optimizedQuery = query;
    
    
    if (shouldGenerateImageQuery(query, conversationHistory)) {
      try {
        optimizedQuery = await generateImageSearchQuery(query, conversationHistory);
        console.log(`🖼️ Image query optimized: "${query}" → "${optimizedQuery}"`);
      } catch (error: any) {
        console.warn("⚠️ Image query generation failed, using original:", error.message);
       
      }
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
    
    const { 
      generateVideoSearchQuery, 
      shouldGenerateVideoQuery 
    } = await import("./videoSearchQueryGenerator");
    
    let optimizedQuery = query;
    
    
    if (shouldGenerateVideoQuery(query, conversationHistory)) {
      try {
        optimizedQuery = await generateVideoSearchQuery(query, conversationHistory);
        console.log(`🎥 Video query optimized: "${query}" → "${optimizedQuery}"`);
      } catch (error: any) {
        console.warn("⚠️ Video query generation failed, using original:", error.message);
        
      }
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


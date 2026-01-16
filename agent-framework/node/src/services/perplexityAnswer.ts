

import OpenAI from "openai";
import axios from "axios";
import { summarizeDocument } from "./documentSummarizer";
import { getEmbedding, getEmbeddings, cosine } from "../embeddings/embeddingClient";
import { parseStructuredAnswer } from "./answerParser";
import { searchMovies } from "./tmdbService";
import { searchPlaces } from "./placesSearch";

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("Missing OPENAI_API_KEY environment variable");
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}

interface Document {
  title: string;
  url: string;
  content: string;
  summary?: string;
  // Include visual elements from search results automatically
  images?: string[]; // Images from search results 
  thumbnail?: string; // Primary image
  video?: { url: string; thumbnail?: string; title?: string }; // Video from search results
  mapData?: { latitude: number; longitude: number; title: string }; // Map coordinates from search results
}

interface ProductImage {
  url: string;
  title?: string;
  source?: string;
}

// ✅ Unified image interface
interface DomainImage {
  url: string;
  title?: string;
  source?: string;
  domain?: 'product' | 'hotel' | 'place' | 'movie' | 'web';
}

// ✅ PERPLEXITY-STYLE: Structured card interfaces
interface ProductCard {
  id: string; // URL or unique identifier
  title: string;
  price: string;
  rating?: number;
  reviews?: number;
  source: string;
  thumbnail: string;
  link: string;
  description?: string;
}

interface HotelCard {
  id: string;
  name: string;
  price?: string;
  rating?: number;
  reviews?: number;
  address?: string;
  thumbnail: string;
  link?: string;
  description?: string;
  location?: { lat: number; lng: number };
}

interface PlaceCard {
  id: string;
  name: string;
  address?: string;
  rating?: number;
  reviews?: number;
  thumbnail: string;
  link?: string;
  description?: string;
  location?: { lat: number; lng: number };
  type?: string; // e.g., "restaurant", "museum", "park"
}

interface MovieCard {
  id: string; // TMDB ID
  title: string;
  releaseDate?: string;
  rating?: number;
  thumbnail: string; // poster URL
  backdrop?: string;
  description?: string;
  genre?: string[];
}





function mapShoppingResultsToProductCards(shoppingResults: any[]): ProductCard[] {
  if (!Array.isArray(shoppingResults) || shoppingResults.length === 0) {
    return [];
  }

  return shoppingResults.slice(0, 10).map((product: any, index: number) => {
    // ✅ Handle all possible field name variations (like normalizeProduct in serpApiProvider.ts)
    const title = product.title || product.name || product.product_title || product.tag || 'Unknown Product';
    const price = product.price || product.extracted_price || product.current_price || 'Price not available';
    const rating = product.rating ? parseFloat(product.rating.toString()) : undefined;
    const reviews = product.reviews ? parseInt(product.reviews.toString()) : (product.review_count ? parseInt(product.review_count.toString()) : undefined);
    
    // ✅ Extract source/retailer name from link or use provided source
    let source = product.source || 'Unknown Source';
    if (source === 'Unknown Source' && product.link) {
      try {
        const url = new URL(product.link);
        source = url.hostname.replace('www.', '').split('.')[0]; // Extract domain name (e.g., "dillards" from "dillards.com")
        // Capitalize first letter
        source = source.charAt(0).toUpperCase() + source.slice(1);
      } catch (e) {
        // If URL parsing fails, keep Unknown Source
      }
    }
    
    const thumbnail = product.thumbnail || product.image || (product.images?.[0] || '');
    const link = product.link || product.url || product.product_link || '';
    const description = product.snippet || product.description || product.product_description || product.extensions?.join(', ') || product.tag || '';
    
    // ✅ Debug logging for first product to verify field extraction
    if (index === 0) {
      console.log(`✅ First product card extracted:`, {
        title,
        price,
        rating,
        reviews,
        source,
        hasThumbnail: !!thumbnail,
        hasLink: !!link,
        hasDescription: !!description,
      });
    }
    
    return {
      id: link || `product-${index}`,
      title: title,
      price: price,
      rating: rating,
      reviews: reviews,
      source: source,
      thumbnail: thumbnail,
      link: link,
      description: description,
    };
  });
}

function mapHotelResultsToHotelCards(hotelResults: any[]): HotelCard[] {
  if (!Array.isArray(hotelResults) || hotelResults.length === 0) {
    return [];
  }

  return hotelResults.slice(0, 10).map((hotel: any, index: number) => ({
    id: hotel.link || hotel.hotel_id || hotel.property_id || `hotel-${index}`,
    name: hotel.name || hotel.title || 'Unknown Hotel',
    price: hotel.price || hotel.rate || hotel.rate_per_night || undefined,
    rating: hotel.rating ? parseFloat(hotel.rating.toString()) : undefined,
    reviews: hotel.reviews ? parseInt(hotel.reviews.toString()) : undefined,
    address: hotel.address || hotel.location || (hotel.address_lines ? hotel.address_lines.join(', ') : undefined) || undefined,
    thumbnail: hotel.thumbnail || hotel.image || hotel.photo || '',
    link: hotel.link || hotel.website || undefined,
    description: hotel.description || hotel.snippet || undefined,
    location: hotel.gps_coordinates ? {
      lat: hotel.gps_coordinates.latitude,
      lng: hotel.gps_coordinates.longitude,
    } : hotel.coordinates ? {
      lat: hotel.coordinates.latitude || hotel.coordinates.lat,
      lng: hotel.coordinates.longitude || hotel.coordinates.lng,
    } : undefined,
  }));
}

function mapPlaceResultsToPlaceCards(placeResults: any[]): PlaceCard[] {
  if (!Array.isArray(placeResults) || placeResults.length === 0) {
    return [];
  }

  return placeResults.slice(0, 10).map((place: any, index: number) => ({
    id: place.place_id || (place.gps_coordinates ? `${place.gps_coordinates.latitude}-${place.gps_coordinates.longitude}` : `place-${index}`),
    name: place.title || place.name || 'Unknown Place',
    address: place.address || (place.address_lines ? (Array.isArray(place.address_lines) ? place.address_lines.join(', ') : place.address_lines) : undefined) || undefined,
    rating: place.rating ? parseFloat(place.rating.toString()) : undefined,
    reviews: place.reviews ? parseInt(place.reviews.toString()) : undefined,
    thumbnail: place.thumbnail || place.image || '',
    link: place.website || place.gmaps_link || place.url || undefined,
    description: place.snippet || place.description || undefined,
    location: place.gps_coordinates ? {
      lat: place.gps_coordinates.latitude,
      lng: place.gps_coordinates.longitude,
    } : place.coordinates ? {
      lat: place.coordinates.lat || place.coordinates.latitude,
      lng: place.coordinates.lng || place.coordinates.longitude,
    } : undefined,
    type: place.type || place.category || undefined,
  }));
}

/**
 * ✅ Map Google Places API results to PlaceCard format
 * Used when SerpAPI doesn't return place results but Google Places API does
 */
function mapGooglePlacesToPlaceCards(googlePlacesResults: any[]): PlaceCard[] {
  if (!Array.isArray(googlePlacesResults) || googlePlacesResults.length === 0) {
    return [];
  }

  return googlePlacesResults.slice(0, 10).map((place: any, index: number) => {
    // Google Places API returns: name, type, rating (string), location (string), description, image_url, images, geo, website, phone
    const geo = place.geo || (place.latitude && place.longitude ? { latitude: place.latitude, longitude: place.longitude } : null);
    
    return {
      id: geo ? `${geo.latitude}-${geo.longitude}` : `google-place-${index}`,
      name: place.name || 'Unknown Place',
      address: place.location || undefined, // Google Places returns location as string
      rating: place.rating ? parseFloat(place.rating.toString()) : undefined,
      reviews: undefined, // Google Places API doesn't return review count in this format
      thumbnail: place.image_url || (place.images && place.images.length > 0 ? place.images[0] : ''),
      link: place.website || undefined,
      description: place.description || undefined,
      location: geo ? {
        lat: geo.latitude || geo.lat,
        lng: geo.longitude || geo.lng,
      } : undefined,
      type: place.type || undefined,
    };
  });
}

// ✅ TMDB integration enabled - maps TMDB search results to MovieCard format
function mapMovieResultsToMovieCards(movieResults: any[]): MovieCard[] {
  if (!Array.isArray(movieResults) || movieResults.length === 0) {
    return [];
  }

  return movieResults.slice(0, 10).map((movie: any) => ({
    id: movie.id ? movie.id.toString() : 'unknown',
    title: movie.title || movie.name || 'Unknown Movie',
    releaseDate: movie.release_date || undefined,
    rating: movie.vote_average ? parseFloat(movie.vote_average.toString()) : undefined,
    thumbnail: movie.poster_path ? `https://image.tmdb.org/t/p/w500${movie.poster_path}` : '',
    backdrop: movie.backdrop_path ? `https://image.tmdb.org/t/p/w1280${movie.backdrop_path}` : undefined,
    description: movie.overview || undefined,
    genre: movie.genre_ids ? [] : undefined,
  }));
}

/**
 * ✅ LIGHTWEIGHT DOMAIN DETECTION
 * Fast regex-based detection (like answer planning) to decide which APIs to call
 * Returns array of domains that match the query
 */
export type Domain = 'movie' | 'place' | 'hotel' | 'product' | 'restaurant' | 'flight';

export function detectDomains(query: string): Domain[] {
  const q = query.toLowerCase().trim();
  const domains: Domain[] = [];
  
  // Movie detection (high confidence keywords)
  if (
    /\b(movie|film|cinema|actor|director|watch|streaming|oscar|box office|trailer|cast|plot|review|imdb|rotten tomatoes)\b/.test(q) ||
    /\b(movies? (about|with|starring|directed by|from|in|to watch|recommendations?))\b/.test(q) ||
    /\b(best movies?|top movies?|movies? (2024|2025|2023)|watch|stream)\b/.test(q)
  ) {
    domains.push('movie');
  }
  
  // Place detection (attractions, landmarks, things to do)
  if (
    /\b(places? to visit|attractions?|landmarks?|things to do|sights?|tourist|monuments?|temples?|museums?|parks?|beaches?|nature)\b/.test(q) ||
    /\b(places? (in|near|around|to see|to explore)|visit|explore|see|tour)\b/.test(q) ||
    /\b(what to (do|see|visit)|where to (go|visit)|top (attractions?|sights?|places?))\b/.test(q)
  ) {
    domains.push('place');
  }
  
  // Hotel detection
  if (
    /\b(hotel|accommodation|stay|lodging|resort|inn|motel|hostel|bed and breakfast|bnb)\b/.test(q) ||
    /\b(hotels? (in|near|at|around|to stay)|where to stay|book (a )?hotel)\b/.test(q)
  ) {
    domains.push('hotel');
  }
  
  // Product/Shopping detection
  if (
    (/\b(buy|shop|purchase|price|\$|under|over|below|above|cheap|expensive|affordable)\b/.test(q) &&
     /\b(shoes?|watch|watches?|bag|bags?|laptop|phone|product|item|shopping)\b/.test(q)) ||
    /\b(best (shoes?|watch|product)|top (shoes?|watch)|(shoes?|watch) (under|below|for))\b/.test(q)
  ) {
    domains.push('product');
  }
  
  // Restaurant detection
  if (
    /\b(restaurant|dining|food|eat|cuisine|dinner|lunch|breakfast|brunch|cafe|bistro|bar|pub)\b/.test(q) ||
    /\b(restaurants? (in|near|at|around)|where to (eat|dine)|best (food|restaurant|pizza|sushi))\b/.test(q)
  ) {
    domains.push('restaurant');
  }
  
  // Flight detection
  if (
    /\b(flight|flights?|airline|airport|fly|flying|ticket|booking|destination)\b/.test(q) ||
    /\b(flights? (to|from|between)|cheap flights?|book (a )?flight|airfare)\b/.test(q)
  ) {
    domains.push('flight');
  }
  
  // Remove duplicates
  return [...new Set(domains)];
}

/**
 * Step 1: Search the web (with query generation)
 * ✅ SIMPLIFIED: Inline retrieval parameters (needsFreshness, needsMultipleSources)
 * Returns both documents and raw response for card extraction
 */
async function searchWeb(
  query: string,
  conversationHistory: any[] = [],
  options?: { needsMultipleSources?: boolean; needsFreshness?: boolean }
): Promise<{ documents: Document[]; rawResponse: any }> {
  const serpKey = process.env.SERPAPI_KEY;
  if (!serpKey) {
    console.warn("⚠️ SERPAPI_KEY not found, skipping web search");
    // ✅ FIX: searchWeb return shape is stable - always return { documents, rawResponse }
    return { documents: [], rawResponse: null };
  }

  try {
    // ✅ SMART: Generate optimized query only when needed (vague queries or with context)
    let searchQuery = query;
    const { generateSearchQuery, shouldGenerateQuery } = await import("./queryGenerator");
    if (shouldGenerateQuery(query, conversationHistory)) {
      try {
        searchQuery = await generateSearchQuery(query, conversationHistory);
        console.log(`🔍 Query generation: "${query}" → "${searchQuery}"`);
      } catch (err: any) {
        console.warn("⚠️ Query generation failed, using original query:", err.message);
        // Fallback to original query on error
      }
    }

    // ✅ SIMPLIFIED: Cap documents based on retrieval options
    // needsMultipleSources = true → 7 docs, false → 5 docs (faster)
    const maxDocs = options?.needsMultipleSources ? 7 : 5;

    const serpUrl = "https://serpapi.com/search.json";
    const params = {
      engine: "google",
      q: searchQuery,
      api_key: serpKey,
      num: maxDocs, // ✅ Retrieval depth: 7 docs for multi-source queries, 5 for simple queries
      hl: "en",
      gl: "us",
      ...(options?.needsFreshness ? { tbs: "qdr:d" } : {}), // ✅ Recent results if freshness needed
    };

    console.log(`🔍 Searching web for: "${query}"${searchQuery !== query ? ` → "${searchQuery}"` : ''}`);
    const response = await axios.get(serpUrl, { params, timeout: 10000 });
    
    const organicResults = response.data.organic_results || [];
    const documents: Document[] = [];

    // ✅ PERPLEXITY-STYLE: Extract images, videos, maps from search results automatically
    for (const result of organicResults.slice(0, maxDocs)) {
      if (result.title && result.link && result.snippet) {
        // Extract images from search result
        const images: string[] = [];
        if (result.thumbnail) images.push(result.thumbnail);
        if (result.images && Array.isArray(result.images)) {
          images.push(...result.images.slice(0, 3)); // Max 3 additional images per result
        }
        
        // Extract video if available
        let video: { url: string; thumbnail?: string; title?: string } | undefined;
        if (result.video) {
          video = {
            url: result.video.link || result.video.url || '',
            thumbnail: result.video.thumbnail,
            title: result.video.title || result.title,
          };
        }
        
        // Extract map coordinates if available
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
          images: images.length > 0 ? images : undefined,
          video: video?.url ? video : undefined,
          mapData: mapData,
        });
      }
    }

    console.log(`✅ Found ${documents.length} web search results`);
    
    // ✅ PERPLEXITY-STYLE: Extract images from shopping_results (metadata only, no text reconstruction)
    const shoppingResults = response.data.shopping_results || [];
    if (shoppingResults.length > 0) {
      console.log(`✅ Found ${shoppingResults.length} shopping results`);
      for (const product of shoppingResults.slice(0, 5)) {
        if (product.title && product.link) {
          // Extract images
          const images: string[] = [];
          if (product.thumbnail) images.push(product.thumbnail);
          if (product.images && Array.isArray(product.images)) {
            images.push(...product.images.slice(0, 3));
          }
          
          documents.push({
            title: product.title,
            url: product.link,
            content: product.snippet || product.description || product.title,
            thumbnail: product.thumbnail,
            images: images.length > 0 ? images : undefined,
          });
        }
      }
    }
    
    // ✅ PERPLEXITY-STYLE: Check for video_results (videos from search)
    const videoResults = response.data.video_results || [];
    if (videoResults.length > 0) {
      console.log(`✅ Found ${videoResults.length} video results`);
      for (const video of videoResults.slice(0, 3)) { // Top 3 videos
        if (video.title && video.link) {
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
    
    // ✅ PERPLEXITY-STYLE: Check for places_results (places with maps)
    const placesResults = response.data.places_results || [];
    if (placesResults.length > 0) {
      console.log(`✅ Found ${placesResults.length} place results`);
      for (const place of placesResults.slice(0, 5)) {
        if (place.title && (place.gps_coordinates || place.coordinates)) {
          const mapData = place.gps_coordinates ? {
            latitude: place.gps_coordinates.latitude,
            longitude: place.gps_coordinates.longitude,
            title: place.title,
          } : place.coordinates ? {
            latitude: place.coordinates.lat || place.coordinates.latitude,
            longitude: place.coordinates.lng || place.coordinates.longitude,
            title: place.title,
          } : undefined;
          
          const images: string[] = [];
          if (place.thumbnail) images.push(place.thumbnail);
          if (place.photos && Array.isArray(place.photos)) {
            place.photos.slice(0, 3).forEach((photo: any) => {
              if (photo.thumbnail || photo.url) images.push(photo.thumbnail || photo.url);
            });
          }
          
          documents.push({
            title: place.title,
            url: place.website || place.url || '',
            content: place.description || place.snippet || place.title,
            thumbnail: place.thumbnail,
            images: images.length > 0 ? images : undefined,
            mapData: mapData,
          });
        }
      }
    }
    
    // ✅ OPTIMIZED: Use snippets directly (like Perplexity) - no URL fetching for speed
    // URL fetching only happens if LLM explicitly generates links (handled in main flow)
    // ✅ FIX: searchWeb return shape is stable
    return { documents, rawResponse: response.data };
  } catch (error: any) {
    console.error("❌ Web search failed:", error.message);
    // ✅ FIX: searchWeb return shape is stable - always return { documents, rawResponse }
    return { documents: [], rawResponse: null };
  }
}

/**
 * ✅ IMPROVEMENT: Fetch full document content from URL (like LangChain)
 */
async function fetchDocumentFromUrl(url: string): Promise<string> {
  try {
    const response = await axios.get(url, {
      timeout: 8000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    });
    
    // Extract text content from HTML
    const html = response.data;
    // Simple text extraction (remove HTML tags)
    const text = html
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '') // Remove scripts
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '') // Remove styles
      .replace(/<[^>]+>/g, ' ') // Remove HTML tags
      .replace(/\s+/g, ' ') // Normalize whitespace
      .trim();
    
    // Limit to first 5000 chars (enough for summarization)
    return text.substring(0, 5000);
  } catch (error: any) {
    console.warn(`⚠️ Failed to fetch document from ${url}:`, error.message);
    return '';
  }
}

/**
 * Step 2: Summarize each document (like LangChain)
 */
async function summarizeDocuments(docs: Document[], query: string): Promise<Document[]> {
  if (docs.length === 0) return [];

  console.log(`📝 Summarizing ${docs.length} documents...`);
  
  const summarized = await Promise.all(
    docs.map(async (doc) => {
      try {
        const summary = await summarizeDocument(doc.content, query);
        return {
          ...doc,
          summary,
        };
      } catch (error: any) {
        console.warn(`⚠️ Failed to summarize "${doc.title}":`, error.message);
        return {
          ...doc,
          summary: doc.content, // Fallback to original
        };
      }
    })
  );

  console.log(`✅ Summarized ${summarized.length} documents`);
  return summarized;
}

/**
 * Step 3: Rerank documents by relevance (using embeddings)
 * ✅ PERPLEXITY-STYLE: Deduplicate sources and ensure diversity before LLM
 * ✅ OPTIMIZED: Skip reranking for simple queries (saves 1-2 seconds)
 */
async function rerankDocuments(query: string, docs: Document[]): Promise<Document[]> {
  if (docs.length === 0) return [];

  // ✅ STEP 1: Deduplicate sources by domain/URL
  const deduplicated: Document[] = [];
  const seenDomains = new Set<string>();
  const seenUrls = new Set<string>();
  
  for (const doc of docs) {
    // Extract domain from URL
    try {
      const urlObj = new URL(doc.url);
      const domain = urlObj.hostname.replace('www.', '');
      
      // Check if we've seen this exact URL
      if (seenUrls.has(doc.url)) {
        continue; // Skip duplicate URL
      }
      
      // Check if we've seen this domain (max 1 per domain for diversity)
      if (seenDomains.has(domain)) {
        continue; // Skip duplicate domain
      }
      
      seenUrls.add(doc.url);
      seenDomains.add(domain);
      deduplicated.push(doc);
    } catch (e) {
      // If URL parsing fails, just check URL uniqueness
      if (!seenUrls.has(doc.url)) {
        seenUrls.add(doc.url);
        deduplicated.push(doc);
      }
    }
  }
  
  console.log(`🔀 Deduplicated: ${docs.length} → ${deduplicated.length} documents`);

  // ✅ OPTIMIZED: Skip reranking for simple queries (saves 1-2 seconds)
  // Simple queries: short, direct questions that don't need semantic reranking
  const isSimpleQuery = (
    query.split(/\s+/).length <= 8 && // Short query
    !/\b(vs|versus|compare|difference|should i|which|recommend)\b/i.test(query) && // Not comparison/decision
    deduplicated.length <= 5 // Small result set
  );

  if (isSimpleQuery) {
    console.log(`⏭️ Skipping reranking for simple query (${deduplicated.length} docs)`);
    return deduplicated.slice(0, 5);
  }

  // ✅ STEP 2: Limit to top 7 for reranking (before embedding computation)
  const limitedDocs = deduplicated.slice(0, 7);
  console.log(`🔀 Reranking ${limitedDocs.length} documents by relevance...`);

  try {
    // ✅ OPTIMIZED: Generate query and doc embeddings in parallel
    const docTexts = limitedDocs.map(doc => doc.summary || doc.content);
    const [queryEmbedding, docEmbeddings] = await Promise.all([
      getEmbedding(query),
      getEmbeddings(docTexts)
    ]);

    // Compute similarity scores
    const scored = limitedDocs.map((doc, i) => {
      const similarity = cosine(queryEmbedding, docEmbeddings[i]);
      return {
        doc,
        similarity,
      };
    });

    // Sort by similarity (highest first) and filter by threshold
    const threshold = 0.3;
    const reranked = scored
      .filter(item => item.similarity > threshold)
      .sort((a, b) => b.similarity - a.similarity)
      .slice(0, 5) // ✅ PERPLEXITY-STYLE: Top 5 most relevant
      .map(item => item.doc);

    console.log(`✅ Reranked: ${reranked.length} documents (threshold: ${threshold}, deduplicated & diverse)`);
    return reranked;
  } catch (error: any) {
    console.error("❌ Reranking failed:", error.message);
    // Fallback: return deduplicated docs
    return deduplicated.slice(0, 5);
  }
}

/**
 * Step 4: Format documents as context (like LangChain)
 */
function formatDocumentsAsContext(docs: Document[]): string {
  return docs
    .map((doc, index) => {
      const content = doc.summary || doc.content;
      return `${index + 1}. ${doc.title}\n${content}`;
    })
    .join('\n\n');
}

/**
 * Step 5: Generate Perplexity-style answer
 */
async function generateAnswer(
  query: string,
  context: string,
  conversationHistory: any[]
): Promise<string> {
  const system = `You are an AI assistant skilled in web search and crafting detailed, engaging, and well-structured answers. You excel at summarizing web pages and extracting relevant information to create professional, blog-style responses.

Answer Requirements:
- Address the query thoroughly using the provided context
- Use clear section headings (plain text, on their own line)
- Maintain a neutral, journalistic tone
- Cite every fact with [number] notation from the context sources
- Write in plain text only (no markdown symbols)

Format:
- Start with an introduction
- Use section headings on their own lines
- End with a conclusion

Citations:
- Cite every sentence with [number] from context sources
- Example: "The Eiffel Tower is one of the most visited landmarks[1]."

<context>
${context}
</context>

Current date & time in ISO format (UTC timezone) is: ${new Date().toISOString()}.`;

  const messages: any[] = [
    { role: "system", content: system }
  ];

  // Add conversation history
  if (conversationHistory && conversationHistory.length > 0) {
    for (const h of conversationHistory) {
      if (h.query) {
        messages.push({ role: "user", content: h.query });
      }
      if (h.summary || h.answer) {
        messages.push({ role: "assistant", content: h.summary || h.answer || "" });
      }
    }
  }

  // Add current query
  messages.push({ role: "user", content: query });

  const response = await getClient().chat.completions.create({
    model: "gpt-4o-mini",
    temperature: 0.3,
    max_tokens: 800, // ✅ OPTIMIZED: Reduced for faster generation (250-300 words)
    messages: messages
  });

  return response.choices[0]?.message?.content || "";
}

/**
 * ✅ NEW: Generate follow-up suggestions separately (after answer is generated)
 * This ensures clean answer text and better contextual follow-ups
 */
async function generateFollowUpSuggestions(
  query: string,
  answerSummary: string
): Promise<string[]> {
  try {
    const prompt = `Given the user's query and the answer provided, generate 3 relevant follow-up questions that would help the user explore the topic further.

User Query: ${query}

Answer Summary: ${answerSummary.substring(0, 500)}${answerSummary.length > 500 ? '...' : ''}

Return ONLY a JSON array of exactly 3 follow-up questions, nothing else:
["Question 1", "Question 2", "Question 3"]`;

    const response = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.7, // Slightly higher for variety
      max_tokens: 150, // Very lightweight
      messages: [
        { 
          role: "system", 
          content: "You are a helpful assistant that generates relevant follow-up questions. Always return a valid JSON array with exactly 3 questions." 
        },
        { role: "user", content: prompt }
      ]
    });

    const content = response.choices[0]?.message?.content?.trim() || "[]";
    
    // Try to extract JSON array from response
    let jsonStr = content;
    
    // If response contains markdown code blocks, extract JSON
    const jsonMatch = content.match(/```(?:json)?\s*(\[[\s\S]*?\])\s*```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1];
    } else if (content.includes('[') && content.includes(']')) {
      // Extract array from text
      const arrayMatch = content.match(/\[[\s\S]*?\]/);
      if (arrayMatch) {
        jsonStr = arrayMatch[0];
      }
    }
    
    try {
      const parsed = JSON.parse(jsonStr);
      if (Array.isArray(parsed)) {
        const suggestions = parsed
          .filter((q: any) => typeof q === 'string' && q.trim().length > 0)
          .slice(0, 3)
          .map((q: string) => q.trim());
        
        if (suggestions.length >= 3) {
          console.log(`✅ Generated ${suggestions.length} follow-up suggestions separately`);
          return suggestions;
        }
      }
    } catch (e) {
      console.warn("⚠️ Failed to parse follow-up suggestions JSON:", e);
    }
    
    // Fallback: Generate simple contextual follow-ups
    console.warn("⚠️ Using fallback follow-up suggestions");
    const queryWords = query.split(/\s+/).slice(0, 5).join(' ');
    return [
      `Tell me more about ${queryWords}`,
      `What are the key points about ${queryWords}?`,
      `How does ${queryWords} work?`
    ];
  } catch (error: any) {
    console.error("❌ Error generating follow-up suggestions:", error.message);
    // Fallback on error
    const queryWords = query.split(/\s+/).slice(0, 5).join(' ');
    return [
      `Tell me more about ${queryWords}`,
      `What are the key points about ${queryWords}?`,
      `How does ${queryWords} work?`
    ];
  }
}

/**
 * ✅ IMPROVEMENT: Generate answer with streaming (like LangChain)
 */
async function generateAnswerStream(
  query: string,
  context: string,
  conversationHistory: any[],
  res: any,
  sources?: Array<{ title: string; link: string }>,
  // Removed answerPlan parameter - no longer needed
): Promise<string> {
  const { SSE } = await import("../utils/sse");
  const sse = new SSE(res);
  sse.init();

  const system = `You are an AI assistant skilled in web search and crafting detailed, engaging, and well-structured answers. You excel at summarizing web pages and extracting relevant information to create professional, blog-style responses.

Answer Requirements:
- Address the query thoroughly using the provided context
- Use clear section headings (plain text, on their own line)
- Maintain a neutral, journalistic tone
- Cite every fact with [number] notation from the context sources
- Write in plain text only (no markdown symbols)

Format:
- Start with an introduction
- Use section headings on their own lines
- End with a conclusion

Citations:
- Cite every sentence with [number] from context sources
- Example: "The Eiffel Tower is one of the most visited landmarks[1]."

<context>
${context}
</context>

Current date & time in ISO format (UTC timezone) is: ${new Date().toISOString()}.`;

  const messages: any[] = [
    { role: "system", content: system }
  ];

  // Add conversation history
  if (conversationHistory && conversationHistory.length > 0) {
    for (const h of conversationHistory) {
      if (h.query) {
        messages.push({ role: "user", content: h.query });
      }
      if (h.summary || h.answer) {
        messages.push({ role: "assistant", content: h.summary || h.answer || "" });
      }
    }
  }

  // Add current query
  messages.push({ role: "user", content: query });

  let fullAnswer = "";
  let buffer = "";
  let firstSentenceSent = false;

  try {
    const stream = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      stream: true,
      temperature: 0.3,
      max_tokens: 1000, // ✅ OPTIMIZED: Reduced for faster generation
      messages: messages
    });

    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;
      if (delta) {
        fullAnswer += delta;
        buffer += delta;

        // Send first sentence immediately (verdict/stance)
        if (!firstSentenceSent && (buffer.includes('.') || buffer.includes('?') || buffer.length > 100)) {
          const firstSentenceEnd = buffer.indexOf('.');
          if (firstSentenceEnd > 0) {
            const firstSentence = buffer.substring(0, firstSentenceEnd + 1);
            sse.send("verdict", firstSentence);
            buffer = buffer.substring(firstSentenceEnd + 1);
            firstSentenceSent = true;
          } else if (buffer.length > 100) {
            sse.send("verdict", buffer.substring(0, 100));
            buffer = buffer.substring(100);
            firstSentenceSent = true;
          }
        }

        // Send remaining content
        if (firstSentenceSent && buffer.length > 50) {
          sse.send("message", buffer);
          buffer = "";
        }
      }
    }

    // Send remaining buffer
    if (buffer.length > 0) {
      sse.send("message", buffer);
    }

    // Parse and send final data
    const parsed = parseStructuredAnswer(fullAnswer);
    
    // ✅ FIX: Don't send end event here - wait for cards/images to be extracted first
    // The end event will be sent in generatePerplexityAnswer after cards/images are ready
    // This ensures Flutter receives all data in the end event

    return fullAnswer;
  } catch (error: any) {
    console.error("❌ Streaming failed:", error);
    const fallback = `Here's a helpful overview regarding "${query}".`;
    sse.send("message", fallback);
    sse.send("end", {
      intent: "answer",
      summary: fallback,
      answer: fallback,
      sections: [],
      sources: [],
      followUpSuggestions: [],
    });
    sse.close();
    return fallback;
  }
}

// ✅ DELETED: All extract*Card functions - search is the only source of truth

// ✅ REMOVED: normalizeUI() function - UI gating moved to frontend (Perplexity-style)

/**
 * Main function: LangChain-style Perplexity answer generation
 */
/**
 * ✅ PERPLEXITY-STYLE: Semantic Understanding (BEFORE search)
 * Understands query intent, entities, context, and optimizes search parameters
 */
interface SemanticUnderstanding {
  intent: string; // Primary intent (hotel, product, place, movie, restaurant, flight, general)
  entities: {
    location?: string; // Normalized location (e.g., "Bangkok", "New York")
    brand?: string; // Brand name if mentioned
    category?: string; // Product/service category
    price?: string; // Price range or modifier (e.g., "cheap", "luxury", "under $100")
    amenities?: string[]; // Features/amenities (e.g., ["pool", "gym", "wifi"])
  };
  queryRefinement: string; // Optimized search query
  needsFreshness: boolean; // Does query need recent information?
  needsMultipleSources: boolean; // Does query benefit from diverse sources?
  isRefinement: boolean; // Is this a follow-up/refinement query?
  detectedDomains: Domain[]; // Detected domains for API calls
}

async function understandQuerySemantically(
  query: string,
  conversationHistory: any[] = []
): Promise<SemanticUnderstanding> {
  try {
    const client = getClient();
    
    // Format conversation history
    const historyText = conversationHistory.length > 0
      ? conversationHistory
          .slice(-5) // Last 5 messages
          .map((msg: any) => `Q: ${msg.query || ""}\nA: ${msg.summary || msg.answer || ""}`)
          .join("\n\n")
      : "";

    const prompt = `You are a semantic understanding system for a search assistant (like Perplexity).

Analyze the user's query and extract ALL relevant information.

User Query: "${query}"
${historyText ? `\n\nConversation History:\n${historyText}` : ""}

Extract and return ONLY a JSON object with this exact structure:
{
  "intent": "primary intent (hotel, product, place, movie, restaurant, flight, or general)",
  "entities": {
    "location": "normalized location name or null (e.g., 'Bangkok', 'New York', 'Salt Lake City')",
    "brand": "brand name or null (e.g., 'Nike', 'Apple')",
    "category": "product/service category or null (e.g., 'shoes', 'hotels', 'restaurants')",
    "price": "price modifier or null (e.g., 'cheap', 'luxury', 'under $100', '5-star')",
    "amenities": ["array of features/amenities or empty array (e.g., ['pool', 'gym', 'wifi'])"]
  },
  "queryRefinement": "optimized search query (2-8 words, natural and searchable)",
  "needsFreshness": true/false,
  "needsMultipleSources": true/false,
  "isRefinement": true/false,
  "detectedDomains": ["array of domains: 'movie', 'place', 'hotel', 'product', 'restaurant', 'flight' or empty"]
}

CRITICAL RULES:
1. Intent: Determine primary intent. If ambiguous, choose the most likely based on keywords and context.
2. Location: Normalize to standard format (e.g., "bangkok" → "Bangkok", "NYC" → "New York")
3. Query Refinement: Create a natural, searchable query that captures the essence. If query is vague, infer from conversation history.
4. needsFreshness: true if query mentions time-sensitive terms (now, current, latest, recent, today, 2024, 2025, news, update, best, top, recommend)
5. needsMultipleSources: true if query is comparison/decision (vs, versus, compare, comparison, should i, worth it, which is better, pick, choose)
6. isRefinement: true if query is vague/follow-up (e.g., "cheaper ones", "luxury ones", "what about X") AND has conversation history
7. detectedDomains: Include all relevant domains (can be multiple, e.g., ["hotel", "restaurant"] for "hotels and restaurants in Paris")
8. If query is a follow-up without explicit location, infer location from conversation history
9. If query explicitly mentions a different location than previous, use the new location (don't merge)

Examples:
- Query: "hotels in bangkok" → { intent: "hotel", entities: { location: "Bangkok" }, queryRefinement: "hotels in Bangkok", detectedDomains: ["hotel"] }
- Query: "cheaper ones" (previous: "hotels in Miami") → { intent: "hotel", entities: { location: "Miami", price: "cheap" }, queryRefinement: "cheap hotels in Miami", isRefinement: true, detectedDomains: ["hotel"] }
- Query: "best restaurants and hotels in Paris" → { intent: "general", entities: { location: "Paris" }, queryRefinement: "best restaurants and hotels in Paris", detectedDomains: ["restaurant", "hotel"] }
- Query: "movies about space" → { intent: "movie", entities: { category: "space" }, queryRefinement: "movies about space", detectedDomains: ["movie"] }

Return ONLY the JSON object, no other text.`;

    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.3,
      max_tokens: 500,
    });

    const content = response.choices[0]?.message?.content?.trim() || "{}";
    
    // Extract JSON from response (handle markdown code blocks)
    let jsonStr = content;
    const jsonMatch = content.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1];
    }

    const understanding = JSON.parse(jsonStr) as SemanticUnderstanding;

    // Validate and set defaults
    return {
      intent: understanding.intent || "general",
      entities: {
        location: understanding.entities?.location || undefined,
        brand: understanding.entities?.brand || undefined,
        category: understanding.entities?.category || undefined,
        price: understanding.entities?.price || undefined,
        amenities: understanding.entities?.amenities || [],
      },
      queryRefinement: understanding.queryRefinement || query,
      needsFreshness: understanding.needsFreshness ?? false,
      needsMultipleSources: understanding.needsMultipleSources ?? false,
      isRefinement: understanding.isRefinement ?? false,
      detectedDomains: understanding.detectedDomains || [],
    };
  } catch (error: any) {
    console.warn("⚠️ Semantic understanding failed, using fallback:", error.message);
    
    // Fallback to regex-based detection
    const detectedDomains = detectDomains(query);
    const queryWords = query.split(/\s+/).length;
    
    return {
      intent: detectedDomains[0] || "general",
      entities: {},
      queryRefinement: query,
      needsFreshness: /\b(now|current|latest|recent|today|2024|2025|best|top|recommend)\b/i.test(query),
      needsMultipleSources: /\b(vs|versus|compare|which|should i|pick|choose)\b/i.test(query) || queryWords > 8,
      isRefinement: false,
      detectedDomains,
    };
  }
}

export async function generatePerplexityAnswer(
  query: string,
  conversationHistory: any[] = [],
  shouldStream: boolean = false,
  res?: any // Response object for streaming
): Promise<{
  answer: string;
  summary: string;
  sections: Array<{ title: string; content: string; type?: string }>;
  sources: Array<{ title: string; link: string }>;
  followUpSuggestions: string[];
  searchImages: DomainImage[]; // ✅ RENAMED: All images from search (web, products, hotels, places, movies)
  videos?: Array<{ url: string; thumbnail?: string; title?: string }>;
  mapPoints?: Array<{ latitude: number; longitude: number; title: string }>;
  cards: {
    products: ProductCard[];
    hotels: HotelCard[];
    places: PlaceCard[];
    movies: MovieCard[];
  };
}> {
  try {
    // ✅ PERPLEXITY-STYLE: Step 0 - Semantic Understanding (BEFORE search)
    console.log(`🧠 Understanding query semantically: "${query}"`);
    const understanding = await understandQuerySemantically(query, conversationHistory);
    console.log(`✅ Semantic understanding:`, {
      intent: understanding.intent,
      location: understanding.entities.location,
      queryRefinement: understanding.queryRefinement,
      needsFreshness: understanding.needsFreshness,
      needsMultipleSources: understanding.needsMultipleSources,
      detectedDomains: understanding.detectedDomains,
    });

    // Step 1: Search web (using semantic understanding)
    const { documents, rawResponse } = await searchWeb(understanding.queryRefinement, conversationHistory, {
      needsMultipleSources: understanding.needsMultipleSources,
      needsFreshness: understanding.needsFreshness,
    });

    if (documents.length === 0) {
      // ✅ FIX: Cards extracted only after successful search - if no documents, cards must be empty
      // ✅ PERPLEXITY-STYLE: If search returns nothing, return text-only answer
      const answer = await generateAnswer(query, "", conversationHistory);
      const parsed = parseStructuredAnswer(answer);
      
      // Generate follow-ups even for fallback case
      const fallbackFollowUps = await generateFollowUpSuggestions(
        query,
        parsed.summary || parsed.answer.substring(0, 500)
      );
      
      return {
        answer: parsed.answer,
        summary: parsed.summary,
        sections: parsed.sections,
        sources: [],
        followUpSuggestions: fallbackFollowUps, // ✅ Use separately generated follow-ups
        searchImages: [],
        videos: [],
        mapPoints: [],
        cards: {
          products: [],
          hotels: [],
          places: [],
          movies: [],
        },
      };
    }

    // ✅ FIX: Cards extracted only after successful search - only extract if documents.length > 0
    // ✅ PERPLEXITY-STYLE: Extract structured cards from search results (after confirming search success)
    const productCards = rawResponse?.shopping_results 
      ? mapShoppingResultsToProductCards(rawResponse.shopping_results)
      : [];
    
    const hotelCards = rawResponse?.properties || rawResponse?.hotels || rawResponse?.hotels_results
      ? mapHotelResultsToHotelCards(rawResponse.properties || rawResponse.hotels || rawResponse.hotels_results)
      : [];
    
    const placeCards = rawResponse?.places_results || rawResponse?.local_results
      ? mapPlaceResultsToPlaceCards(rawResponse.places_results || rawResponse.local_results)
      : [];
    
    // ✅ PERPLEXITY-STYLE: Use domains from semantic understanding
    const detectedDomains = understanding.detectedDomains.length > 0 
      ? understanding.detectedDomains 
      : detectDomains(query); // Fallback to regex if semantic understanding didn't detect domains
    console.log(`🎯 Detected domains: ${detectedDomains.join(', ') || 'none (web search only)'}`);
    
    // ✅ MOVIE API: Only call TMDB if movie domain detected
    let movieCards: MovieCard[] = [];
    if (detectedDomains.includes('movie')) {
      try {
        console.log(`🎬 Calling TMDB API for movie query: "${query}"`);
        const tmdbResponse = await searchMovies(query, 1);
        if (tmdbResponse?.results && Array.isArray(tmdbResponse.results) && tmdbResponse.results.length > 0) {
          movieCards = mapMovieResultsToMovieCards(tmdbResponse.results);
          console.log(`✅ TMDB returned ${movieCards.length} movie cards`);
        } else {
          console.log(`ℹ️ TMDB returned no results for: "${query}"`);
        }
      } catch (error: any) {
        // API key missing or API error - silently return empty array
        if (error.message?.includes("TMDB_API_KEY") || error.message?.includes("TMDB API error")) {
          console.log(`ℹ️ TMDB API key not configured, skipping movie search`);
        } else {
          console.warn("⚠️ Movie search failed:", error.message);
        }
      }
    } else {
      console.log(`⏭️ Skipping TMDB (not a movie query)`);
    }
    
    // ✅ PLACE API: Only call Google Places API if place domain detected
    // Note: Places are also extracted from SerpAPI's places_results above
    // Google Places API is called as a fallback if SerpAPI doesn't return results
    let enrichedPlaceCards = placeCards;
    if (detectedDomains.includes('place') && placeCards.length === 0) {
      // Only call Google Places API if SerpAPI didn't return place results
      try {
        console.log(`📍 Calling Google Places API for place query: "${query}"`);
        const googlePlacesResults = await searchPlaces(query);
        if (googlePlacesResults && Array.isArray(googlePlacesResults) && googlePlacesResults.length > 0) {
          enrichedPlaceCards = mapGooglePlacesToPlaceCards(googlePlacesResults);
          console.log(`✅ Google Places returned ${enrichedPlaceCards.length} place cards`);
        } else {
          console.log(`ℹ️ Google Places returned no results for: "${query}"`);
        }
      } catch (error: any) {
        if (error.message?.includes("GOOGLE_MAPS_BACKEND_KEY") || error.message?.includes("Places API")) {
          console.log(`ℹ️ Google Places API key not configured, skipping places search`);
        } else {
          console.warn("⚠️ Google Places search failed:", error.message);
        }
      }
    } else if (detectedDomains.includes('place') && placeCards.length > 0) {
      console.log(`ℹ️ Using SerpAPI place results (${placeCards.length} cards), skipping Google Places API`);
    } else {
      console.log(`⏭️ Skipping Google Places API (not a place query)`);
    }
    
    // ✅ FUTURE: Add more conditional API calls here as needed
    // if (detectedDomains.includes('hotel')) {
    //   // Call hotel-specific API
    // }
    // if (detectedDomains.includes('restaurant')) {
    //   // Call restaurant-specific API
    // }
    // if (detectedDomains.includes('flight')) {
    //   // Call flight-specific API
    // }

    // Step 2: Summarize each document
    const summarizedDocs = await summarizeDocuments(documents, query);

    // Step 3: Rerank by relevance
    const rerankedDocs = await rerankDocuments(query, summarizedDocs);

    // Step 4: Format as context
    const context = formatDocumentsAsContext(rerankedDocs);

    // Step 5: Extract sources from reranked documents (before streaming)
    const sources = rerankedDocs.map(doc => ({
      title: doc.title,
      link: doc.url,
    }));

    // Step 6: Generate answer (with streaming support)
    let answerText: string;
    if (shouldStream && res) {
      answerText = await generateAnswerStream(query, context, conversationHistory, res, sources);
    } else {
      answerText = await generateAnswer(query, context, conversationHistory);
    }

    // Step 7: Parse structured answer (no follow-ups in answer text anymore)
    const parsed = parseStructuredAnswer(answerText);
    
    // Step 8: Generate follow-up suggestions separately (clean, contextual)
    console.log("🔄 Generating follow-up suggestions separately...");
    const followUpSuggestions = await generateFollowUpSuggestions(
      query,
      parsed.summary || parsed.answer.substring(0, 500)
    );
    console.log(`✅ Generated ${followUpSuggestions.length} follow-up suggestions`);

    // ✅ PERPLEXITY-STYLE: Extract ALL media from search results (search-first, no LLM dependency)
    // Cards already extracted above from structured search results
    let allImages: DomainImage[] = [];
    let allVideos: Array<{ url: string; thumbnail?: string; title?: string }> = [];
    let allMapPoints: Array<{ latitude: number; longitude: number; title: string }> = [];
    
    // ✅ STEP 1: Extract images, videos, maps from search documents (search-first)
    for (const doc of rerankedDocs) {
      // Extract images from document metadata
      if (doc.images && Array.isArray(doc.images)) {
        for (const imgUrl of doc.images) {
          allImages.push({
            url: imgUrl,
            title: doc.title,
            source: doc.url,
            domain: 'web',
          });
        }
      } else if (doc.thumbnail) {
        allImages.push({
          url: doc.thumbnail,
          title: doc.title,
          source: doc.url,
          domain: 'web',
        });
      }
      
      // Extract videos from document metadata
      if (doc.video && doc.video.url) {
        allVideos.push(doc.video);
      }
      
      // Extract map coordinates from document metadata
      if (doc.mapData) {
        allMapPoints.push(doc.mapData);
      }
      
      // ✅ PERPLEXITY-STYLE: Cards come ONLY from structured search results, never from text reconstruction
    }
    
    // ✅ FIX: Images are deduplicated before capping
    // Deduplicate by URL
    const seenUrls = new Set<string>();
    const deduplicatedImages: DomainImage[] = [];
    for (const img of allImages) {
      if (!seenUrls.has(img.url)) {
        seenUrls.add(img.url);
        deduplicatedImages.push(img);
      }
    }
    // Cap at 20 total after deduplication
    allImages = deduplicatedImages.slice(0, 20);
    
    console.log(`✅ SEARCH-FIRST: Extracted ${allImages.length} images, ${allVideos.length} videos, ${allMapPoints.length} map points, ${productCards.length} product cards, ${hotelCards.length} hotel cards, ${placeCards.length} place cards, ${movieCards.length} movie cards from search results`);
    console.log(`✅ Generated Perplexity-style answer: ${parsed.sections.length} sections, ${sources.length} sources, ${followUpSuggestions.length} follow-ups, ${allImages.length} images, ${allVideos.length} videos, ${allMapPoints.length} map points`);

    // ✅ FIX: Filter out FOLLOW_UP_SUGGESTIONS sections before sending/returning
    const filteredSections = parsed.sections.filter(
      (section: any) => !section.title?.toUpperCase().includes('FOLLOW_UP_SUGGESTIONS')
    );
    
    // If streaming, send cards and images in a separate event after extraction
    if (shouldStream && res) {
      const { SSE } = await import("../utils/sse");
      const sse = new SSE(res);
      // ✅ FIX: Don't call init() here - it's already initialized in generateAnswerStream
      // Just reuse the existing connection
      
      // ✅ FIX: Send everything in end event (sections, sources, cards, images, videos, maps)
      // This ensures Flutter receives all data at once and can update the session properly
      sse.send("end", {
        intent: "answer",
        summary: parsed.summary,
        answer: parsed.answer,
        sections: filteredSections, // ✅ Use filtered sections
        sources: sources,
        followUpSuggestions: followUpSuggestions, // ✅ Use separately generated follow-ups
        cards: {
          products: productCards,
          hotels: hotelCards,
          places: enrichedPlaceCards,
          movies: movieCards,
        },
        destination_images: allImages.map((img: DomainImage) => img.url),
        videos: allVideos,
        mapPoints: allMapPoints,
      });
      
      // ✅ FIX: Close connection after sending all data
      sse.close();
      
      return {
        answer: parsed.answer,
        summary: parsed.summary,
        sections: filteredSections, // ✅ Use filtered sections
        sources: sources,
        followUpSuggestions: followUpSuggestions, // ✅ Use separately generated follow-ups
        searchImages: allImages,
        videos: allVideos,
        mapPoints: allMapPoints,
        cards: {
          products: productCards,
          hotels: hotelCards,
          places: enrichedPlaceCards,
          movies: movieCards,
        },
      };
    }

    return {
      answer: parsed.answer,
      summary: parsed.summary,
      sections: filteredSections, // ✅ Use filtered sections
      sources,
      followUpSuggestions: followUpSuggestions, // ✅ Use separately generated follow-ups
      searchImages: allImages,
      videos: allVideos,
      mapPoints: allMapPoints,
      cards: {
        products: productCards,
        hotels: hotelCards,
        places: enrichedPlaceCards,
        movies: movieCards,
      },
    };
  } catch (error: any) {
    console.error("❌ Perplexity answer generation failed:", error);
    // Fallback - no images for error cases
    return {
      answer: `Here's a helpful overview regarding "${query}".`,
      summary: `Here's a helpful overview regarding "${query}".`,
      sections: [],
      sources: [],
      followUpSuggestions: [],
      searchImages: [], // No images for error fallback
      cards: {
        products: [],
        hotels: [],
        places: [],
        movies: [],
      },
    };
  }
}


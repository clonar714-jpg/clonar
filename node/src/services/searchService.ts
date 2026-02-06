/**
 * Stub search service so /api/search, /api/images, /api/videos routes load.
 * Replace with real search (e.g. SearxNG, Bing, etc.) for production.
 */

export interface SearchOptions {
  needsMultipleSources?: boolean;
  needsFreshness?: boolean;
  maxResults?: number;
  searchType?: string;
}

export interface SearchDocument {
  title: string;
  url: string;
  snippet?: string;
}

export interface SearchResult {
  documents: SearchDocument[];
  images?: unknown[];
  videos?: unknown[];
}

export async function search(
  _query: string,
  _conversationHistory: unknown[],
  _options?: SearchOptions
): Promise<SearchResult> {
  return { documents: [] };
}

export async function searchImages(
  _query: string,
  _conversationHistory: unknown[],
  _options?: { maxResults?: number }
): Promise<unknown[]> {
  return [];
}

export async function searchVideos(
  _query: string,
  _conversationHistory: unknown[],
  _options?: { maxResults?: number }
): Promise<unknown[]> {
  return [];
}

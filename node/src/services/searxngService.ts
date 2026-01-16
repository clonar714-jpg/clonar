/**
 * ✅ PERPLEXICA-STYLE: SearXNG Search Service
 * Provides academic search functionality using SearXNG
 */

import { getSearxngURL } from '../config/serverRegistry';

interface SearxngSearchOptions {
  categories?: string[];
  engines?: string[];
  language?: string;
  pageno?: number;
}

interface SearxngSearchResult {
  title: string;
  url: string;
  img_src?: string;
  thumbnail_src?: string;
  thumbnail?: string;
  content?: string;
  author?: string;
  iframe_src?: string;
}

/**
 * Search using SearXNG
 * @param query - Search query
 * @param opts - Search options (engines, categories, etc.)
 * @returns Search results and suggestions
 */
export const searchSearxng = async (
  query: string,
  opts?: SearxngSearchOptions,
): Promise<{ results: SearxngSearchResult[]; suggestions: string[] }> => {
  const searxngURL = getSearxngURL();
  
  if (!searxngURL) {
    console.warn('⚠️ SearXNG URL not configured, returning empty results');
    return { results: [], suggestions: [] };
  }

  try {
    const url = new URL(`${searxngURL}/search?format=json`);
    url.searchParams.append('q', query);

    if (opts) {
      Object.keys(opts).forEach((key) => {
        const value = opts[key as keyof SearxngSearchOptions];
        if (Array.isArray(value)) {
          url.searchParams.append(key, value.join(','));
          return;
        }
        if (value !== undefined) {
          url.searchParams.append(key, value as string);
        }
      });
    }

    const res = await fetch(url.toString());
    if (!res.ok) {
      throw new Error(`SearXNG search failed: ${res.statusText}`);
    }

    const data = await res.json();

    const results: SearxngSearchResult[] = data.results || [];
    const suggestions: string[] = data.suggestions || [];

    return { results, suggestions };
  } catch (error: any) {
    console.error('❌ SearXNG search error:', error.message);
    return { results: [], suggestions: [] };
  }
};


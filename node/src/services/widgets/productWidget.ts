/**
 * ✅ Agent-Style Product Widget
 * Uses LLM to extract intent and fetches from multiple APIs (SerpAPI Shopping, Google Shopping)
 * Merges all sources with deduplication - no fallback needed
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';
import { search } from '../searchService';
import z from 'zod';

// Intent extraction schema
const productIntentSchema = z.object({
  productName: z.string().nullable().describe('Product name or title'),
  brand: z.string().nullable().optional().describe('Brand name (e.g., Nike, Apple, Samsung)'),
  category: z.string().nullable().optional().describe('Product category (e.g., shoes, laptop, phone, headphones)'),
  priceRange: z.object({
    min: z.number().nullable().optional(),
    max: z.number().nullable().optional(),
  }).nullable().optional().describe('Price range'),
  gender: z.enum(['men', 'women', 'unisex']).nullable().optional().describe('Gender-specific product'),
  color: z.string().nullable().optional().describe('Product color'),
  features: z.array(z.string()).nullable().optional().describe('Desired features or specifications'),
});

interface ProductIntent {
  productName: string | null;
  brand?: string | null;
  category?: string | null;
  priceRange?: { min?: number | null; max?: number | null } | null;
  gender?: 'men' | 'women' | 'unisex' | null;
  color?: string | null;
  features?: string[] | null;
}

// Fetch products from SerpAPI Shopping
async function fetchFromSerpAPI(
  intent: ProductIntent
): Promise<any[]> {
  try {
    // Build search query
    let query = '';
    if (intent.productName) {
      query = intent.productName;
    }
    if (intent.brand) {
      query = `${intent.brand} ${query}`.trim();
    }
    if (intent.category) {
      query = `${query} ${intent.category}`.trim();
    }
    if (intent.gender) {
      query = `${query} ${intent.gender}`.trim();
    }
    if (intent.color) {
      query = `${query} ${intent.color}`.trim();
    }
    if (!query.trim()) {
      query = 'products';
    }

    // Use the search service to get SerpAPI shopping results
    const searchResult = await search(query.trim(), [], {
      maxResults: 20,
      searchType: 'web',
    });

    // Extract shopping results from SerpAPI rawResponse
    const shoppingResults = searchResult.rawResponse?.shopping_results || 
                           searchResult.rawResponse?.shopping?.results ||
                           searchResult.rawResponse?.organic_results?.filter((r: any) => 
                             r.type === 'shopping' || r.link?.includes('amazon') || r.link?.includes('ebay')
                           ) || [];

    // Transform to consistent format
    return shoppingResults.map((product: any) => {
      // Extract price - handle both string and numeric formats
      let price: string | number = 'Price not available';
      if (product.extracted_price) {
        price = product.extracted_price;
      } else if (product.price) {
        price = product.price;
      } else if (product.current_price) {
        price = product.current_price;
      }

      // Extract source/retailer name from link or use provided source
      let source = product.source || 'Unknown Source';
      if (source === 'Unknown Source' && product.link) {
        try {
          const url = new URL(product.link);
          source = url.hostname.replace('www.', '').split('.')[0];
          source = source.charAt(0).toUpperCase() + source.slice(1);
        } catch (e) {
          // If URL parsing fails, keep Unknown Source
        }
      }

      return {
        id: product.product_id || product.position || product.link,
        title: product.title || product.name || product.product_title || product.tag || 'Unknown Product',
        price: price,
        oldPrice: product.old_price || product.original_price || product.list_price,
        rating: product.rating ? parseFloat(product.rating.toString()) : undefined,
        reviewCount: product.reviews ? parseInt(product.reviews.toString()) : 
                     (product.review_count ? parseInt(product.review_count.toString()) : undefined),
        description: product.snippet || product.description || product.product_description || 
                    (product.extensions ? product.extensions.join(', ') : '') || product.tag || '',
        thumbnail: product.thumbnail || product.image || (product.images?.[0] || ''),
        images: product.images || (product.thumbnail ? [product.thumbnail] : []),
        link: product.link || product.url || product.product_link || '',
        source: source,
        brand: product.brand || intent.brand,
        category: product.category || intent.category,
        delivery: product.delivery,
        extensions: product.extensions || [],
        source_api: 'serpapi',
      };
    });
  } catch (error: any) {
    console.warn('⚠️ SerpAPI shopping search failed:', error.message);
    return [];
  }
}

// Fetch products from Google Shopping (via SerpAPI with shopping parameter)
async function fetchFromGoogleShopping(
  intent: ProductIntent
): Promise<any[]> {
  try {
    // Build search query
    let query = '';
    if (intent.productName) {
      query = intent.productName;
    }
    if (intent.brand) {
      query = `${intent.brand} ${query}`.trim();
    }
    if (intent.category) {
      query = `${query} ${intent.category}`.trim();
    }
    if (!query.trim()) {
      return []; // Skip if no query
    }

    // Use SerpAPI with shopping-specific search
    // Note: This would require SerpAPI shopping endpoint, which may need special handling
    // For now, we'll use the regular search and filter for shopping results
    const searchResult = await search(`buy ${query.trim()}`, [], {
      maxResults: 20,
      searchType: 'web',
    });

    // Extract Google Shopping results
    const shoppingResults = searchResult.rawResponse?.shopping_results || 
                           searchResult.rawResponse?.shopping?.results || [];

    // Transform to consistent format (similar to SerpAPI)
    return shoppingResults.map((product: any) => {
      let price: string | number = 'Price not available';
      if (product.extracted_price) {
        price = product.extracted_price;
      } else if (product.price) {
        price = product.price;
      }

      let source = product.source || 'Google Shopping';
      if (product.link) {
        try {
          const url = new URL(product.link);
          source = url.hostname.replace('www.', '').split('.')[0];
          source = source.charAt(0).toUpperCase() + source.slice(1);
        } catch (e) {
          // Keep default source
        }
      }

      return {
        id: product.product_id || product.position || product.link,
        title: product.title || product.name || 'Unknown Product',
        price: price,
        oldPrice: product.old_price || product.original_price,
        rating: product.rating ? parseFloat(product.rating.toString()) : undefined,
        reviewCount: product.reviews ? parseInt(product.reviews.toString()) : undefined,
        description: product.snippet || product.description || '',
        thumbnail: product.thumbnail || product.image || '',
        images: product.images || (product.thumbnail ? [product.thumbnail] : []),
        link: product.link || product.url || '',
        source: source,
        brand: product.brand || intent.brand,
        category: product.category || intent.category,
        source_api: 'google_shopping',
      };
    });
  } catch (error: any) {
    console.warn('⚠️ Google Shopping search failed:', error.message);
    return [];
  }
}

// Decide which data sources to use based on intent
function decideDataSources(intent: ProductIntent): {
  useSerpAPI: boolean;
  useGoogleShopping: boolean;
} {
  return {
    useSerpAPI: true, // Always use SerpAPI as primary source
    useGoogleShopping: !!intent.productName || !!intent.brand, // Use if we have search criteria
  };
}

// Filter products by price range if specified
function filterByPriceRange(products: any[], priceRange?: { min?: number; max?: number } | null): any[] {
  if (!priceRange || (!priceRange.min && !priceRange.max)) {
    return products;
  }

  return products.filter(product => {
    const price = typeof product.price === 'number' ? product.price : 
                  typeof product.price === 'string' ? parseFloat(product.price.replace(/[^\d.]/g, '')) : 
                  null;
    
    if (price === null || isNaN(price)) {
      return true; // Keep products with unknown prices
    }

    if (priceRange.min && price < priceRange.min) {
      return false;
    }
    if (priceRange.max && price > priceRange.max) {
      return false;
    }
    return true;
  });
}

// Merge product data from multiple sources, deduplicating by title + source
function mergeProductData(
  serpAPIData: any[],
  googleShoppingData: any[]
): any[] {
  const merged: any[] = [];
  const seen = new Set<string>();
  
  // Helper to generate unique key for deduplication
  const getKey = (product: any): string => {
    const title = (product.title || product.name || '').toLowerCase().trim();
    const source = (product.source || 'unknown').toLowerCase().trim();
    // Use title + source to allow same product from different retailers
    return `${title}::${source}`;
  };
  
  // Priority 1: SerpAPI data (most comprehensive)
  serpAPIData.forEach(product => {
    const key = getKey(product);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push({
        ...product,
        source: product.source || 'serpapi',
      });
    }
  });
  
  // Priority 2: Google Shopping data (supplement with additional retailers)
  googleShoppingData.forEach(product => {
    const key = getKey(product);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push({
        ...product,
        source: product.source || 'google_shopping',
      });
    }
  });
  
  return merged;
}

// Separate evidence (factual) from commerce (purchase) data
function formatProductCards(products: any[]): any[] {
  return products.map(product => ({
    // Evidence (factual, non-commercial)
    id: product.id || product.product_id || product.link || `product-${Math.random()}`,
    title: product.title || product.name || 'Unknown Product',
    description: product.description || product.snippet || '',
    brand: product.brand,
    category: product.category,
    rating: product.rating ? parseFloat(product.rating.toString()) : undefined,
    reviews: product.reviewCount || product.reviews,
    images: product.images || (product.thumbnail ? [product.thumbnail] : []),
    thumbnail: product.thumbnail || product.image || (product.images?.[0] || ''),
    extensions: product.extensions || [],
    delivery: product.delivery,
    
    // Commerce (purchase-related)
    price: product.price,
    discountPrice: product.oldPrice && product.price && 
                   (typeof product.oldPrice === 'number' ? product.oldPrice : parseFloat(product.oldPrice.toString().replace(/[^\d.]/g, ''))) > 
                   (typeof product.price === 'number' ? product.price : parseFloat(product.price.toString().replace(/[^\d.]/g, ''))) 
                   ? product.oldPrice : undefined,
    source: product.source || 'Unknown Source',
    link: product.link || product.url || product.product_link || '',
    purchaseLinks: {
      direct: product.link || product.url,
      amazon: product.link?.includes('amazon') ? product.link : undefined,
      ebay: product.link?.includes('ebay') ? product.link : undefined,
      walmart: product.link?.includes('walmart') ? product.link : undefined,
    },
  }));
}

const productWidget: WidgetInterface = {
  type: 'product',

  shouldExecute(classification?: any): boolean {
    // ✅ Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showProductWidget) {
      return true;
    }
    
    // Check if product widget should execute based on classification
    if (classification?.widgetTypes?.includes('product')) {
      return true;
    }
    
    // Fallback: check intent/domains
    const detectedDomains = classification?.detectedDomains || [];
    const intent = classification?.intent || '';
    return detectedDomains.includes('product') || intent === 'product';
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget, classification, rawResponse, followUp, llm } = input;
    
    // ✅ CRITICAL: LLM is required for agent-style widget (intent extraction)
    if (!llm) {
      return {
        type: 'product',
        data: [],
        success: false,
        error: 'LLM required for agent-style product widget (intent extraction)',
      };
    }

    try {
      // Step 1: Extract structured intent using LLM
      const query = followUp || classification?.query || classification?.queryRefinement || widget?.params?.query || '';
      
      if (!query) {
        return {
          type: 'product',
          data: [],
          success: false,
          error: 'No query provided for intent extraction',
        };
      }

      console.log('🔍 Extracting product intent from query:', query);
      
      // Use generateObject if available, otherwise fall back to generateText + JSON parsing
      let intentOutput: { object: ProductIntent };
      
      if (typeof llm.generateObject === 'function') {
        intentOutput = await llm.generateObject({
          messages: [
            {
              role: 'system',
              content: 'Extract product search intent from user query. Return ONLY valid JSON with structured data containing productName, brand, category, priceRange, gender, color, and features. If information is not provided, use null.',
            },
            {
              role: 'user',
              content: query,
            },
          ],
          schema: productIntentSchema,
        });
      } else {
        // Fallback: use generateText and parse JSON
        const response = await llm.generateText({
          messages: [
            {
              role: 'system',
              content: 'Extract product search intent from user query. Return ONLY valid JSON matching this schema: { productName: string | null, brand?: string | null, category?: string | null, priceRange?: { min?: number, max?: number } | null, gender?: "men" | "women" | "unisex" | null, color?: string | null, features?: string[] }. If information is not provided, use null.',
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

      const intent: ProductIntent = intentOutput.object;
      
      // ✅ Normalize null arrays to empty arrays for easier handling
      if (intent.features === null) {
        intent.features = [];
      }
      
      console.log('✅ Extracted product intent:', intent);

      // Step 2: Validate that we have at least some search criteria
      if (!intent.productName && !intent.brand && !intent.category) {
        return {
          type: 'product',
          data: [],
          success: false,
          error: 'Could not extract product search criteria from query (need product name, brand, or category)',
        };
      }

      // Step 3: Decide which data sources to use
      const sources = decideDataSources(intent);
      console.log('📊 Data sources decision:', sources);

      // Step 4: Fetch from ALL sources in parallel (no fallback - all are data sources)
      const fetchPromises: Promise<any[]>[] = [];
      
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

      if (sources.useGoogleShopping) {
        fetchPromises.push(
          fetchFromGoogleShopping(intent)
            .catch(error => {
              console.warn('⚠️ Google Shopping failed:', error.message);
              return []; // Return empty array, continue with other sources
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      const [serpAPIData, googleShoppingData] = await Promise.all(fetchPromises);

      // Step 5: Merge data from all sources
      const mergedProducts = mergeProductData(serpAPIData, googleShoppingData);
      console.log(`✅ Merged ${mergedProducts.length} products from ${serpAPIData.length} SerpAPI, ${googleShoppingData.length} Google Shopping`);

      // Step 6: Filter by price range if specified
      const filteredProducts = filterByPriceRange(mergedProducts, intent.priceRange);

      // Step 7: Format product cards with evidence/commerce separation
      const productCards = formatProductCards(filteredProducts);

      if (productCards.length === 0) {
        return {
          type: 'product',
          data: [],
          success: false,
          error: 'No products found from any data source (SerpAPI, Google Shopping)',
        };
      }

      return {
        type: 'product',
        data: productCards,
        success: true,
        llmContext: `Found ${productCards.length} products${intent.productName ? ` matching "${intent.productName}"` : ''}${intent.brand ? ` from ${intent.brand}` : ''}${intent.priceRange ? ` in price range ${intent.priceRange.min || '0'}-${intent.priceRange.max || '∞'}` : ''} from multiple sources`,
      };
    } catch (error: any) {
      console.error('❌ Agent-style product widget error:', error);
      
      // No fallback - return error (all sources are already included in the widget)
      return {
        type: 'product',
        data: [],
        success: false,
        error: error.message || 'Failed to fetch product data from all sources',
      };
    }
  },
};

export default productWidget;

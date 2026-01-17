

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';
import { search } from '../searchService';
import z from 'zod';


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


async function fetchFromSerpAPI(
  intent: ProductIntent
): Promise<any[]> {
  try {
    
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

    
    const searchResult = await search(query.trim(), [], {
      maxResults: 20,
      searchType: 'web',
    });

   
    const shoppingResults = searchResult.rawResponse?.shopping_results || 
                           searchResult.rawResponse?.shopping?.results ||
                           searchResult.rawResponse?.organic_results?.filter((r: any) => 
                             r.type === 'shopping' || r.link?.includes('amazon') || r.link?.includes('ebay')
                           ) || [];

    
    return shoppingResults.map((product: any) => {
      
      let price: string | number = 'Price not available';
      if (product.extracted_price) {
        price = product.extracted_price;
      } else if (product.price) {
        price = product.price;
      } else if (product.current_price) {
        price = product.current_price;
      }

      
      let source = product.source || 'Unknown Source';
      if (source === 'Unknown Source' && product.link) {
        try {
          const url = new URL(product.link);
          source = url.hostname.replace('www.', '').split('.')[0];
          source = source.charAt(0).toUpperCase() + source.slice(1);
        } catch (e) {
          
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


async function fetchFromGoogleShopping(
  intent: ProductIntent
): Promise<any[]> {
  try {
    
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
      return []; 
    }

    
    const searchResult = await search(`buy ${query.trim()}`, [], {
      maxResults: 20,
      searchType: 'web',
    });

    
    const shoppingResults = searchResult.rawResponse?.shopping_results || 
                           searchResult.rawResponse?.shopping?.results || [];

    
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


function decideDataSources(intent: ProductIntent): {
  useSerpAPI: boolean;
  useGoogleShopping: boolean;
} {
  return {
    useSerpAPI: true, 
    useGoogleShopping: !!intent.productName || !!intent.brand, 
  };
}


function filterByPriceRange(products: any[], priceRange?: { min?: number; max?: number } | null): any[] {
  if (!priceRange || (!priceRange.min && !priceRange.max)) {
    return products;
  }

  return products.filter(product => {
    const price = typeof product.price === 'number' ? product.price : 
                  typeof product.price === 'string' ? parseFloat(product.price.replace(/[^\d.]/g, '')) : 
                  null;
    
    if (price === null || isNaN(price)) {
      return true; 
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


function mergeProductData(
  serpAPIData: any[],
  googleShoppingData: any[]
): any[] {
  const merged: any[] = [];
  const seen = new Set<string>();
  
  
  const getKey = (product: any): string => {
    const title = (product.title || product.name || '').toLowerCase().trim();
    const source = (product.source || 'unknown').toLowerCase().trim();
    
    return `${title}::${source}`;
  };
  
  
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


function formatProductCards(products: any[]): any[] {
  return products.map(product => ({
    
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
   
    if (classification?.classification?.showProductWidget) {
      return true;
    }
    
    
    if (classification?.widgetTypes?.includes('product')) {
      return true;
    }
    
   
    const detectedDomains = classification?.detectedDomains || [];
    const intent = classification?.intent || '';
    return detectedDomains.includes('product') || intent === 'product';
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget, classification, rawResponse, followUp, llm } = input;
    
    
    if (!llm) {
      return {
        type: 'product',
        data: [],
        success: false,
        error: 'LLM required for agent-style product widget (intent extraction)',
      };
    }

    try {
      
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
      
      
      if (intent.features === null) {
        intent.features = [];
      }
      
      console.log('✅ Extracted product intent:', intent);

      
      if (!intent.productName && !intent.brand && !intent.category) {
        return {
          type: 'product',
          data: [],
          success: false,
          error: 'Could not extract product search criteria from query (need product name, brand, or category)',
        };
      }

      
      const sources = decideDataSources(intent);
      console.log('📊 Data sources decision:', sources);

      
      const fetchPromises: Promise<any[]>[] = [];
      
      if (sources.useSerpAPI) {
        fetchPromises.push(
          fetchFromSerpAPI(intent)
            .catch(error => {
              console.warn('⚠️ SerpAPI failed:', error.message);
              return []; 
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
              return []; 
            })
        );
      } else {
        fetchPromises.push(Promise.resolve([]));
      }

      const [serpAPIData, googleShoppingData] = await Promise.all(fetchPromises);

      
      const mergedProducts = mergeProductData(serpAPIData, googleShoppingData);
      console.log(`✅ Merged ${mergedProducts.length} products from ${serpAPIData.length} SerpAPI, ${googleShoppingData.length} Google Shopping`);

      
      const filteredProducts = filterByPriceRange(mergedProducts, intent.priceRange);

      
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

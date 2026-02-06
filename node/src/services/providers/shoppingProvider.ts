

export interface ShoppingProvider {
  name: string;
  search(query: string, options?: ShoppingSearchOptions): Promise<ShoppingProduct[]>;
}

export interface ShoppingSearchOptions {
  limit?: number;
  priceMax?: number;
  priceMin?: number;
  gender?: 'men' | 'women' | 'unisex';
  category?: string;
  brand?: string;
}

export interface ShoppingProduct {
  title: string;
  price: string;
  rating: number;
  thumbnail: string;
  images: string[];
  link: string;
  source: string;
  snippet?: string;
  description?: string;
  category?: string;
  brand?: string;
  gender?: string;
  reviews?: string;
  extensions?: string[];
  tag?: string;
  delivery?: string;
  _raw_snippet?: string;
}


export function buildOptimalQuery(
  originalQuery: string,
  options?: ShoppingSearchOptions
): string {
  let query = originalQuery.toLowerCase().trim();
  

  query = query.replace(/\s*(under|below|less than|max|maximum|up to)\s*\$?\d+/gi, '');
  
  
  if (query.includes(' for men') || query.includes(' for male')) {
    query = query.replace(/\s+for\s+(men|male)/gi, '');
    if (!query.includes("men's") && !query.includes("mens")) {
      
      const categoryMatch = query.match(/\b(shoes|sneakers|boots|shirt|tshirt|t-shirt|glasses|sunglasses|watch|watches|bag|purse|backpack)\b/i);
      if (categoryMatch) {
        query = query.replace(categoryMatch[0], `men's ${categoryMatch[0]}`);
      } else {
        query = `men's ${query}`;
      }
    }
  }
  
  if (query.includes(' for women') || query.includes(' for woman') || query.includes(' for female')) {
    query = query.replace(/\s+for\s+(women|woman|female|girls)/gi, '');
    if (!query.includes("women's") && !query.includes("womens")) {
      const categoryMatch = query.match(/\b(shoes|sneakers|boots|shirt|tshirt|t-shirt|glasses|sunglasses|watch|watches|bag|purse|backpack|dress)\b/i);
      if (categoryMatch) {
        query = query.replace(categoryMatch[0], `women's ${categoryMatch[0]}`);
      } else {
        query = `women's ${query}`;
      }
    }
  }
  
  
  query = query.replace(/\s+/g, ' ').trim();
  
  return query;
}


export function extractFiltersFromQuery(query: string): {
  priceMax?: number;
  priceMin?: number;
  gender?: 'men' | 'women' | 'unisex';
  category?: string;
  brand?: string;
} {
  const filters: any = {};
  
  
  const priceMatch = query.match(/(under|below|less than|max|maximum|up to)\s*\$?(\d+)/i);
  if (priceMatch) {
    filters.priceMax = parseInt(priceMatch[2]);
  }
  
  const priceMinMatch = query.match(/(over|above|more than|min|minimum|from)\s*\$?(\d+)/i);
  if (priceMinMatch) {
    filters.priceMin = parseInt(priceMinMatch[2]);
  }
  
  
  if (/men|male|mens/i.test(query)) {
    filters.gender = 'men';
  } else if (/women|woman|female|girls|womens/i.test(query)) {
    filters.gender = 'women';
  }
  
  
  const categories = ['shoes', 'sneakers', 'boots', 'shirt', 'tshirt', 't-shirt', 'glasses', 'sunglasses', 'watch', 'watches', 'bag', 'purse', 'backpack', 'dress', 'laptop', 'phone', 'headphones'];
  for (const cat of categories) {
    if (new RegExp(`\\b${cat}\\b`, 'i').test(query)) {
      filters.category = cat;
      break;
    }
  }
  
  
  const brands = ['nike', 'adidas', 'puma', 'reebok', 'new balance', 'balmain', 'rayban', 'ray-ban', 'gucci', 'oakley', 'apple', 'samsung', 'sony', 'hp', 'macbook', 'fossil', 'michael kors', 'mk', 'prada'];
  for (const brand of brands) {
    if (new RegExp(`\\b${brand}\\b`, 'i').test(query)) {
      filters.brand = brand;
      break;
    }
  }
  
  return filters;
}


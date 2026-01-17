

export interface SlotExtraction {
  brand: string | null;
  category: string | null;
  price: string | null;
  city: string | null;
}


export function analyzeCardNeed(query: string): SlotExtraction {
  const lower = query.toLowerCase();
  
 
  const brands = [
    'nike', 'adidas', 'apple', 'samsung', 'sony', 'canon', 'nikon',
    'dell', 'hp', 'lenovo', 'asus', 'msi', 'lg', 'panasonic',
    'rolex', 'omega', 'seiko', 'casio', 'fossil',
    'ray-ban', 'oakley', 'warby parker',
  ];
  
  let brand: string | null = null;
  for (const b of brands) {
    if (lower.includes(b)) {
      brand = b;
      break;
    }
  }

  
  let category: string | null = null;
  const categories = [
    'shoes', 'sneakers', 'boots', 'sandals',
    'watch', 'watches', 'timepiece',
    'glasses', 'sunglasses', 'eyewear',
    'laptop', 'computer', 'phone', 'smartphone',
    'headphones', 'earbuds', 'camera',
    'hotel', 'hotels', 'restaurant', 'restaurants',
  ];
  
  for (const cat of categories) {
    if (lower.includes(cat)) {
      category = cat;
      break;
    }
  }

  
  let price: string | null = null;
  const priceMatch = lower.match(/\$?(\d+)\s*(k|thousand|hundred)?/i);
  if (priceMatch) {
    let amount = priceMatch[1];
    if (priceMatch[2] && priceMatch[2].toLowerCase().startsWith('k')) {
      amount = amount + '000';
    }
    price = `$${amount}`;
  } else if (lower.includes('under') || lower.includes('below') || lower.includes('less than')) {
    const underMatch = lower.match(/(?:under|below|less than)\s*\$?(\d+)/i);
    if (underMatch) {
      price = `$${underMatch[1]}`;
    }
  }

  
  let city: string | null = null;
  
  const cityPatterns = [
    /\b(new york|nyc|manhattan)\b/i,
    /\b(los angeles|la)\b/i,
    /\b(chicago)\b/i,
    /\b(houston)\b/i,
    /\b(phoenix)\b/i,
    /\b(philadelphia)\b/i,
    /\b(san antonio)\b/i,
    /\b(san diego)\b/i,
    /\b(dallas)\b/i,
    /\b(san jose)\b/i,
    /\b(london)\b/i,
    /\b(paris)\b/i,
    /\b(tokyo)\b/i,
    /\b(berlin)\b/i,
    /\b(madrid)\b/i,
    /\b(rome)\b/i,
    /\b(amsterdam)\b/i,
    /\b(barcelona)\b/i,
  ];
  
  for (const pattern of cityPatterns) {
    const match = query.match(pattern);
    if (match) {
      city = match[1] || match[0];
      break;
    }
  }

  return {
    brand,
    category,
    price,
    city,
  };
}


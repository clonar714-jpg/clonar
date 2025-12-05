// src/filters/productFilters.ts

/**
 * Extract price from text
 */
function extractPrice(priceText: any): number | null {
  if (!priceText) return null;
  const text = priceText.toString().replace(/,/g, "");
  const match = text.match(/\$?(\d{2,5})(\.\d+)?/);
  if (!match) return null;
  return parseFloat(match[1]);
}

/**
 * 🟦 C8.1 — LEXICAL FILTERING (HARD FILTERS)
 * Applied BEFORE reranking to remove obviously wrong items
 */
export function applyLexicalFilters(query: string, items: any[]): any[] {
  if (!items || items.length === 0) return [];

  // Skip filtering for hotels - they don't have product categories
  if (items.length > 0 && (items[0].source === "Google Hotels" || items[0].name && !items[0].title)) {
    return items;
  }

  const q = query.toLowerCase();
  let filtered = [...items]; // Create a copy

  // PRICE FILTERS
  const priceMatch = q.match(/under\s*\$?(\d+)/i) || q.match(/\$?(\d+)\s*under/i);
  if (priceMatch) {
    const limit = parseInt(priceMatch[1]);
    filtered = filtered.filter((item) => {
      const p = extractPrice(item.price || item.extracted_price);
      return p !== null && p <= limit;
    });
    console.log(`💰 Price filter: ${filtered.length} items under $${limit}`);
  }

  // GENDER FILTERING
  if (q.includes("men") || q.includes("male") || q.includes("mens")) {
    filtered = filtered.filter((item) => {
      const title = (item.title || item.name || "").toLowerCase();
      const category = (item.category || "").toLowerCase();
      return /men|male|mens/i.test(title) || /men|male/i.test(category);
    });
    console.log(`👔 Gender filter (men): ${filtered.length} items`);
  }

  if (q.includes("women") || q.includes("woman") || q.includes("girl") || q.includes("womens")) {
    filtered = filtered.filter((item) => {
      const title = (item.title || item.name || "").toLowerCase();
      const category = (item.category || "").toLowerCase();
      return /women|woman|female|girls|womens/i.test(title) || /women|female/i.test(category);
    });
    console.log(`👗 Gender filter (women): ${filtered.length} items`);
  }

  // CATEGORY FILTERING
  if (q.includes("shirt") || q.includes("tshirt") || q.includes("t-shirt")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /shirt|t-shirt|tee|t shirt/i.test(title);
    });
    console.log(`👕 Category filter (shirt): ${filtered.length} items`);
  }

  if (q.includes("glasses") || q.includes("sunglasses")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /glass|sunglass|eyewear|spectacle/i.test(title);
    });
    console.log(`👓 Category filter (glasses): ${filtered.length} items`);
  }

  if (q.includes("shoes") || q.includes("sneakers") || q.includes("sneaker")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /shoe|sneaker|running|boot|sandal/i.test(title);
    });
    console.log(`👟 Category filter (shoes): ${filtered.length} items`);
  }

  if (q.includes("watch") || q.includes("watches")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /watch/i.test(title);
    });
    console.log(`⌚ Category filter (watch): ${filtered.length} items`);
  }

  if (q.includes("bag") || q.includes("purse") || q.includes("backpack")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /bag|purse|backpack|handbag|tote/i.test(title);
    });
    console.log(`👜 Category filter (bag): ${filtered.length} items`);
  }

  if (q.includes("laptop") || q.includes("computer")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /laptop|computer|notebook|macbook/i.test(title);
    });
    console.log(`💻 Category filter (laptop): ${filtered.length} items`);
  }

  if (q.includes("phone") || q.includes("smartphone")) {
    filtered = filtered.filter((i) => {
      const title = (i.title || i.name || "").toLowerCase();
      return /phone|smartphone|iphone|android/i.test(title);
    });
    console.log(`📱 Category filter (phone): ${filtered.length} items`);
  }

  return filtered;
}


// src/services/productSearch.ts
import { refineQuery } from "./llmQueryRefiner";
import { generateProductDescription } from "./productDescriptionGenerator";
import { repairQuery } from "./queryRepair";
import { providerManager } from "./providers/providerManager";
import { SerpApiProvider } from "./providers/serpApiProvider";
// Register providers (happens once at startup)
providerManager.register(new SerpApiProvider());
// Uncomment when you get Shopify API:
// providerManager.register(new ShopifyProvider());
/**
 * Normalize price so Flutter parsing never fails.
 */
function parsePrice(raw) {
    if (!raw)
        return "0";
    if (typeof raw === "number")
        return raw.toString();
    const text = raw.toString();
    const cleaned = text.replace(/[^\d.]/g, "");
    return cleaned.length ? cleaned : "0";
}
/**
 * Normalize rating.
 */
function parseRating(raw) {
    if (!raw)
        return 0;
    const text = raw.toString().replace(/[^\d.]/g, "");
    return Number(text) || 0;
}
/**
 * Normalize thumbnail or images.
 */
function safeImage(img) {
    if (!img)
        return "";
    if (typeof img === "string")
        return img;
    return "";
}
/**
 * Map raw provider product to Clonar standard product.
 */
function normalizeProduct(item) {
    const title = item.title ||
        item.name ||
        item.product_title ||
        item.tag ||
        "Unknown Product";
    const price = parsePrice(item.price || item.extracted_price || item.current_price);
    const rating = parseRating(item.rating || item.reviews || item.score);
    const thumbnail = safeImage(item.thumbnail) ||
        safeImage(item.image) ||
        (item.images?.[0] ? safeImage(item.images[0]) : "") ||
        "";
    // Build images array - include thumbnail if not already in images
    const imageList = [];
    if (thumbnail) {
        imageList.push(thumbnail);
    }
    if (item.images && Array.isArray(item.images)) {
        item.images.forEach((img) => {
            const imgUrl = safeImage(img);
            if (imgUrl && !imageList.includes(imgUrl)) {
                imageList.push(imgUrl);
            }
        });
    }
    // If no images found, use thumbnail as fallback
    const images = imageList.length > 0 ? imageList : (thumbnail ? [thumbnail] : []);
    const link = item.link ||
        item.url ||
        item.product_link ||
        "";
    // Extract old_price for discount calculation
    const oldPrice = parsePrice(item.old_price || item.original_price || item.list_price);
    // ✅ DESCRIPTION EXTRACTION (Multi-source, future-proof for affiliate APIs)
    // Priority order:
    // 1. snippet (SerpAPI Google Shopping)
    // 2. description (Generic/affiliate APIs)
    // 3. product_description (Amazon, eBay affiliate APIs)
    // 4. long_description (Some affiliate APIs)
    // 5. short_description (Some affiliate APIs)
    // 6. extensions array (SerpAPI fallback - join array items)
    // 7. tag (SerpAPI fallback)
    // 8. delivery (SerpAPI fallback - sometimes contains useful info)
    const snippet = item.snippet || "";
    const description = item.description || item.product_description || item.long_description || item.short_description || "";
    const extensions = Array.isArray(item.extensions) && item.extensions.length > 0
        ? item.extensions.map((e) => String(e || "")).filter((e) => e.trim().length > 0).join(", ")
        : "";
    const tag = item.tag || "";
    const delivery = item.delivery || "";
    // Combine all possible description sources (prefer longer, more detailed ones)
    let finalSnippet = snippet || description;
    if (!finalSnippet && extensions) {
        finalSnippet = extensions;
    }
    else if (!finalSnippet && tag) {
        finalSnippet = tag;
    }
    else if (!finalSnippet && delivery && delivery.length > 20) {
        // Only use delivery if it's substantial (not just "Free shipping")
        finalSnippet = delivery;
    }
    // ✅ LOG: Help debug missing descriptions (remove in production if too verbose)
    if (!finalSnippet) {
        console.log(`⚠️ No description found for product: ${title}`);
        console.log(`   Available fields: snippet=${!!snippet}, description=${!!description}, extensions=${extensions.length > 0}, tag=${!!tag}`);
    }
    return {
        title,
        price,
        thumbnail,
        images,
        link,
        rating,
        // Additional fields Flutter expects
        source: item.source || "Unknown Source",
        reviews: item.reviews || item.review_count || "",
        snippet: finalSnippet, // ✅ Raw snippet (will be replaced with LLM-generated description)
        extensions: item.extensions || [],
        tag: item.tag || "",
        delivery: item.delivery || "",
        // Price fields for discount calculation
        old_price: oldPrice !== "0" ? oldPrice : undefined,
        extracted_price: price, // Keep for compatibility
        // ✅ FUTURE-PROOF: Store raw description fields for affiliate API compatibility
        // When switching to affiliate APIs (Amazon, eBay, etc.), these fields will be automatically used
        _raw_description: description, // Store for future use
        _raw_product_description: item.product_description || "",
        _raw_snippet: finalSnippet, // Store raw snippet for LLM context
    };
}
async function tryFetch(fn, label) {
    try {
        const items = await fn();
        return { success: true, items, label };
    }
    catch (err) {
        console.error(`❌ ${label} search error:`, err.message || err);
        return { success: false, items: [], label };
    }
}
function mergeCardResults(attempts) {
    const merged = [];
    const seen = new Set();
    for (const a of attempts) {
        if (!a.items || a.items.length === 0)
            continue;
        for (const item of a.items) {
            const key = `${item.title || ""}_${item.price || ""}_${item.link || ""}`;
            if (!seen.has(key)) {
                seen.add(key);
                merged.push(item);
            }
        }
    }
    return merged;
}
/**
 * 🏪 Provider Manager
 * Manages multiple shopping providers with fallback logic
 */
const providers = [
    new SerpApiProvider(),
    // Add more providers as they become available
    // new ShopifyProvider(),
];
/**
 * 🔍 Search using unified provider manager
 * Uses the same pattern for all field types
 * ⚠️ NO description generation here - done AFTER filtering in agent.ts
 */
async function searchWithProviders(query, options) {
    // Use unified ProviderManager (handles query optimization, filtering, fallback)
    const products = await providerManager.search(query, "shopping", options);
    // Convert to internal format
    const normalized = products.map((p) => normalizeProduct(p));
    // ⚠️ Description generation removed - will be done AFTER filtering in agent.ts
    // This prevents generating descriptions for items that won't be displayed
    return normalized;
}
/**
 * Enrich products with Perplexity-style LLM-generated descriptions
 * Uses batching to avoid rate limits and improve performance
 * ⚠️ This should ONLY be called AFTER filtering/reranking for final displayed results
 */
export async function enrichProductsWithDescriptions(products) {
    if (products.length === 0)
        return;
    console.log(`📝 Generating LLM descriptions for ${products.length} products...`);
    // ✅ OPTIMIZATION: Process all products in parallel (removed batching delays)
    // OpenAI API can handle concurrent requests, and we have timeout protection
    const descriptionPromises = products.map(async (product) => {
        try {
            // Extract features from extensions, tag, or snippet
            const features = [];
            if (product.extensions && Array.isArray(product.extensions)) {
                features.push(...product.extensions.map((e) => String(e || '')));
            }
            if (product.tag)
                features.push(product.tag);
            // Extract materials/design hints from snippet
            const materials = [];
            const rawSnippet = product._raw_snippet || product.snippet || '';
            if (rawSnippet.toLowerCase().includes('mesh'))
                materials.push('mesh');
            if (rawSnippet.toLowerCase().includes('leather'))
                materials.push('leather');
            if (rawSnippet.toLowerCase().includes('rubber'))
                materials.push('rubber');
            if (rawSnippet.toLowerCase().includes('foam'))
                materials.push('foam');
            // Infer category from title/snippet
            let category = '';
            const titleLower = (product.title || '').toLowerCase();
            const snippetLower = rawSnippet.toLowerCase();
            if (titleLower.includes('running') || snippetLower.includes('running'))
                category = 'Running';
            else if (titleLower.includes('basketball') || snippetLower.includes('basketball'))
                category = 'Basketball';
            else if (titleLower.includes('lifestyle') || snippetLower.includes('lifestyle'))
                category = 'Lifestyle';
            else if (titleLower.includes('sneaker') || snippetLower.includes('sneaker'))
                category = 'Sneakers';
            else if (titleLower.includes('shoe'))
                category = 'Footwear';
            const description = await Promise.race([
                generateProductDescription({
                    title: product.title,
                    price: product.price,
                    rating: product.rating,
                    category: category || undefined,
                    provider: product.source,
                    images: product.images || [],
                    rawDescription: rawSnippet, // For context only, not to copy
                    features: features.length > 0 ? features : undefined,
                    materials: materials.length > 0 ? materials : undefined,
                }),
                new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout')), 4000)),
            ]);
            // Replace snippet with LLM-generated description
            product.snippet = description;
            console.log(`✅ Generated description for: ${product.title.substring(0, 40)}...`);
        }
        catch (error) {
            console.warn(`⚠️ Failed to generate description for ${product.title}:`, error.message);
            // Keep original snippet if generation fails
        }
    });
    // Wait for all descriptions to complete in parallel
    await Promise.allSettled(descriptionPromises);
    console.log(`✅ Finished generating descriptions`);
}
/**
 * Fallback shopping API (uses unified provider system)
 */
async function fallbackShoppingAPI(query) {
    // ProviderManager automatically tries all registered providers
    // This is just a wrapper for consistency
    try {
        const products = await providerManager.search(query, "shopping");
        if (products.length > 0) {
            return products.map((p) => normalizeProduct(p));
        }
    }
    catch (error) {
        console.warn("⚠️ Fallback provider failed:", error.message);
    }
    return [];
}
/**
 * 🚀 Professional Shopping Search (Perplexity-style)
 * Uses provider abstraction with 3-layer retry system
 */
export async function searchProducts(query) {
    // 🔮 STEP 0: LLM Query Repair (Perplexity-style) - MUST happen FIRST
    const repairedQuery = await repairQuery(query, "shopping");
    console.log(`🔮 Query repair (shopping): "${query}" → "${repairedQuery}"`);
    const attempts = [];
    // Attempt 1 — Primary provider (use repaired query)
    const primary = await tryFetch(() => searchWithProviders(repairedQuery), "primary");
    attempts.push(primary);
    if (primary.success && primary.items.length >= 3) {
        console.log(`🛍 Found ${primary.items.length} products (primary provider)`);
        return primary.items.slice(0, 15);
    }
    // Attempt 2 — LLM-refined query (use repaired query as base)
    try {
        const refinedQuery = await refineQuery(repairedQuery, "shopping");
        const refined = await tryFetch(() => searchWithProviders(refinedQuery), "refined");
        attempts.push(refined);
        if (refined.success && refined.items.length >= 3) {
            console.log(`🛍 Found ${refined.items.length} products (refined query)`);
            return refined.items.slice(0, 15);
        }
    }
    catch (err) {
        console.error("❌ Query refinement failed:", err.message);
    }
    // Attempt 3 — Fallback provider
    const fallback = await tryFetch(() => fallbackShoppingAPI(query), "fallback");
    attempts.push(fallback);
    // Final result (merge non-empty results)
    const merged = mergeCardResults(attempts);
    if (merged.length > 0) {
        console.log(`🛍 Found ${merged.length} products (merged from ${attempts.filter(a => a.success).length} sources)`);
        // ⚠️ Description generation removed - will be done AFTER filtering in agent.ts
        // This prevents generating descriptions for items that won't be displayed
        return merged.slice(0, 15);
    }
    // ✅ Never return empty cards
    console.warn("⚠️ No products found, returning error card");
    return [
        {
            title: "No products found",
            price: "0",
            thumbnail: "",
            images: [],
            link: "",
            rating: 0,
            source: "Search",
            reviews: "",
            snippet: `No products found for "${query}". Try a different search term.`,
            extensions: [],
            tag: "",
            delivery: "",
        },
    ];
}

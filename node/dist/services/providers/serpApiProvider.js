/**
 * 🔍 SerpAPI Shopping Provider
 * Implements BaseProvider interface for SerpAPI (Google Shopping)
 */
import axios from "axios";
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
 * Map raw SerpAPI product to Clonar standard product.
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
    const images = imageList.length > 0 ? imageList : (thumbnail ? [thumbnail] : []);
    const link = item.link ||
        item.url ||
        item.product_link ||
        "";
    const oldPrice = parsePrice(item.old_price || item.original_price || item.list_price);
    // Description extraction (multi-source)
    const snippet = item.snippet || "";
    const description = item.description || item.product_description || item.long_description || item.short_description || "";
    const extensions = Array.isArray(item.extensions) && item.extensions.length > 0
        ? item.extensions.map((e) => String(e || "")).filter((e) => e.trim().length > 0).join(", ")
        : "";
    const tag = item.tag || "";
    const delivery = item.delivery || "";
    // Combine descriptions (priority: snippet > description > extensions > tag)
    const finalDescription = snippet || description || extensions || tag || "";
    return {
        title,
        price,
        rating,
        thumbnail,
        images,
        link,
        source: "SerpAPI",
        snippet: finalDescription,
        description: finalDescription,
        reviews: item.reviews || item.review_count || "",
        extensions: extensions ? extensions.split(", ") : [],
        tag,
        delivery,
        _raw_snippet: snippet, // Keep original for LLM context
    };
}
/**
 * Extract size from query
 */
function extractSize(query) {
    const sizeMatch = query.match(/\b(size|sz)\s*(\d+)\b/i);
    return sizeMatch ? sizeMatch[2] : null;
}
/**
 * Extract color from query
 */
function extractColor(query) {
    const colors = ['black', 'white', 'red', 'blue', 'green', 'yellow', 'orange', 'purple', 'pink', 'brown', 'gray', 'grey', 'navy', 'beige', 'tan'];
    const lowerQuery = query.toLowerCase();
    return colors.find(c => lowerQuery.includes(c)) || null;
}
/**
 * SerpAPI Shopping Provider Implementation
 * Uses unified BaseProvider interface
 */
export class SerpApiProvider {
    constructor() {
        this.name = "SerpAPI";
        this.fieldType = "shopping";
    }
    async search(query, options) {
        const serpUrl = "https://serpapi.com/search.json";
        const serpKey = process.env.SERPAPI_KEY;
        if (!serpKey) {
            throw new Error("Missing SERPAPI_KEY");
        }
        // Query is already optimized by ProviderManager
        const optimalQuery = query;
        const params = {
            engine: "google_shopping",
            q: optimalQuery, // Use optimized query
            hl: "en",
            gl: "us",
            api_key: serpKey,
            num: options?.limit || 20,
            tbs: "qdr:m", // ✅ FIX: Get results from past month (qdr:d=day, qdr:w=week, qdr:m=month, qdr:y=year)
        };
        // ✅ OPTIMIZATION: Retry logic with minimal backoff for faster responses
        const maxRetries = 3;
        let lastError;
        for (let attempt = 0; attempt < maxRetries; attempt++) {
            try {
                // ✅ OPTIMIZATION: Use consistent timeout (20s is sufficient)
                const timeout = 20000;
                console.log(`🔍 SerpAPI shopping attempt ${attempt + 1}/${maxRetries} (timeout: ${timeout}ms)...`);
                const res = await axios.get(serpUrl, { params, timeout });
                let items = res.data.shopping_results || [];
                console.log(`✅ SerpAPI shopping success: ${items.length} products found`);
                // Extract and filter by size (if in query)
                const size = extractSize(query);
                if (size) {
                    items = items.filter((p) => {
                        const title = (p.title || "").toLowerCase();
                        const desc = (p.snippet || p.description || "").toLowerCase();
                        return title.includes(`size ${size}`) ||
                            title.includes(` ${size} `) ||
                            desc.includes(`size ${size}`) ||
                            (p.variants && Array.isArray(p.variants) && p.variants.some((v) => v.size?.toString() === size || v.size?.toString() === `US ${size}` || v.size?.toString() === `UK ${size}`));
                    });
                }
                // Extract and filter by color (if in query)
                const color = extractColor(query);
                if (color) {
                    items = items.filter((p) => {
                        const title = (p.title || "").toLowerCase();
                        const desc = (p.snippet || p.description || "").toLowerCase();
                        return title.includes(color) || desc.includes(color);
                    });
                }
                const normalizedProducts = items.map((item) => normalizeProduct(item));
                return normalizedProducts;
            }
            catch (error) {
                lastError = error;
                const isTimeout = error.message?.includes("timeout") || error.code === "ECONNABORTED";
                if (isTimeout && attempt < maxRetries - 1) {
                    // ✅ OPTIMIZATION: Reduced backoff delays (100ms, 200ms instead of 1s, 2s, 3s)
                    const backoffDelay = (attempt + 1) * 100;
                    console.warn(`⚠️ SerpAPI timeout (attempt ${attempt + 1}), retrying in ${backoffDelay}ms...`);
                    await new Promise(resolve => setTimeout(resolve, backoffDelay));
                    continue;
                }
                // Last attempt or non-timeout error
                console.error(`❌ SerpAPI search error (attempt ${attempt + 1}/${maxRetries}):`, error.message);
                if (attempt === maxRetries - 1) {
                    throw error; // Throw on final attempt
                }
            }
        }
        // Should never reach here, but TypeScript needs it
        throw lastError || new Error("SerpAPI search failed after all retries");
    }
}

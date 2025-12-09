// src/services/restaurantSearch.ts
import axios from "axios";
import { refineQuery } from "./llmQueryRefiner";
import { repairQuery } from "./queryRepair";
function safeString(v) {
    return v ? v.toString() : "";
}
function safeNumber(v) {
    if (!v)
        return 0;
    return Number(String(v).replace(/[^\d.]/g, "")) || 0;
}
function safeImage(v) {
    return typeof v === "string" ? v : "";
}
function normalizeRestaurant(item) {
    // Build images array - include thumbnail if not already in images
    const imageList = [];
    const thumbnail = safeImage(item.thumbnail) ||
        safeImage(item.image) ||
        (item.images?.[0] ? safeImage(item.images[0]) : "") ||
        "";
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
    return {
        name: safeString(item.name || item.title),
        title: safeString(item.name || item.title || "Unknown Restaurant"), // Keep 'title' for compatibility
        rating: safeNumber(item.rating),
        price_level: safeString(item.price_level || item.price),
        cuisine: safeString(item.cuisine || item.category || item.type),
        address: safeString(item.address),
        phone: safeString(item.phone),
        thumbnail,
        images,
        link: safeString(item.link || item.url),
        reviews: safeNumber(item.reviews || item.review_count),
        type: safeString(item.type || item.category || item.cuisine), // Keep for compatibility
    };
}
/**
 * 🚀 C6 PATCH #7 — Primary restaurant search (SerpAPI)
 */
async function serpRestaurantSearch(query) {
    const serpUrl = "https://serpapi.com/search.json";
    const serpKey = process.env.SERPAPI_KEY;
    if (!serpKey) {
        throw new Error("Missing SERPAPI_KEY");
    }
    const params = {
        engine: "google_local",
        q: query,
        hl: "en",
        gl: "us",
        api_key: serpKey,
        num: 10,
    };
    const res = await axios.get(serpUrl, { params });
    const items = res.data.local_results || [];
    return items.map(normalizeRestaurant);
}
/**
 * 🚀 C6 PATCH #7 — Multi-API fallback for restaurants
 */
export async function searchRestaurants(query) {
    try {
        // 🔮 STEP 0: LLM Query Repair (Perplexity-style) - MUST happen FIRST
        const repairedQuery = await repairQuery(query, "restaurants");
        console.log(`🔮 Query repair (restaurants): "${query}" → "${repairedQuery}"`);
        console.log("🍽 Restaurant search:", repairedQuery);
        const results = [];
        // Attempt 1 — Primary SerpAPI (use repaired query)
        try {
            const primary = await serpRestaurantSearch(repairedQuery);
            results.push(...primary);
            if (results.length >= 3) {
                console.log(`🍽 Found ${results.length} restaurants (primary)`);
                return results.slice(0, 10);
            }
        }
        catch (err) {
            console.error("❌ Primary restaurant search failed:", err.message);
        }
        // Attempt 2 — LLM-refined query (use repaired query as base)
        try {
            const refinedQuery = await refineQuery(repairedQuery, "restaurants");
            const refined = await serpRestaurantSearch(refinedQuery);
            results.push(...refined);
            if (results.length >= 3) {
                console.log(`🍽 Found ${results.length} restaurants (refined query)`);
                return results.slice(0, 10);
            }
        }
        catch (err) {
            console.error("❌ Refined restaurant search failed:", err.message);
        }
        // Deduplicate results
        const seen = new Set();
        const merged = results.filter((r) => {
            const key = `${r.name || ""}_${r.address || ""}`;
            if (seen.has(key))
                return false;
            seen.add(key);
            return true;
        });
        if (merged.length > 0) {
            console.log(`🍽 Found ${merged.length} restaurants (merged)`);
            return merged.slice(0, 10);
        }
        // ✅ C6 PATCH #8 — Never return empty cards
        console.warn("⚠️ No restaurants found, returning error card");
        return [
            {
                name: "No restaurants found",
                title: "No restaurants found",
                rating: 0,
                price_level: "",
                cuisine: "",
                address: "",
                phone: "",
                thumbnail: "",
                images: [],
                link: "",
                reviews: 0,
                source: "Search",
                type: "",
            },
        ];
    }
    catch (err) {
        console.error("❌ Restaurant search error:", err.message || err);
        // ✅ C6 PATCH #8 — Never return empty cards
        return [
            {
                name: "Error loading restaurants",
                title: "Error loading restaurants",
                rating: 0,
                price_level: "",
                cuisine: "",
                address: "",
                phone: "",
                thumbnail: "",
                images: [],
                link: "",
                reviews: 0,
                source: "Error",
                type: "",
            },
        ];
    }
}

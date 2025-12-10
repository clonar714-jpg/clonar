// src/routes/agent.ts
import express from "express";
import { shouldFetchCards } from "../utils/semanticIntent";
import { routeQuery } from "../followup/router";
import { refineQuery } from "../services/llmQueryRefiner";
import { searchProducts, enrichProductsWithDescriptions } from "../services/productSearch";
import { searchHotels, enrichHotelsWithThemesAndDescriptions } from "../services/hotelSearch";
import { searchFlights } from "../services/flightSearch";
import { searchRestaurants } from "../services/restaurantSearch";
import { searchPlaces } from "../services/placesSearch";
import { searchMovies } from "../services/tmdbService";
import { analyzeImage } from "../services/imageAnalysis";
import { getAnswerStream, getAnswerNonStream } from "../services/llmAnswer";
import { rerankCards } from "../reranker/cardReranker";
import { applyLexicalFilters } from "../filters/productFilters";
import { applyAttributeFilters } from "../filters/attributeFilters";
import { correctCards } from "../correctors/llmCardCorrector";
import { filterHotelsByLocation, filterRestaurantsByLocation, filterPlacesByLocation } from "../filters/locationFilters";
import { saveSession, getSession, clearSession } from "../memory/sessionMemory";
import { detectGender } from "../memory/genderDetector";
import { refineQuery as refineQueryC11 } from "../refinement/refineQuery";
import { mergeQueryWithContext } from "../followup/context";
// ✅ Follow-up engine imports
import { getFollowUpSuggestions } from "../followup";
// ✅ Personalization imports
import { extractPreferenceSignals } from "../services/personalization/preferenceExtractor";
import { storePreferenceSignal, getUserPreferences } from "../services/personalization/preferenceStorage";
import { enhanceQueryWithPreferences, extractCategoryFromQuery } from "../services/personalization/queryEnhancer";
import { matchItemsToPreferences, hybridRerank } from "../services/personalization/preferenceMatcher";
import { incrementConversationCount, aggregateIfNeeded } from "../services/personalization/backgroundAggregator";
const router = express.Router();
let requestQueue = [];
let processingCount = 0;
const MAX_CONCURRENT_REQUESTS = 5; // Maximum concurrent requests
const MAX_QUEUE_SIZE = 20; // Maximum queue size
/**
 * ✅ FIX: Process queued requests
 */
async function processQueue() {
    if (processingCount >= MAX_CONCURRENT_REQUESTS || requestQueue.length === 0) {
        return;
    }
    const next = requestQueue.shift();
    if (!next)
        return;
    processingCount++;
    next.resolve(); // Release the request to be processed
    // Process the request
    try {
        await handleRequest(next.req, next.res);
    }
    catch (err) {
        console.error("❌ Request processing error:", err);
        if (!next.res.headersSent) {
            next.res.status(500).json({ error: "Request processing failed", detail: err.message });
        }
    }
    finally {
        processingCount--;
        // Process next in queue
        processQueue();
    }
}
/**
 * ✅ FIX: Main request handler (extracted from router.post)
 */
async function handleRequest(req, res) {
    try {
        const { query, conversationHistory, stream, sessionId, conversationId, userId, lastFollowUp, parentQuery, imageUrl } = req.body;
        let cleanQuery = query?.trim();
        // ✅ DEBUG: Log received imageUrl
        if (imageUrl) {
            console.log(`📸 Received imageUrl in request: ${typeof imageUrl}, value: ${imageUrl?.substring?.(0, 80) || imageUrl}`);
        }
        else {
            console.log(`📸 No imageUrl in request body`);
        }
        // ✅ NEW: Support image search - if imageUrl is provided, enhance query with image analysis
        let imageAnalysis = null;
        if (imageUrl && typeof imageUrl === "string" && imageUrl.trim().length > 0) {
            console.log(`🖼️ Image search request: query="${cleanQuery || '(no text)'}", imageUrl="${imageUrl.substring(0, 60)}..."`);
            try {
                // Analyze the image to get description and keywords
                imageAnalysis = await analyzeImage(imageUrl);
                console.log(`✅ Image analyzed: ${imageAnalysis.description.substring(0, 100)}...`);
                // ✅ BIG TECH STRATEGY: Multi-level intent detection (like ChatGPT/Perplexity)
                const hasUserText = cleanQuery && cleanQuery.trim().length > 0 &&
                    cleanQuery.toLowerCase() !== 'find similar items';
                // Level 1: Explicit user intent (highest priority)
                const explicitExplain = cleanQuery && (cleanQuery.toLowerCase().includes('explain') ||
                    cleanQuery.toLowerCase().includes('what is') ||
                    cleanQuery.toLowerCase().includes('describe') ||
                    cleanQuery.toLowerCase().includes('tell me about') ||
                    cleanQuery.toLowerCase().includes('what does this show') ||
                    cleanQuery.toLowerCase().includes('what place is this') ||
                    cleanQuery.toLowerCase().includes('where is this'));
                const explicitSearch = cleanQuery && (cleanQuery.toLowerCase().includes('find similar') ||
                    cleanQuery.toLowerCase().includes('search for') ||
                    cleanQuery.toLowerCase().includes('show me similar') ||
                    cleanQuery.toLowerCase().includes('where to buy') ||
                    cleanQuery.toLowerCase().includes('similar') ||
                    cleanQuery.toLowerCase().includes('like this'));
                // Level 2: Image content analysis (when intent is ambiguous)
                const imageDescription = imageAnalysis.description.toLowerCase();
                const isProductImage = imageDescription.includes('dress') ||
                    imageDescription.includes('shirt') ||
                    imageDescription.includes('hoodie') ||
                    imageDescription.includes('sweatshirt') ||
                    imageDescription.includes('jacket') ||
                    imageDescription.includes('product') ||
                    imageDescription.includes('item') ||
                    imageDescription.includes('clothing') ||
                    imageDescription.includes('apparel') ||
                    imageDescription.includes('garment') ||
                    imageDescription.includes('furniture') ||
                    imageDescription.includes('shoes') ||
                    imageDescription.includes('bag') ||
                    imageDescription.includes('accessory') ||
                    imageDescription.includes('reebok') ||
                    imageDescription.includes('nike') ||
                    imageDescription.includes('adidas') ||
                    imageDescription.includes('brand') ||
                    imageDescription.includes('logo') ||
                    imageDescription.includes('coral') && (imageDescription.includes('zip') || imageDescription.includes('zipper'));
                const isPlaceImage = imageDescription.includes('place') ||
                    imageDescription.includes('location') ||
                    imageDescription.includes('landmark') ||
                    imageDescription.includes('building') ||
                    imageDescription.includes('hotel') ||
                    imageDescription.includes('restaurant') ||
                    imageDescription.includes('beach') ||
                    imageDescription.includes('mountain') ||
                    imageDescription.includes('park') ||
                    imageDescription.includes('attraction');
                const isDocumentImage = imageDescription.includes('text') ||
                    imageDescription.includes('document') ||
                    imageDescription.includes('screenshot') ||
                    imageDescription.includes('map') ||
                    imageDescription.includes('interface') ||
                    imageDescription.includes('menu') ||
                    imageDescription.includes('screen');
                // Decision logic (ChatGPT/Perplexity-style)
                if (explicitExplain) {
                    // ✅ Explicit explain → Always explain (ignore image type)
                    cleanQuery = `${cleanQuery}. Image shows: ${imageAnalysis.description}`;
                    console.log(`🔍 EXPLAIN mode (explicit): "${cleanQuery.substring(0, 100)}..."`);
                }
                else if (explicitSearch) {
                    // ✅ Explicit search → Always search (ignore image type)
                    if (imageAnalysis.enhancedQuery) {
                        let cleanedEnhancedQuery = imageAnalysis.enhancedQuery
                            .replace(/^```json\s*/i, '')
                            .replace(/\s*```$/i, '')
                            .replace(/```/g, '')
                            .trim();
                        cleanQuery = `${cleanQuery} ${cleanedEnhancedQuery}`;
                    }
                    else if (imageAnalysis.keywords.length > 0) {
                        const keywords = imageAnalysis.keywords.join(' ');
                        cleanQuery = `${cleanQuery} ${keywords}`;
                    }
                    console.log(`🔍 SEARCH mode (explicit): "${cleanQuery}"`);
                }
                else if (!hasUserText) {
                    // ✅ No text → Use image content analysis
                    if (isProductImage) {
                        // Product → Search for similar
                        if (imageAnalysis.enhancedQuery) {
                            let cleanedEnhancedQuery = imageAnalysis.enhancedQuery
                                .replace(/^```json\s*/i, '')
                                .replace(/\s*```$/i, '')
                                .replace(/```/g, '')
                                .trim();
                            cleanQuery = `Find similar items. ${cleanedEnhancedQuery}`;
                        }
                        else {
                            cleanQuery = `Find similar items. ${imageAnalysis.keywords.join(' ')}`;
                        }
                        console.log(`🔍 SEARCH mode (auto-detected product): "${cleanQuery}"`);
                    }
                    else {
                        // Place/Document/Screenshot → Explain
                        cleanQuery = `Explain what is shown in this image. Image content: ${imageAnalysis.description}`;
                        console.log(`🔍 EXPLAIN mode (auto-detected place/document): "${cleanQuery.substring(0, 100)}..."`);
                    }
                }
                else {
                    // ✅ Ambiguous text → Default to explain (safer)
                    cleanQuery = `${cleanQuery}. Image shows: ${imageAnalysis.description}`;
                    console.log(`🔍 EXPLAIN mode (default for ambiguous): "${cleanQuery.substring(0, 100)}..."`);
                }
                // ✅ Final cleanup: remove any markdown artifacts from the final query
                cleanQuery = cleanQuery
                    .replace(/```json/gi, '')
                    .replace(/```/g, '')
                    .replace(/\s{2,}/g, ' ') // Remove extra spaces
                    .trim();
            }
            catch (error) {
                console.error('❌ Image analysis failed, continuing with original query:', error.message);
                console.error('❌ Error stack:', error.stack);
                // Continue with original query if image analysis fails
                if (!cleanQuery || cleanQuery.trim().length === 0) {
                    cleanQuery = "Find similar items";
                }
                // Set imageAnalysis to null to indicate failure
                imageAnalysis = null;
            }
        }
        if (!cleanQuery || typeof cleanQuery !== "string" || cleanQuery.trim().length === 0) {
            res.status(400).json({ error: "Invalid query" });
            return;
        }
        // ✅ FIX: When image is provided, COMPLETELY CLEAR conversation history to prevent old image context
        let filteredConversationHistory = conversationHistory || [];
        if (imageUrl && imageAnalysis) {
            console.log(`🖼️ ========== CLEARING CONVERSATION HISTORY ==========`);
            console.log(`🖼️ Original history length: ${(conversationHistory || []).length}`);
            // ✅ AGGRESSIVE FIX: For image searches, completely clear conversation history
            // This ensures no previous image search context interferes
            filteredConversationHistory = [];
            console.log(`✅ Conversation history completely cleared for image search (was ${(conversationHistory || []).length} turns)`);
            console.log(`🖼️ Using empty conversation history to ensure fresh results`);
        }
        // ==================================================================
        // ✅ FIX: ALWAYS GENERATE LLM ANSWER FIRST (Perplexity-style)
        // ==================================================================
        // Handle streaming requests separately
        if (stream === "true" || stream === true) {
            return getAnswerStream(cleanQuery, filteredConversationHistory, res);
        }
        // 1️⃣ ALWAYS generate LLM answer (but don't block for shopping/hotels)
        // ⚡ OPTIMIZATION: Start answer generation in parallel, don't wait for shopping/hotels
        const answerStartTime = Date.now();
        let answerData;
        // Start answer generation (non-blocking for shopping/hotels)
        const answerPromise = getAnswerNonStream(cleanQuery, filteredConversationHistory).catch((err) => {
            console.error("❌ LLM answer generation error:", err.message);
            return {
                summary: `I understand you're asking about "${cleanQuery}". Let me help you with that.`,
                sources: [],
                locations: [],
                destination_images: [],
            };
        });
        // ✅ Use query as temporary answer (will be replaced when real answer arrives)
        let llmAnswer = cleanQuery;
        // 2️⃣ UNIFIED ROUTING ENGINE
        // ⚠️ CRITICAL: Route with ORIGINAL query first to get correct intent
        // DO NOT add memory/context before intent classification!
        const lastTurn = filteredConversationHistory?.length
            ? filteredConversationHistory[filteredConversationHistory.length - 1]
            : null;
        // Route with original query to get correct intent classification
        const routing = await routeQuery({
            query: cleanQuery, // ✅ Use ORIGINAL query for intent classification
            lastTurn,
            llmAnswer,
        });
        console.log("🚦 Routing decision:", routing);
        console.log(`📝 Original query: "${cleanQuery}"`);
        console.log(`🎯 Detected intent: ${routing.finalIntent}, Card type: ${routing.finalCardType}`);
        // 3️⃣ Fetch cards based on routing decision
        let results = [];
        // 🟦 C8.4 — FINAL PIPELINE: Filter → Rerank → Correct
        // 🧠 C11.3 — Final Query Refiner (Memory + LLM)
        const sessionIdForMemory = conversationId ?? userId ?? sessionId ?? "global";
        // ✅ FIX: When image is provided, ALWAYS clear session memory to prevent cached results
        if (imageUrl && imageAnalysis) {
            console.log(`🖼️ ========== IMAGE SEARCH DETECTED ==========`);
            console.log(`🖼️ New image URL: ${imageUrl.substring(0, 80)}...`);
            // ✅ AGGRESSIVE FIX: Always completely DELETE session for image searches (not just reset)
            const session = getSession(sessionIdForMemory);
            if (session) {
                console.log(`🧹 FORCE DELETING session: domain=${session.domain}, brand=${session.brand}, lastImageUrl=${session.lastImageUrl?.substring(0, 40) || 'none'}...`);
                // Completely delete the session (not just reset)
                clearSession(sessionIdForMemory);
            }
            // ✅ ALWAYS create completely fresh session for image searches
            saveSession(sessionIdForMemory, {
                domain: "general",
                brand: null,
                category: null,
                price: null,
                city: null,
                gender: null,
                intentSpecific: {},
                lastQuery: cleanQuery,
                lastAnswer: "",
                lastImageUrl: imageUrl, // ✅ Track the current image URL
            });
            console.log(`✅ Session completely deleted and recreated for new image search`);
        }
        // ✅ FIX: Only apply memory/context enhancement for shopping/hotels/flights/restaurants/places
        // DO NOT enhance informational queries (answer/general) - they should stay as-is
        const finalIntent = routing.finalIntent || "";
        const isShoppingIntent = finalIntent === "shopping" || routing.finalCardType === "shopping";
        const isTravelIntent = ["hotels", "flights", "restaurants", "places", "location"].includes(finalIntent);
        const isMovieIntent = finalIntent === "movies" || routing.finalCardType === "movies";
        const shouldEnhanceQuery = isShoppingIntent || isTravelIntent || isMovieIntent;
        let queryForRefinement = cleanQuery;
        let contextAwareQuery = cleanQuery;
        // ✅ PERSONALIZATION: Detect "of my type" / "of my taste" queries and use user preferences
        const isPersonalizationQuery = /\b(of my (type|taste|style|preference)|in my style|for me|my kind)\b/i.test(cleanQuery);
        if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
            console.log(`🎯 Personalization query detected: "${cleanQuery}"`);
            try {
                const userPrefs = await getUserPreferences(userId);
                if (userPrefs && userPrefs.confidence_score && userPrefs.confidence_score >= 0.3) {
                    console.log(`✅ Found user preferences (confidence: ${userPrefs.confidence_score})`);
                    // Extract category from query (e.g., "glasses of my type" → "glasses")
                    const categoryMatch = cleanQuery.match(/^(.+?)\s+(?:of my|in my|for me|my kind)/i);
                    const baseCategory = categoryMatch ? categoryMatch[1].trim() : cleanQuery.replace(/\b(of my|in my|for me|my kind).*$/i, '').trim();
                    // Build personalized query
                    let personalizedQuery = baseCategory;
                    // Add brand preferences if available
                    if (userPrefs.brand_preferences && userPrefs.brand_preferences.length > 0) {
                        const topBrand = userPrefs.brand_preferences[0];
                        if (!personalizedQuery.toLowerCase().includes(topBrand.toLowerCase())) {
                            personalizedQuery = `${topBrand} ${personalizedQuery}`;
                        }
                    }
                    // Add style keywords if available
                    if (userPrefs.style_keywords && userPrefs.style_keywords.length > 0) {
                        const topStyle = userPrefs.style_keywords[0];
                        if (!personalizedQuery.toLowerCase().includes(topStyle.toLowerCase())) {
                            personalizedQuery = `${personalizedQuery} ${topStyle}`;
                        }
                    }
                    // Add price range if available (for shopping)
                    if (isShoppingIntent && userPrefs.price_range_max) {
                        personalizedQuery = `${personalizedQuery} under $${userPrefs.price_range_max}`;
                    }
                    // Add category-specific preferences
                    if (userPrefs.category_preferences) {
                        const categoryPrefs = userPrefs.category_preferences;
                        const relevantCategory = baseCategory.toLowerCase();
                        // Check if we have preferences for this category
                        for (const [cat, prefs] of Object.entries(categoryPrefs)) {
                            if (relevantCategory.includes(cat) || cat.includes(relevantCategory)) {
                                if (prefs.brands && Array.isArray(prefs.brands) && prefs.brands.length > 0) {
                                    const topBrand = prefs.brands[0];
                                    if (!personalizedQuery.toLowerCase().includes(topBrand.toLowerCase())) {
                                        personalizedQuery = `${topBrand} ${personalizedQuery}`;
                                    }
                                }
                                if (prefs.style && !personalizedQuery.toLowerCase().includes(prefs.style.toLowerCase())) {
                                    personalizedQuery = `${personalizedQuery} ${prefs.style}`;
                                }
                                break;
                            }
                        }
                    }
                    if (personalizedQuery !== cleanQuery) {
                        contextAwareQuery = personalizedQuery;
                        queryForRefinement = personalizedQuery;
                        console.log(`🎯 Personalized query: "${cleanQuery}" → "${personalizedQuery}"`);
                    }
                    else {
                        console.log(`⚠️ User preferences found but couldn't enhance query`);
                    }
                }
                else {
                    console.log(`ℹ️ No user preferences found or confidence too low (${userPrefs?.confidence_score || 0})`);
                }
            }
            catch (err) {
                console.error(`❌ Error retrieving user preferences: ${err.message}`);
                // Continue with normal flow if personalization fails
            }
        }
        // ✅ PHASE 2: Enhance query with user preferences (for all relevant queries)
        if (shouldEnhanceQuery && userId && userId !== "global" && userId !== "dev-user-id") {
            try {
                const category = extractCategoryFromQuery(cleanQuery, finalIntent);
                const preferenceEnhanced = await enhanceQueryWithPreferences(cleanQuery, userId, {
                    intent: finalIntent,
                    category: category,
                    minConfidence: 0.3, // Only apply if confidence >= 30%
                });
                if (preferenceEnhanced !== cleanQuery) {
                    contextAwareQuery = preferenceEnhanced;
                    queryForRefinement = preferenceEnhanced;
                    console.log(`🎯 Phase 2: Preference-enhanced query: "${cleanQuery}" → "${preferenceEnhanced}"`);
                }
            }
            catch (err) {
                console.error(`❌ Error in Phase 2 query enhancement: ${err.message}`);
                // Continue with normal flow if enhancement fails
            }
        }
        // ✅ NEW: Extract parent query from conversation history if not provided
        let extractedParentQuery = parentQuery;
        if (!extractedParentQuery && filteredConversationHistory && filteredConversationHistory.length > 0) {
            // Get the last conversation turn
            const lastTurn = filteredConversationHistory[filteredConversationHistory.length - 1];
            if (lastTurn && lastTurn.query) {
                extractedParentQuery = lastTurn.query;
                console.log(`📚 Extracted parent query from conversation history: "${extractedParentQuery}"`);
            }
        }
        // 🚀 PRODUCTION-GRADE: LLM-Based Context Understanding (replaces brittle keyword matching)
        // Similar to how ChatGPT, Perplexity, and Cursor handle context intelligently
        if (shouldEnhanceQuery && extractedParentQuery) {
            try {
                const { extractContextWithLLM, mergeQueryContextWithLLM } = await import("../services/llmContextExtractor");
                // Step 1: Extract context from current query using LLM (handles all edge cases)
                const extractedContext = await extractContextWithLLM(cleanQuery, extractedParentQuery, filteredConversationHistory);
                // Step 2: Intelligently merge with parent query using LLM
                const mergedQuery = await mergeQueryContextWithLLM(cleanQuery, extractedParentQuery, extractedContext, finalIntent);
                if (mergedQuery !== cleanQuery) {
                    contextAwareQuery = mergedQuery;
                    queryForRefinement = mergedQuery;
                    console.log(`🧠 LLM Context Merging: "${cleanQuery}" → "${mergedQuery}"`);
                }
                else {
                    // LLM determined no merging needed
                    queryForRefinement = cleanQuery;
                }
            }
            catch (err) {
                console.error(`❌ LLM context extraction failed, falling back to rule-based: ${err.message}`);
                // Fallback to rule-based merging (existing logic)
                const { analyzeCardNeed } = await import("../followup/cardAnalyzer");
                const parentSlots = analyzeCardNeed(extractedParentQuery);
                const qLower = cleanQuery.toLowerCase();
                // Detect refinement queries
                const isRefinementQuery = /^(only|just|show|find|get|give me|i want|i need)\s+.*/i.test(cleanQuery.trim()) ||
                    /\b(only|just|more|less|cheaper|expensive|costlier|luxury|budget|premium|star|stars)\b/i.test(cleanQuery) ||
                    /\b(\d+)\s*(star|stars)\b/i.test(cleanQuery);
                // Merge brand if parent has it and follow-up doesn't
                if (parentSlots.brand && !qLower.includes(parentSlots.brand.toLowerCase())) {
                    contextAwareQuery = `${parentSlots.brand} ${contextAwareQuery}`;
                }
                // Merge category if parent has it and follow-up doesn't
                if (parentSlots.category && !qLower.includes(parentSlots.category.toLowerCase())) {
                    contextAwareQuery = `${contextAwareQuery} ${parentSlots.category}`;
                }
                // Merge city if parent has it and follow-up doesn't
                const isTravelIntentForLocation = ["hotels", "flights", "restaurants", "places", "location"].includes(finalIntent);
                if (parentSlots.city && !qLower.includes(parentSlots.city.toLowerCase())) {
                    if (isTravelIntentForLocation || isRefinementQuery) {
                        contextAwareQuery = `${contextAwareQuery} in ${parentSlots.city}`;
                        console.log(`📍 Fallback: Merged location from parent: "${parentSlots.city}" → "${contextAwareQuery}"`);
                    }
                }
                // Merge price if parent has it and follow-up doesn't
                if (parentSlots.price && !qLower.includes(parentSlots.price.toLowerCase())) {
                    contextAwareQuery = `${contextAwareQuery} ${parentSlots.price}`;
                }
                if (contextAwareQuery !== cleanQuery) {
                    console.log(`📍 Fallback: Merged context for ${routing.finalIntent}: "${cleanQuery}" → "${contextAwareQuery}"`);
                }
                queryForRefinement = contextAwareQuery;
            }
        }
        else if (!isPersonalizationQuery) {
            // For answer/general queries, use original query without enhancement
            // BUT: If it's a personalization query, we already set queryForRefinement above
            console.log(`ℹ️ Skipping memory enhancement for ${routing.finalIntent} intent (informational query)`);
            queryForRefinement = cleanQuery;
        }
        // Note: If isPersonalizationQuery is true, queryForRefinement was already set above
        // Only refine query if it's a shopping/travel intent (NOT movies)
        // ✅ Movies should NOT be refined with price filters - use original query
        const refinedQuery = (shouldEnhanceQuery && routing.finalCardType !== "movies")
            ? await refineQueryC11(queryForRefinement, sessionIdForMemory)
            : cleanQuery; // ✅ Keep original query for answer/general/movies intents
        switch (routing.finalCardType) {
            case "shopping":
                // 1. Fetch raw results (with refined query)
                let rawShoppingCards = await searchProducts(refinedQuery);
                // 🧠 C11.4 — Extra search pass if zero results
                if (rawShoppingCards.length === 0) {
                    console.warn("⚠️ Zero results, trying refined query...");
                    const extraRefined = await refineQueryC11(queryForRefinement, sessionIdForMemory);
                    rawShoppingCards = await searchProducts(extraRefined);
                }
                // 2. Hard lexical filters
                rawShoppingCards = applyLexicalFilters(refinedQuery, rawShoppingCards);
                // 3. Soft attribute filters
                rawShoppingCards = await applyAttributeFilters(refinedQuery, rawShoppingCards);
                // 4. Rerank using embeddings (C7) OR Phase 3 preference matching
                const category = extractCategoryFromQuery(cleanQuery, finalIntent);
                if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: "Of My Taste" - Match items to preferences using embeddings
                    console.log(`🎯 Phase 3: Using preference matching for "of my taste" query`);
                    results = await matchItemsToPreferences(rawShoppingCards, userId, finalIntent, category);
                }
                else if (userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: Hybrid reranking (combine query relevance + preferences)
                    console.log(`🎯 Phase 3: Using hybrid reranking (query + preferences)`);
                    results = await hybridRerank(rawShoppingCards, refinedQuery, userId, finalIntent, category, 0.6, 0.4);
                }
                else {
                    // Regular reranking (no preferences)
                    results = await rerankCards(refinedQuery, rawShoppingCards, "shopping");
                }
                // 5. LLM-based correction to remove mismatches
                // ⚡ Get real answer now (should be ready by this point)
                const answerData = await answerPromise;
                llmAnswer = answerData.summary || answerData.answer || cleanQuery;
                console.log(`⏱️ LLM answer generation took: ${Date.now() - answerStartTime}ms`);
                results = await correctCards(refinedQuery, llmAnswer, results);
                // 6. Generate descriptions ONLY for final displayed results (after all filtering)
                if (results.length > 0) {
                    await enrichProductsWithDescriptions(results);
                }
                break;
            case "hotel":
                // 1. Fetch raw results (with refined query)
                let rawHotelCards = await searchHotels(refinedQuery);
                // 🧠 C11.4 — Extra search pass if zero results
                if (rawHotelCards.length === 0) {
                    console.warn("⚠️ Zero results, trying refined query...");
                    const extraRefined = await refineQueryC11(queryForRefinement, sessionIdForMemory);
                    rawHotelCards = await searchHotels(extraRefined);
                }
                // 2. Hard lexical filters (price, etc.)
                rawHotelCards = applyLexicalFilters(refinedQuery, rawHotelCards);
                // 2b. Location filters (downtown, airport, etc.) - NEW
                rawHotelCards = filterHotelsByLocation(rawHotelCards, refinedQuery);
                // 3. Soft attribute filters
                rawHotelCards = await applyAttributeFilters(refinedQuery, rawHotelCards);
                // 4. Rerank using embeddings (C7) OR Phase 3 preference matching
                if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: "Of My Taste" - Match hotels to preferences using embeddings
                    console.log(`🎯 Phase 3: Using preference matching for "of my taste" query`);
                    results = await matchItemsToPreferences(rawHotelCards, userId, finalIntent, undefined);
                }
                else if (userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: Hybrid reranking (combine query relevance + preferences)
                    console.log(`🎯 Phase 3: Using hybrid reranking (query + preferences)`);
                    results = await hybridRerank(rawHotelCards, refinedQuery, userId, finalIntent, undefined, 0.6, 0.4);
                }
                else {
                    // Regular reranking (no preferences)
                    results = await rerankCards(refinedQuery, rawHotelCards, "hotels");
                }
                // 5. LLM-based correction (skipped for hotels - all hotels in location are relevant)
                results = await correctCards(refinedQuery, llmAnswer, results);
                // 6. Generate descriptions ONLY for final displayed results (after all filtering)
                if (results.length > 0) {
                    results = await enrichHotelsWithThemesAndDescriptions(results);
                }
                break;
            case "restaurants":
                // 1. Fetch raw results (with refined query)
                let rawRestaurantCards = await searchRestaurants(refinedQuery);
                // 🧠 C11.4 — Extra search pass if zero results
                if (rawRestaurantCards.length === 0) {
                    console.warn("⚠️ Zero results, trying refined query...");
                    const extraRefined = await refineQueryC11(queryForRefinement, sessionIdForMemory);
                    rawRestaurantCards = await searchRestaurants(extraRefined);
                }
                // 2. Hard lexical filters
                rawRestaurantCards = applyLexicalFilters(refinedQuery, rawRestaurantCards);
                // 2b. Location filters (downtown, airport, etc.) - NEW
                rawRestaurantCards = filterRestaurantsByLocation(rawRestaurantCards, refinedQuery);
                // 3. Soft attribute filters
                rawRestaurantCards = await applyAttributeFilters(refinedQuery, rawRestaurantCards);
                // 4. Rerank using embeddings (C7) OR Phase 3 preference matching
                if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: "Of My Taste" - Match restaurants to preferences using embeddings
                    console.log(`🎯 Phase 3: Using preference matching for "of my taste" query`);
                    results = await matchItemsToPreferences(rawRestaurantCards, userId, finalIntent, undefined);
                }
                else if (userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: Hybrid reranking (combine query relevance + preferences)
                    console.log(`🎯 Phase 3: Using hybrid reranking (query + preferences)`);
                    results = await hybridRerank(rawRestaurantCards, refinedQuery, userId, finalIntent, undefined, 0.6, 0.4);
                }
                else {
                    // Regular reranking (no preferences)
                    results = await rerankCards(refinedQuery, rawRestaurantCards, "restaurants");
                }
                // 5. LLM-based correction
                results = await correctCards(refinedQuery, llmAnswer, results);
                break;
            case "flights":
                // 1. Fetch raw results (with refined query)
                let rawFlightCards = await searchFlights(refinedQuery);
                // 🧠 C11.4 — Extra search pass if zero results
                if (rawFlightCards.length === 0) {
                    console.warn("⚠️ Zero results, trying refined query...");
                    const extraRefined = await refineQueryC11(queryForRefinement, sessionIdForMemory);
                    rawFlightCards = await searchFlights(extraRefined);
                }
                // 2. Hard lexical filters (price, route, etc.)
                rawFlightCards = applyLexicalFilters(refinedQuery, rawFlightCards);
                // 3. Soft attribute filters
                rawFlightCards = await applyAttributeFilters(refinedQuery, rawFlightCards);
                // 4. Rerank using embeddings (C7) OR Phase 3 preference matching
                if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: "Of My Taste" - Match flights to preferences using embeddings
                    console.log(`🎯 Phase 3: Using preference matching for "of my taste" query`);
                    results = await matchItemsToPreferences(rawFlightCards, userId, finalIntent, undefined);
                }
                else if (userId && userId !== "global" && userId !== "dev-user-id") {
                    // ✅ PHASE 3: Hybrid reranking (combine query relevance + preferences)
                    console.log(`🎯 Phase 3: Using hybrid reranking (query + preferences)`);
                    results = await hybridRerank(rawFlightCards, refinedQuery, userId, finalIntent, undefined, 0.6, 0.4);
                }
                else {
                    // Regular reranking (no preferences)
                    results = await rerankCards(refinedQuery, rawFlightCards, "flights");
                }
                // 5. LLM-based correction
                results = await correctCards(refinedQuery, llmAnswer, results);
                break;
            case "places":
                // 🎯 Places Search Engine (LLM-powered) - Use context-aware query if available
                try {
                    const placesQuery = shouldEnhanceQuery ? contextAwareQuery : cleanQuery;
                    results = await searchPlaces(placesQuery);
                    console.log(`✅ Places search: ${results.length} places found for query: "${placesQuery}"`);
                    // Apply location filters (downtown, airport, etc.) - NEW
                    results = filterPlacesByLocation(results, placesQuery);
                    // ✅ PHASE 3: Preference matching for places
                    if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
                        console.log(`🎯 Phase 3: Using preference matching for "of my taste" query`);
                        results = await matchItemsToPreferences(results, userId, finalIntent, undefined);
                    }
                    else if (userId && userId !== "global" && userId !== "dev-user-id") {
                        console.log(`🎯 Phase 3: Using hybrid reranking (query + preferences)`);
                        results = await hybridRerank(results, placesQuery, userId, finalIntent, undefined, 0.6, 0.4);
                    }
                    if (results.length > 0) {
                        const sample = results[0];
                        console.log(`📋 Sample result:`, {
                            name: sample.name,
                            location: sample.location,
                            hasGeo: !!sample.geo,
                            geo: sample.geo,
                            hasImage: !!sample.image_url,
                            image_url: sample.image_url?.substring(0, 50) + '...',
                        });
                    }
                }
                catch (err) {
                    console.error("❌ Places search error:", err.message);
                    results = [];
                }
                break;
            case "location":
                // 🎯 Places Search Engine (LLM-powered) - Use context-aware query if available
                try {
                    const locationQuery = shouldEnhanceQuery ? contextAwareQuery : cleanQuery;
                    results = await searchPlaces(locationQuery);
                    console.log(`✅ Location search: ${results.length} places found for query: "${locationQuery}"`);
                    console.log(`📋 Sample result:`, results[0] || "No results");
                    if (results.length === 0) {
                        console.warn("⚠️ No places returned from searchPlaces for location query");
                    }
                }
                catch (err) {
                    console.error("❌ Location search error:", err.message);
                    console.error("❌ Error stack:", err.stack);
                    results = [];
                }
                break;
            case "movies":
                // 🎬 Movies Search using TMDB API
                try {
                    // Preprocess query: Remove common phrases but preserve movie titles
                    let movieQuery = cleanQuery
                        .replace(/showtimes?/gi, "")
                        .replace(/tickets?/gi, "")
                        .replace(/in\s+[A-Z][a-z\s]+/gi, "") // Remove "in [City]"
                        .replace(/under\s+\$?\d+/gi, "") // Remove "under $200"
                        .replace(/below\s+\$?\d+/gi, "") // Remove "below $200"
                        .replace(/\s+/g, " ") // Normalize whitespace
                        .trim();
                    // Extract year from query
                    const yearMatch = movieQuery.match(/\b(19|20)\d{2}\b/);
                    const targetYear = yearMatch ? parseInt(yearMatch[0], 10) : null;
                    // Remove year from query for title extraction
                    if (targetYear) {
                        movieQuery = movieQuery.replace(/\b(19|20)\d{2}\b/g, "").trim();
                    }
                    // Remove "for good" if it appears before "movie"
                    movieQuery = movieQuery.replace(/for\s+good\s+/gi, "");
                    // If query contains "movie" or "film", extract the title part before it
                    if (movieQuery.toLowerCase().includes("movie") || movieQuery.toLowerCase().includes("film")) {
                        const titleMatch = movieQuery.match(/^(.+?)\s+(?:movie|film)/i);
                        if (titleMatch && titleMatch[1]) {
                            movieQuery = titleMatch[1].trim();
                        }
                        else {
                            movieQuery = movieQuery.replace(/\s*(?:movie|film)\s*/gi, " ").trim();
                        }
                    }
                    // Final cleanup: remove any remaining common words at the end
                    movieQuery = movieQuery.replace(/\s+(?:tickets?|showtimes?|in|near|around)\s*$/i, "").trim();
                    console.log(`🎬 Movie search: "${cleanQuery}" → "${movieQuery}"${targetYear ? ` (Year: ${targetYear})` : ''}`);
                    // Search TMDB
                    let tmdbResults = await searchMovies(movieQuery);
                    console.log(`🎬 TMDB search: ${tmdbResults.results?.length || 0} movies found`);
                    if (!tmdbResults.results || tmdbResults.results.length === 0) {
                        results = [];
                        break;
                    }
                    // Filter by year if specified
                    let filteredResults = [...tmdbResults.results];
                    if (targetYear) {
                        filteredResults = filteredResults.filter((movie) => {
                            if (!movie.release_date)
                                return false;
                            const movieYear = new Date(movie.release_date).getFullYear();
                            return movieYear === targetYear;
                        });
                        // If no exact year match, allow ±1 year
                        if (filteredResults.length === 0) {
                            filteredResults = tmdbResults.results.filter((movie) => {
                                if (!movie.release_date)
                                    return false;
                                const movieYear = new Date(movie.release_date).getFullYear();
                                return Math.abs(movieYear - targetYear) <= 1;
                            });
                        }
                        console.log(`🎯 Filtered to ${filteredResults.length} movies${targetYear ? ` from ${targetYear}` : ''}`);
                    }
                    // Get list of movies currently playing in theaters from TMDB
                    let nowPlayingMovieIds = new Set();
                    let useTimeBasedFallback = false;
                    try {
                        const { getNowPlayingMovies } = await import("@/services/tmdbService");
                        const nowPlaying1 = await getNowPlayingMovies(1, 'US');
                        const nowPlaying2 = await getNowPlayingMovies(2, 'US');
                        const allNowPlaying = [
                            ...(nowPlaying1.results || []),
                            ...(nowPlaying2.results || []),
                        ];
                        nowPlayingMovieIds = new Set(allNowPlaying.map((m) => m.id));
                        console.log(`🎬 Found ${nowPlayingMovieIds.size} movies currently playing in theaters`);
                    }
                    catch (err) {
                        console.warn("⚠️ Failed to fetch now playing movies, falling back to time-based check:", err.message);
                        useTimeBasedFallback = true;
                    }
                    // Helper function for time-based fallback
                    const isMovieInTheatersByDate = (releaseDate) => {
                        if (!releaseDate)
                            return false;
                        try {
                            const release = new Date(releaseDate);
                            const now = new Date();
                            const daysSinceRelease = Math.floor((now.getTime() - release.getTime()) / (1000 * 60 * 60 * 24));
                            const daysUntilRelease = -daysSinceRelease;
                            return (daysSinceRelease >= 0 && daysSinceRelease <= 120) || (daysUntilRelease > 0 && daysUntilRelease <= 30);
                        }
                        catch (e) {
                            return false;
                        }
                    };
                    // Transform TMDB results to card format
                    results = filteredResults.slice(0, 12).map((movie) => {
                        // Check if movie is in theaters
                        const isInTheaters = useTimeBasedFallback
                            ? isMovieInTheatersByDate(movie.release_date)
                            : nowPlayingMovieIds.has(movie.id);
                        return {
                            title: movie.title,
                            description: movie.overview || "",
                            image: movie.poster_path
                                ? `https://image.tmdb.org/t/p/w500${movie.poster_path}`
                                : null,
                            rating: movie.vote_average ? `${movie.vote_average.toFixed(1)}/10` : null,
                            releaseDate: movie.release_date || null,
                            id: movie.id,
                            source: "TMDB",
                            link: `https://www.themoviedb.org/movie/${movie.id}`,
                            isInTheaters: isInTheaters,
                        };
                    });
                    console.log(`✅ Movies search: ${results.length} movies found`);
                    const inTheatersCount = results.filter((m) => m.isInTheaters).length;
                    console.log(`🎬 ${inTheatersCount} of ${results.length} movies are currently in theaters`);
                    // ✅ PHASE 3: Preference matching for movies
                    if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
                        console.log(`🎯 Phase 3: Using preference matching for "of my taste" query`);
                        results = await matchItemsToPreferences(results, userId, finalIntent, undefined);
                    }
                    else if (userId && userId !== "global" && userId !== "dev-user-id") {
                        console.log(`🎯 Phase 3: Using hybrid reranking (query + preferences)`);
                        results = await hybridRerank(results, movieQuery, userId, finalIntent, undefined, 0.6, 0.4);
                    }
                }
                catch (err) {
                    console.error("❌ Movies search error:", err.message);
                    results = [];
                }
                break;
            default:
                // For answer/general queries, check if shouldFetchCards suggests cards
                const cardType = await shouldFetchCards(cleanQuery, llmAnswer);
                // ✅ Use refinedQuery only if it's a shopping/travel intent, otherwise use cleanQuery
                const cardTypeStr = cardType || "";
                const queryForCardSearch = (cardTypeStr === "shopping" || ["hotels", "flights", "restaurants"].includes(cardTypeStr))
                    ? refinedQuery
                    : cleanQuery;
                if (cardTypeStr === "shopping") {
                    let rawShoppingCards2 = await searchProducts(queryForCardSearch);
                    // 🧠 C11.4 — Extra search pass if zero results
                    if (rawShoppingCards2.length === 0) {
                        console.warn("⚠️ Zero results, trying refined query...");
                        const extraRefined = shouldEnhanceQuery
                            ? await refineQueryC11(queryForRefinement, sessionIdForMemory)
                            : cleanQuery;
                        rawShoppingCards2 = await searchProducts(extraRefined);
                        // Apply same filtering pipeline again
                        rawShoppingCards2 = applyLexicalFilters(extraRefined, rawShoppingCards2);
                        rawShoppingCards2 = await applyAttributeFilters(extraRefined, rawShoppingCards2);
                    }
                    rawShoppingCards2 = applyLexicalFilters(queryForCardSearch, rawShoppingCards2);
                    rawShoppingCards2 = await applyAttributeFilters(queryForCardSearch, rawShoppingCards2);
                    results = await rerankCards(queryForCardSearch, rawShoppingCards2, "shopping");
                    results = await correctCards(queryForCardSearch, llmAnswer, results);
                    // Generate descriptions ONLY for final displayed results
                    if (results.length > 0) {
                        await enrichProductsWithDescriptions(results);
                    }
                }
                else if (cardTypeStr === "hotels") {
                    let rawHotelCards2 = await searchHotels(queryForCardSearch);
                    // 🧠 C11.4 — Extra search pass if zero results
                    if (rawHotelCards2.length === 0) {
                        console.warn("⚠️ Zero results, trying refined query...");
                        const extraRefined = shouldEnhanceQuery
                            ? await refineQueryC11(queryForRefinement, sessionIdForMemory)
                            : cleanQuery;
                        rawHotelCards2 = await searchHotels(extraRefined);
                        // Apply same filtering pipeline again
                        rawHotelCards2 = applyLexicalFilters(extraRefined, rawHotelCards2);
                        rawHotelCards2 = await applyAttributeFilters(extraRefined, rawHotelCards2);
                    }
                    rawHotelCards2 = applyLexicalFilters(queryForCardSearch, rawHotelCards2);
                    rawHotelCards2 = filterHotelsByLocation(rawHotelCards2, queryForCardSearch);
                    rawHotelCards2 = await applyAttributeFilters(queryForCardSearch, rawHotelCards2);
                    results = await rerankCards(queryForCardSearch, rawHotelCards2, "hotels");
                    results = await correctCards(queryForCardSearch, llmAnswer, results);
                    // Generate descriptions ONLY for final displayed results
                    if (results.length > 0) {
                        results = await enrichHotelsWithThemesAndDescriptions(results);
                    }
                }
                else if (cardTypeStr === "flights") {
                    let rawFlightCards2 = await searchFlights(queryForCardSearch);
                    // 🧠 C11.4 — Extra search pass if zero results
                    if (rawFlightCards2.length === 0) {
                        console.warn("⚠️ Zero results, trying refined query...");
                        const extraRefined = shouldEnhanceQuery
                            ? await refineQueryC11(queryForRefinement, sessionIdForMemory)
                            : cleanQuery;
                        rawFlightCards2 = await searchFlights(extraRefined);
                        // Apply same filtering pipeline again
                        rawFlightCards2 = applyLexicalFilters(extraRefined, rawFlightCards2);
                        rawFlightCards2 = await applyAttributeFilters(extraRefined, rawFlightCards2);
                    }
                    rawFlightCards2 = applyLexicalFilters(queryForCardSearch, rawFlightCards2);
                    rawFlightCards2 = await applyAttributeFilters(queryForCardSearch, rawFlightCards2);
                    results = await rerankCards(queryForCardSearch, rawFlightCards2, "flights");
                    results = await correctCards(queryForCardSearch, llmAnswer, results);
                }
                else if (cardTypeStr === "restaurants") {
                    let rawRestaurantCards2 = await searchRestaurants(queryForCardSearch);
                    // 🧠 C11.4 — Extra search pass if zero results
                    if (rawRestaurantCards2.length === 0) {
                        console.warn("⚠️ Zero results, trying refined query...");
                        const extraRefined = shouldEnhanceQuery
                            ? await refineQueryC11(queryForRefinement, sessionIdForMemory)
                            : cleanQuery;
                        rawRestaurantCards2 = await searchRestaurants(extraRefined);
                        // Apply same filtering pipeline again
                        rawRestaurantCards2 = applyLexicalFilters(extraRefined, rawRestaurantCards2);
                        rawRestaurantCards2 = await applyAttributeFilters(extraRefined, rawRestaurantCards2);
                    }
                    rawRestaurantCards2 = applyLexicalFilters(queryForCardSearch, rawRestaurantCards2);
                    rawRestaurantCards2 = await applyAttributeFilters(queryForCardSearch, rawRestaurantCards2);
                    results = await rerankCards(queryForCardSearch, rawRestaurantCards2, "restaurants");
                    results = await correctCards(queryForCardSearch, llmAnswer, results);
                }
                else if (cardTypeStr === "places" || cardTypeStr === "location") {
                    // 🎯 Places search for default case - Use original query (places don't need memory enhancement)
                    results = await searchPlaces(cleanQuery);
                    console.log(`✅ Places search (default): ${results.length} places found for query: "${cleanQuery}"`);
                }
                break;
        }
        // Use routing result for response metadata
        const responseIntent = routing.finalIntent;
        console.log(`🎯 Response intent: ${responseIntent}, Card type: ${routing.finalCardType}, Results count: ${results.length}`);
        // ==================================================================
        // 💡 FOLLOW-UP ENGINE — Perplexity-style (with slot memory)
        // ⚡ OPTIMIZATION: Start follow-up generation in parallel with card processing
        // ==================================================================
        const sessionIdForFollowUps = conversationId ?? userId ?? sessionId ?? "global";
        // Start follow-up generation early (don't wait for it to block response)
        const followUpPromise = getFollowUpSuggestions({
            query: cleanQuery,
            answer: llmAnswer,
            intent: responseIntent ?? "answer",
            sessionId: sessionIdForFollowUps,
            lastFollowUp: lastFollowUp || null,
            parentQuery: parentQuery || null,
            cards: results || [],
            routingSlots: {
                brand: routing.brand,
                category: routing.category,
                price: routing.price,
                city: routing.city,
            },
        }).catch((e) => {
            console.error("❌ Follow-up generation error:", e.message || e);
            return {
                suggestions: [],
                cardType: "none",
                shouldReturnCards: false,
                slots: { brand: null, category: null, price: null, city: null },
                behaviorState: null,
            };
        });
        // ⚡ OPTIMIZATION: For initial queries, skip enforced cards check (they're already fetched above)
        // Only process enforced cards for follow-up queries that explicitly request cards
        let enforcedCards = [];
        let shouldReturnCards = false;
        let expectedCardType = null;
        let mergedQuery = cleanQuery;
        // Only wait for follow-up payload if we need it for enforced cards
        // For initial queries, we can proceed without it
        if (lastFollowUp || parentQuery) {
            // This is a follow-up query - wait for follow-up payload to check if we need enforced cards
            const followUpPayloadForEnforced = await followUpPromise;
            shouldReturnCards = followUpPayloadForEnforced.shouldReturnCards;
            expectedCardType = followUpPayloadForEnforced.cardType;
            mergedQuery = mergeQueryWithContext(cleanQuery, followUpPayloadForEnforced.slots || {
                brand: null,
                category: null,
                price: null,
                city: null,
            });
            if (shouldReturnCards) {
                // Use merged query for all follow-up card searches
                switch (expectedCardType) {
                    case "shopping": {
                        let enforcedRaw = await searchProducts(mergedQuery);
                        // 🧠 C11.4 — Extra search pass if zero results
                        if (enforcedRaw.length === 0) {
                            console.warn("⚠️ Zero results, trying refined query...");
                            const extraRefined = await refineQueryC11(mergedQuery, sessionIdForFollowUps);
                            enforcedRaw = await searchProducts(extraRefined);
                            // Apply same filtering pipeline again
                            enforcedRaw = applyLexicalFilters(extraRefined, enforcedRaw);
                            enforcedRaw = await applyAttributeFilters(extraRefined, enforcedRaw);
                        }
                        enforcedRaw = applyLexicalFilters(mergedQuery, enforcedRaw);
                        enforcedRaw = await applyAttributeFilters(mergedQuery, enforcedRaw);
                        enforcedCards = await rerankCards(mergedQuery, enforcedRaw, "shopping");
                        enforcedCards = await correctCards(mergedQuery, llmAnswer, enforcedCards);
                        // Generate descriptions ONLY for final displayed results
                        if (enforcedCards.length > 0) {
                            await enrichProductsWithDescriptions(enforcedCards);
                        }
                        break;
                    }
                    case "hotel": {
                        let enforcedRaw = await searchHotels(mergedQuery);
                        // 🧠 C11.4 — Extra search pass if zero results
                        if (enforcedRaw.length === 0) {
                            console.warn("⚠️ Zero results, trying refined query...");
                            const extraRefined = await refineQueryC11(mergedQuery, sessionIdForFollowUps);
                            enforcedRaw = await searchHotels(extraRefined);
                            // Apply same filtering pipeline again
                            enforcedRaw = applyLexicalFilters(extraRefined, enforcedRaw);
                            enforcedRaw = filterHotelsByLocation(enforcedRaw, extraRefined);
                            enforcedRaw = await applyAttributeFilters(extraRefined, enforcedRaw);
                        }
                        enforcedRaw = applyLexicalFilters(mergedQuery, enforcedRaw);
                        enforcedRaw = filterHotelsByLocation(enforcedRaw, mergedQuery);
                        enforcedRaw = await applyAttributeFilters(mergedQuery, enforcedRaw);
                        enforcedCards = await rerankCards(mergedQuery, enforcedRaw, "hotels");
                        enforcedCards = await correctCards(mergedQuery, llmAnswer, enforcedCards);
                        // Generate descriptions ONLY for final displayed results
                        if (enforcedCards.length > 0) {
                            enforcedCards = await enrichHotelsWithThemesAndDescriptions(enforcedCards);
                        }
                        break;
                    }
                    case "restaurants": {
                        let enforcedRaw = await searchRestaurants(mergedQuery);
                        // 🧠 C11.4 — Extra search pass if zero results
                        if (enforcedRaw.length === 0) {
                            console.warn("⚠️ Zero results, trying refined query...");
                            const extraRefined = await refineQueryC11(mergedQuery, sessionIdForFollowUps);
                            enforcedRaw = await searchRestaurants(extraRefined);
                            // Apply same filtering pipeline again
                            enforcedRaw = applyLexicalFilters(extraRefined, enforcedRaw);
                            enforcedRaw = await applyAttributeFilters(extraRefined, enforcedRaw);
                        }
                        enforcedRaw = applyLexicalFilters(mergedQuery, enforcedRaw);
                        enforcedRaw = await applyAttributeFilters(mergedQuery, enforcedRaw);
                        enforcedCards = await rerankCards(mergedQuery, enforcedRaw, "restaurants");
                        enforcedCards = await correctCards(mergedQuery, llmAnswer, enforcedCards);
                        break;
                    }
                    case "flights": {
                        let enforcedRaw = await searchFlights(mergedQuery);
                        // 🧠 C11.4 — Extra search pass if zero results
                        if (enforcedRaw.length === 0) {
                            console.warn("⚠️ Zero results, trying refined query...");
                            const extraRefined = await refineQueryC11(mergedQuery, sessionIdForFollowUps);
                            enforcedRaw = await searchFlights(extraRefined);
                            // Apply same filtering pipeline again
                            enforcedRaw = applyLexicalFilters(extraRefined, enforcedRaw);
                            enforcedRaw = await applyAttributeFilters(extraRefined, enforcedRaw);
                        }
                        enforcedRaw = applyLexicalFilters(mergedQuery, enforcedRaw);
                        enforcedRaw = await applyAttributeFilters(mergedQuery, enforcedRaw);
                        enforcedCards = await rerankCards(mergedQuery, enforcedRaw, "flights");
                        enforcedCards = await correctCards(mergedQuery, llmAnswer, enforcedCards);
                        break;
                    }
                    case "places": {
                        // 🎯 Places follow-up cards (LLM-powered)
                        try {
                            enforcedCards = await searchPlaces(mergedQuery);
                            console.log(`✅ Places follow-up search: ${enforcedCards.length} places found`);
                        }
                        catch (err) {
                            console.error("❌ Places follow-up search error:", err.message);
                            enforcedCards = [];
                        }
                        break;
                    }
                }
            }
        }
        else {
            // Initial query - follow-ups will be awaited later, don't block here
        }
        // ⚡ OPTIMIZATION: Don't block on follow-ups - use timeout (follow-ups are nice-to-have)
        // Follow-ups can take 3-10 seconds (embedding calls), but we shouldn't wait that long
        let followUpPayload;
        try {
            followUpPayload = await Promise.race([
                followUpPromise,
                new Promise((resolve) => setTimeout(() => {
                    console.warn("⚠️ Follow-up generation timed out (5s), using fallback");
                    resolve({
                        suggestions: [],
                        cardType: "none",
                        shouldReturnCards: false,
                        slots: { brand: null, category: null, price: null, city: null },
                        behaviorState: null,
                    });
                }, 5000) // 5 second timeout for follow-ups
                )
            ]);
        }
        catch (err) {
            console.warn("⚠️ Follow-up generation failed, using fallback:", err.message);
            followUpPayload = {
                suggestions: [],
                cardType: "none",
                shouldReturnCards: false,
                slots: { brand: null, category: null, price: null, city: null },
                behaviorState: null,
            };
        }
        // Final cards → either original or enforced ones
        let finalCards = enforcedCards.length > 0 ? enforcedCards : results;
        // ✅ C6 PATCH #3 — Minimum Card Threshold Logic
        if (finalCards.length < 3 && (responseIntent === "shopping" || responseIntent === "hotels")) {
            console.warn("⚠️ Low card count, retrying with refined query...");
            try {
                const refined = await refineQuery(cleanQuery, responseIntent);
                if (responseIntent === "shopping") {
                    let refinedRaw = await searchProducts(refined);
                    refinedRaw = applyLexicalFilters(refined, refinedRaw);
                    refinedRaw = await applyAttributeFilters(refined, refinedRaw);
                    const refinedResults = await rerankCards(refined, refinedRaw, "shopping");
                    const correctedResults = await correctCards(refined, llmAnswer, refinedResults);
                    // Generate descriptions ONLY for final results
                    if (correctedResults.length > 0) {
                        await enrichProductsWithDescriptions(correctedResults);
                    }
                    if (correctedResults.length > finalCards.length) {
                        finalCards = correctedResults;
                        console.log(`✅ Refined query returned ${correctedResults.length} cards`);
                    }
                }
                else if (responseIntent === "hotels") {
                    let refinedRaw = await searchHotels(refined);
                    refinedRaw = applyLexicalFilters(refined, refinedRaw);
                    refinedRaw = filterHotelsByLocation(refinedRaw, refined);
                    refinedRaw = await applyAttributeFilters(refined, refinedRaw);
                    const refinedResults = await rerankCards(refined, refinedRaw, "hotels");
                    const correctedResults = await correctCards(refined, llmAnswer, refinedResults);
                    // Generate descriptions ONLY for final results
                    if (correctedResults.length > 0) {
                        const enriched = await enrichHotelsWithThemesAndDescriptions(correctedResults);
                        if (enriched.length > finalCards.length) {
                            finalCards = enriched;
                        }
                        else {
                            finalCards = correctedResults;
                        }
                    }
                    else if (correctedResults.length > finalCards.length) {
                        finalCards = correctedResults;
                    }
                    if (finalCards.length > 0) {
                        console.log(`✅ Refined query returned ${finalCards.length} cards`);
                    }
                }
            }
            catch (err) {
                console.error("❌ Query refinement retry failed:", err.message);
            }
        }
        // ✅ C6 PATCH #4 — Force Cards Only When Needed
        const mustShowCards = responseIntent === "shopping" ||
            responseIntent === "hotels" ||
            responseIntent === "flights" ||
            responseIntent === "restaurants" ||
            responseIntent === "places" ||
            responseIntent === "location" ||
            responseIntent === "movies" || // ✅ Add movies to mustShowCards
            shouldReturnCards; // follow-up ask
        // 🧠 C9.4 — Memory-Aware Card Filtering
        // ⚠️ Skip memory filtering for places/location/movies (they don't have brand/category/price/gender)
        const isPlacesOrLocationOrMovies = responseIntent === "places" || responseIntent === "location" || responseIntent === "movies";
        let memoryFilteredCards = finalCards;
        if (!isPlacesOrLocationOrMovies) {
            const session = getSession(sessionIdForMemory);
            if (session) {
                // Filter by brand if session has brand
                if (session.brand) {
                    memoryFilteredCards = memoryFilteredCards.filter((c) => {
                        const title = (c.title || c.name || "").toLowerCase();
                        return title.includes(session.brand.toLowerCase());
                    });
                    console.log(`🧠 Memory filter (brand: ${session.brand}): ${memoryFilteredCards.length} cards`);
                }
                // Filter by category if session has category
                if (session.category) {
                    memoryFilteredCards = memoryFilteredCards.filter((c) => {
                        const title = (c.title || c.name || "").toLowerCase();
                        const category = (c.category || "").toLowerCase();
                        return title.includes(session.category.toLowerCase()) ||
                            category.includes(session.category.toLowerCase());
                    });
                    console.log(`🧠 Memory filter (category: ${session.category}): ${memoryFilteredCards.length} cards`);
                }
                // Filter by price if session has price
                if (session.price) {
                    memoryFilteredCards = memoryFilteredCards.filter((c) => {
                        const priceText = c.price || c.extracted_price || "";
                        const priceMatch = priceText.toString().replace(/,/g, "").match(/\$?(\d{2,5})(\.\d+)?/);
                        if (!priceMatch)
                            return true; // Keep items without price
                        const itemPrice = parseFloat(priceMatch[1]);
                        return itemPrice <= session.price;
                    });
                    console.log(`🧠 Memory filter (price: $${session.price}): ${memoryFilteredCards.length} cards`);
                }
                // Filter by gender if session has gender
                if (session.gender) {
                    memoryFilteredCards = memoryFilteredCards.filter((c) => {
                        const title = (c.title || c.name || "").toLowerCase();
                        const category = (c.category || "").toLowerCase();
                        if (session.gender === "men") {
                            return /men|male|mens/i.test(title) || /men|male/i.test(category);
                        }
                        else {
                            return /women|woman|female|girls|womens/i.test(title) || /women|female/i.test(category);
                        }
                    });
                    console.log(`🧠 Memory filter (gender: ${session.gender}): ${memoryFilteredCards.length} cards`);
                }
            }
        }
        else {
            console.log(`📍 Skipping memory filtering for ${responseIntent} (places/location/movies don't have brand/category/price/gender)`);
        }
        // ✅ C6 PATCH #8 — NEVER Return Empty Cards to Frontend
        let safeCards = mustShowCards ? (memoryFilteredCards && memoryFilteredCards.length > 0 ? memoryFilteredCards : finalCards) : [];
        // 🎯 Safety check: If mustShowCards is true but we have no cards, use finalCards directly
        if (mustShowCards && safeCards.length === 0 && finalCards.length > 0) {
            console.warn(`⚠️ Safe cards empty but finalCards has ${finalCards.length} items, using finalCards`);
            safeCards = finalCards;
        }
        console.log(`📦 Final cards: ${finalCards.length}, Memory filtered: ${memoryFilteredCards.length}, Safe cards: ${safeCards.length}, Must show: ${mustShowCards}`);
        // 🎯 Final safety: Log if we're about to send empty cards when we should have them
        if (mustShowCards && safeCards.length === 0) {
            console.error(`❌ CRITICAL: mustShowCards=true but safeCards is empty! Response intent: ${responseIntent}, Card type: ${routing.finalCardType}`);
        }
        // Build response - ALWAYS include answer, even if no cards
        // ⚡ Ensure we have the real answer (should be ready by now, but use timeout)
        let finalAnswerData;
        try {
            finalAnswerData = await Promise.race([
                answerPromise,
                new Promise((resolve) => setTimeout(() => resolve({
                    summary: `Here are the results for "${cleanQuery}".`,
                    answer: `Here are the results for "${cleanQuery}".`,
                    sources: [],
                    locations: [],
                    destination_images: [],
                }), 3000) // 3 second timeout for answer
                )
            ]);
        }
        catch (err) {
            console.warn("⚠️ Answer generation timed out, using fallback");
            finalAnswerData = {
                summary: `Here are the results for "${cleanQuery}".`,
                answer: `Here are the results for "${cleanQuery}".`,
                sources: [],
                locations: [],
                destination_images: [],
            };
        }
        console.log(`⏱️ Total LLM answer generation time: ${Date.now() - answerStartTime}ms`);
        console.log(`📤 Sending response - Intent: ${responseIntent}, Cards: ${safeCards.length}, CardType: ${routing.finalCardType}`);
        // ✅ PERSONALIZATION: Store preference signals (non-blocking, async)
        // Only store if we have cards and a valid user ID
        if (safeCards.length > 0 && userId && userId !== "global" && userId !== "dev-user-id") {
            // Extract signals in background (don't block response)
            setImmediate(async () => {
                try {
                    const signals = extractPreferenceSignals(cleanQuery, responseIntent || "", safeCards);
                    await storePreferenceSignal({
                        user_id: userId,
                        conversation_id: conversationId || undefined,
                        query: cleanQuery,
                        intent: responseIntent || undefined,
                        style_keywords: signals.style_keywords,
                        price_mentions: signals.price_mentions,
                        brand_mentions: signals.brand_mentions,
                        rating_mentions: signals.rating_mentions,
                        cards_shown: safeCards.slice(0, 20), // Store top 20 cards
                        user_interaction: {}, // Future: track clicks, time spent
                    });
                    // ✅ PHASE 4: Increment conversation count and check if aggregation is needed
                    incrementConversationCount(userId);
                    // Check if aggregation is needed (non-blocking)
                    setImmediate(async () => {
                        await aggregateIfNeeded(userId);
                    });
                }
                catch (err) {
                    // Silent fail - don't log errors for non-critical personalization
                    console.error("⚠️ Preference signal storage failed (non-critical):", err.message);
                }
            });
        }
        const responseData = {
            success: true,
            intent: responseIntent,
            summary: finalAnswerData.summary || finalAnswerData.answer || `Here are the results for "${cleanQuery}".`,
            answer: finalAnswerData.summary || finalAnswerData.answer || `Here are the results for "${cleanQuery}".`,
            cardType: routing.finalCardType, // ✅ Use routing decision
            // ✅ Follow-up engine data (Perplexity-style)
            followUps: followUpPayload.suggestions, // Main field
            followUpSuggestions: followUpPayload.suggestions, // Keep for backward compatibility
            followUpCardType: expectedCardType,
            shouldReturnCards: shouldReturnCards,
            slots: {
                brand: routing.brand || followUpPayload.slots.brand,
                category: routing.category || followUpPayload.slots.category,
                price: routing.price || followUpPayload.slots.price,
                city: routing.city || followUpPayload.slots.city,
            },
            behavior: followUpPayload.behaviorState, // Main field
            behaviorState: followUpPayload.behaviorState, // Keep for backward compatibility
        };
        // ✅ Perplexity-style: Group hotels AFTER all filtering/reranking/correction
        if (routing.finalCardType === "hotel" && Array.isArray(safeCards) && safeCards.length > 0) {
            const { groupHotels } = await import("../services/hotelGrouping");
            const grouped = groupHotels(safeCards);
            // Extract map points from final cards
            const mapPoints = safeCards
                .filter((h) => h.latitude && h.longitude)
                .map((h) => ({
                lat: h.latitude,
                lng: h.longitude,
                name: h.name || h.title || "Unknown",
                rating: h.rating || h.overall_rating || 0,
            }));
            // Build sections array, filtering out empty sections
            const sections = [];
            if (grouped.luxury.length > 0) {
                sections.push({ title: "Luxury hotels", items: grouped.luxury });
            }
            if (grouped.midrange.length > 0) {
                sections.push({ title: "Midrange hotels", items: grouped.midrange });
            }
            if (grouped.boutique.length > 0) {
                sections.push({ title: "Boutique hotels", items: grouped.boutique });
            }
            if (grouped.budget.length > 0) {
                sections.push({ title: "Budget options", items: grouped.budget });
            }
            // Set Perplexity-style response structure
            responseData.sections = sections;
            responseData.map = mapPoints;
            // Remove old flat card lists (Perplexity doesn't send them)
            // Keep for backward compatibility if needed, but sections is the main field
            // responseData.results = safeCards;
            // responseData.products = safeCards;
            // responseData.cards = safeCards;
            console.log(`🏨 Hotel response: ${sections.length} sections, ${safeCards.length} total hotels, ${mapPoints.length} map points`);
        }
        else {
            // Standard response (shopping, restaurants, etc.) - flat array
            responseData.results = safeCards;
            responseData.products = safeCards;
            responseData.cards = safeCards;
        }
        // ✅ ALWAYS include answer-specific fields (already fetched above)
        responseData.sources = finalAnswerData.sources || [];
        responseData.locations = finalAnswerData.locations || [];
        responseData.destination_images = finalAnswerData.destination_images || [];
        // ✅ NEW: Include image analysis data if image was provided
        if (imageAnalysis) {
            responseData.imageAnalysis = {
                description: imageAnalysis.description,
                keywords: imageAnalysis.keywords,
            };
            console.log(`🖼️ Image analysis included in response: ${imageAnalysis.description.substring(0, 60)}...`);
        }
        // 🧠 C9.1 — Memory Update After EACH Query
        const detectedGender = detectGender(cleanQuery);
        const priceNumber = followUpPayload.slots.price
            ? parseInt(followUpPayload.slots.price.toString().replace(/[^\d]/g, ""))
            : null;
        saveSession(sessionIdForMemory, {
            domain: responseIntent,
            brand: routing.brand || followUpPayload.slots.brand || null,
            category: routing.category || followUpPayload.slots.category || null,
            price: priceNumber,
            city: routing.city || followUpPayload.slots.city || null,
            gender: detectedGender,
            intentSpecific: (followUpPayload.behaviorState?.interestPattern && typeof followUpPayload.behaviorState.interestPattern === 'object')
                ? followUpPayload.behaviorState.interestPattern
                : {},
            lastQuery: cleanQuery,
            lastAnswer: llmAnswer,
        });
        res.json(responseData);
        return;
    }
    catch (err) {
        console.error("❌ Agent error:", err);
        if (!res.headersSent) {
            res.status(500).json({ error: "Agent failed", detail: err.message });
            return;
        }
    }
}
/**
 * MAIN AGENT ENDPOINT
 * Handles:
 * - First queries
 * - Follow-up queries
 * - Streaming or non-stream
 * ✅ FIX: Added request queuing to prevent overwhelming the system
 */
router.post("/", async (req, res) => {
    // ✅ FIX: Check queue size
    if (requestQueue.length >= MAX_QUEUE_SIZE) {
        return res.status(503).json({
            error: "Server busy",
            message: "Too many requests in queue. Please try again in a moment."
        });
    }
    // ✅ FIX: If we have capacity, process immediately
    if (processingCount < MAX_CONCURRENT_REQUESTS) {
        processingCount++;
        try {
            await handleRequest(req, res);
        }
        catch (err) {
            console.error("❌ Request error:", err);
            if (!res.headersSent) {
                res.status(500).json({ error: "Request failed", detail: err.message });
            }
        }
        finally {
            processingCount--;
            processQueue();
        }
    }
    else {
        // ✅ FIX: Queue the request
        await new Promise((resolve) => {
            requestQueue.push({ req, res, resolve });
            processQueue();
        });
    }
});
export default router;

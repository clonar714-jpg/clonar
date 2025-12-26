/**
 * ✅ SIMPLIFIED LANGCHAIN-STYLE HANDLER
 *
 * Simple flow: Query → PerplexityAnswer → Response
 * No complexity, no cards, no intent detection
 */
import { validateAgentRequest } from "./agent.validation";
import { createErrorResponse } from "../utils/errorResponse";
import { generatePerplexityAnswer } from "../services/perplexityAnswer";
/**
 * ✅ SIMPLIFIED: Just call PerplexityAnswer and return response
 */
export async function handleAgentRequestSimple(req, res) {
    try {
        // Validate request
        const validation = validateAgentRequest(req.body);
        if (!validation.success) {
            res.status(400).json(createErrorResponse('Invalid request body', validation.error));
            return;
        }
        const body = validation.data;
        const query = body.query.trim();
        if (!query || query.length === 0) {
            res.status(400).json(createErrorResponse('Query cannot be empty'));
            return;
        }
        // Build conversation history
        const conversationHistory = (body.conversationHistory || []).map((h) => ({
            query: h.query,
            summary: h.summary,
            answer: h.summary, // Use summary as answer for history
        }));
        // ✅ OPTIMIZED: Streaming enabled by default for better UX (feels instant)
        // Check both query parameter (from Flutter) and body parameter
        const streamFromQuery = req.query.stream === 'true' || String(req.query.stream) === 'true';
        const streamFromBody = body.stream !== false && body.stream !== 'false';
        const shouldStream = streamFromQuery || streamFromBody;
        console.log(`🔍 Streaming check: query.stream=${req.query.stream}, body.stream=${body.stream}, shouldStream=${shouldStream}`);
        // ✅ SIMPLIFIED: Just call PerplexityAnswer service
        console.log(`🔍 Processing query: "${query}"${shouldStream ? ' (streaming)' : ''}`);
        const result = await generatePerplexityAnswer(query, conversationHistory, shouldStream, res);
        // ✅ IMPROVEMENT: If streaming, response already sent
        if (shouldStream && res.headersSent) {
            return;
        }
        // ✅ SIMPLIFIED: Return clean response
        // ✅ FIX: Filter out FOLLOW_UP_SUGGESTIONS sections before sending
        const filteredSections = result.sections.filter((section) => !section.title?.toUpperCase().includes('FOLLOW_UP_SUGGESTIONS'));
        res.json({
            success: true,
            intent: "answer",
            summary: result.summary,
            answer: result.answer,
            sections: filteredSections, // ✅ Use filtered sections
            sources: result.sources,
            followUpSuggestions: result.followUpSuggestions,
            // ✅ PERPLEXITY-STYLE: Include search images from all domains (web, products, hotels, places, movies)
            destination_images: result.searchImages.map(img => img.url), // Extract URLs for Flutter
            // ✅ PERPLEXITY-STYLE: Include structured cards for all domains
            cards: {
                products: result.cards.products,
                hotels: result.cards.hotels,
                places: result.cards.places,
                movies: result.cards.movies,
            },
            // Legacy fields (empty for compatibility)
            results: [],
            locationCards: [],
        });
    }
    catch (err) {
        console.error("❌ Request error:", err);
        if (!res.headersSent) {
            res.status(500).json(createErrorResponse("Request failed", err.message));
        }
    }
}

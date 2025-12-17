// src/routes/hotelDetails.ts
import express from "express";
import OpenAI from "openai";
// Lazy-load OpenAI client
let clientInstance = null;
function getOpenAIClient() {
    if (!clientInstance) {
        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey) {
            throw new Error("Missing OPENAI_API_KEY environment variable");
        }
        clientInstance = new OpenAI({
            apiKey: apiKey,
        });
    }
    return clientInstance;
}
const router = express.Router();
/**
 * Perplexity-style hotel intelligence generator
 * Generates all hotel sections: whatPeopleSay, reviewSummary, chooseThisIf, about, amenitiesClean, locationSummary, ratingInsights
 */
router.post("/", async (req, res) => {
    try {
        const { name, location, address, rating, reviewCount, description, amenities, nearby, cleanliness, rooms, service, sleepQuality, value, locationRating } = req.body;
        if (!name) {
            return res.status(400).json({ error: "Hotel name is required" });
        }
        // Build comprehensive hotel data object - auto-adapts to any fields present
        // This structure works with minimal SerpAPI data and automatically uses richer data when available
        const hotelData = {
            name,
            ...(location && { location }),
            ...(address && { address }),
            ...(rating && { rating }),
            ...(reviewCount && { reviewCount }),
            ...(description && { description }),
            ...(amenities && Array.isArray(amenities) && { amenities }),
            ...(nearby && { nearby }),
            // Rating breakdowns (if available from any source)
            ...(cleanliness && { cleanliness }),
            ...(rooms && { rooms }),
            ...(service && { service }),
            ...(sleepQuality && { sleepQuality }),
            ...(value && { value }),
            ...(locationRating && { locationRating }),
            // Future-proof: Include any additional fields that might be present
            // The AI will automatically use them if they appear
            ...(req.body.reviews && { reviews: req.body.reviews }),
            ...(req.body.review_snippets && { review_snippets: req.body.review_snippets }),
            ...(req.body.ratings_breakdown && { ratings_breakdown: req.body.ratings_breakdown }),
            ...(req.body.airport_distance && { airport_distance: req.body.airport_distance }),
            ...(req.body.nearby_places && { nearby_places: req.body.nearby_places }),
            ...(req.body.hotel_class && { hotel_class: req.body.hotel_class }),
            ...(req.body.tags && { tags: req.body.tags }),
            ...(req.body.geo && { geo: req.body.geo }),
        };
        const systemPrompt = `You are an AI subsystem inside a production hotel search engine (similar to Perplexity, Google Hotels, and TripAdvisor AI summaries).

Your job: Generate structured, grounded hotel intelligence using ANY hotel object passed to you — whether minimal (SerpAPI) or rich (Booking.com, Expedia, TripAdvisor, Google Hotels).

The system MUST:
- Work today using only SerpAPI fields.
- Automatically adapt to new API fields when they appear.
- Never hallucinate missing data.
- Always produce all sections cleanly, with fallbacks when fields are absent.

=====================================================
🎯 SMART DATA HANDLING RULES
=====================================================

✓ If TripAdvisor reviews exist → extract themes, sentiments, and specific feedback
✓ If rating breakdown exists → use it for ratingInsights and reviewSummary
✓ If amenities exist → clean + list them with specific details
✓ If description exists → rewrite it as "About" with awards, history, positioning
✓ If location info is available → summarize it with nearby attractions
✓ If only basic SerpAPI data is present → generate grounded but simple text
✓ If richer TripAdvisor API data appears → instantly use it without code changes
✓ Always follow Perplexity's exact content patterns and structure

Never fabricate amenities, distances, neighborhood names, or features not present in the input object.

=====================================================
🧠 SECTIONS TO GENERATE
=====================================================

Generate all 7 sections:

1) **whatPeopleSay** (3–5 sentences, 150-250 words)
   - Structure: Opening (hotel type/style) → Core strengths (what reviews highlight) → Specific features (standout aspects) → Balanced view (light criticism) → Target audience (who it's best for)
   - Extract common themes from reviews if available
   - Mention specific aspects: service, cleanliness, accommodations, dining
   - Include balanced perspective: praise + light criticism
   - Identify target audience: corporate retreats, families, business travelers, etc.
   - DO NOT repeat the hotel name
   - Follow Perplexity's exact style: "Hotel offers [type] experience with emphasis on [strength]. Reviews highlight [aspect1], [aspect2], and [aspect3]. [Theme] is consistently mentioned. [Balanced criticism]. The property aligns well with [target audience]."

2) **reviewSummary** (4–6 sentences, 150-200 words)
   - Structure: Overall sentiment → Detailed themes → Rating breakdown → Guest feedback → Balanced view
   - Include deeper themes from reviews, if available
   - Mention detailed feedback: cleanliness, rooms, service, value, location
   - Reference specific rating categories with numbers if available
   - If no reviews → fallback to "Guests generally appreciate…" style
   - Sound like TripAdvisor AI-generated summaries
   - No marketing hype, only data-grounded insights

3) **chooseThisIf** (1–2 sentences, 30-60 words)
   - Structure: "You want..." or "Choose this if you want..." → Key characteristics → Specific benefits
   - Based on amenities, location, rating, hotel class
   - Adaptive: luxury, budget, airport proximity, family-friendly, business
   - Be direct and actionable
   - Example: "You want an authentic European-style ski lodge experience with world-class service, mid-mountain access, and exceptional offsite facilities."
   - No hallucination—only use provided metadata

4) **about** (4–6 sentences, 200-300 words)
   - Structure: Awards/Recognition → History/Heritage → Location Context → Positioning → Experience → Philosophy
   - Start with awards/recognition if available ("Best Ski Hotel in the World" by World Ski Awards)
   - Include historical context if available ("Named after Norwegian Olympic Gold Medal skier...")
   - Describe location in detail ("nestled mid-mountain in the alpine setting at...")
   - Highlight unique selling points ("authentic European ski lodge")
   - Describe guest experience ("legendary services and accommodations, world-renowned skiing")
   - End with brand philosophy ("More than just a resort hotel, [name] has become a legend...")
   - If description missing → generate neutral functional description using known amenities, class, location
   - Clean, Perplexity-style "About" section

5) **amenitiesClean** (formatted list)
   - Clean, unique, capitalized
   - Auto-adapt to any future API fields
   - Remove duplicates, format properly

6) **locationSummary** (1–2 sentences, 40-80 words)
   - Structure: Location description → Nearby attractions → Accessibility
   - Describe location context in detail
   - Mention nearby attractions/points of interest if available
   - Include accessibility information if available
   - No hallucinated distances or landmarks
   - If minimal location data → fallback generic

7) **ratingInsights** (1–2 sentences, 30-60 words)
   - Structure: Overall rating context → Specific category highlights → Comparison or standout aspects
   - Mention specific rating categories with actual numbers
   - Highlight strengths (highest ratings)
   - Note any weaknesses (lowest ratings)
   - Use data-driven insights
   - Example: "Guests consistently praise the hotel's cleanliness (4.9) and rooms (4.8), while value receives slightly lower scores (4.4)."
   - If breakdown missing → fallback to single overall rating with context

=====================================================
📌 OUTPUT FORMAT (REQUIRED)
=====================================================

Return ONLY this JSON object:

{
  "whatPeopleSay": "...",
  "reviewSummary": "...",
  "chooseThisIf": "...",
  "about": "...",
  "amenitiesClean": [...],
  "locationSummary": "...",
  "ratingInsights": "..."
}

Return ONLY valid JSON, no markdown, no extra text.

=====================================================
📌 IMPORTANT
=====================================================

- NEVER hallucinate specific distances, landmarks, or amenities.
- NEVER invent numbers or review counts.
- ALWAYS stay grounded in the provided object.
- ALWAYS generate fluid, human-sounding text like Perplexity + TripAdvisor AI.
- ALWAYS adapt automatically if new fields appear.
- Use third-person objective tone.
- Avoid overly promotional language.
- If reviews appear positive/negative, reflect that fairly.`;
        try {
            const client = getOpenAIClient();
            const response = await client.chat.completions.create({
                model: "gpt-4o-mini",
                temperature: 0.5,
                messages: [
                    { role: "system", content: systemPrompt },
                    {
                        role: "user",
                        content: `Generate all Perplexity-style hotel sections for:\n\n${JSON.stringify(hotelData, null, 2)}\n\nReturn ONLY the JSON object with all required fields.`,
                    },
                ],
            });
            const content = response.choices[0]?.message?.content || "";
            // Try to parse JSON from response
            let hotelDetails = {};
            try {
                // Extract JSON from markdown code blocks if present
                const jsonMatch = content.match(/\{[\s\S]*\}/);
                if (jsonMatch) {
                    hotelDetails = JSON.parse(jsonMatch[0]);
                }
                else {
                    hotelDetails = JSON.parse(content);
                }
            }
            catch (e) {
                console.error("❌ Failed to parse LLM response as JSON:", e);
                // Fallback to default values
                hotelDetails = getDefaultHotelDetails(hotelData);
            }
            // Ensure all required fields exist with fallbacks
            hotelDetails = {
                whatPeopleSay: hotelDetails.whatPeopleSay || getDefaultWhatPeopleSay(name, location, rating),
                reviewSummary: hotelDetails.reviewSummary || getDefaultReviewSummary(name, rating, reviewCount),
                chooseThisIf: hotelDetails.chooseThisIf || getDefaultChooseThisIf(name, amenities),
                about: hotelDetails.about || getDefaultAbout(description, name, amenities),
                amenitiesClean: hotelDetails.amenitiesClean || (Array.isArray(amenities) ? amenities : []),
                locationSummary: hotelDetails.locationSummary || getDefaultLocationSummary(address, location, nearby),
                ratingInsights: hotelDetails.ratingInsights || getDefaultRatingInsights(cleanliness, rooms, service, value),
            };
            if (!res.headersSent) {
                return res.json(hotelDetails);
            }
        }
        catch (err) {
            console.error("❌ LLM hotel details generation error:", err.message || err);
            // Return default values on error (only if headers not already sent)
            if (!res.headersSent) {
                return res.json(getDefaultHotelDetails({ name, location, rating, reviewCount, description, amenities, address, nearby, cleanliness, rooms, service, value }));
            }
        }
    }
    catch (err) {
        console.error("❌ Error generating hotel details:", err);
        // Only send response if headers haven't been sent (e.g., by timeout middleware)
        if (!res.headersSent) {
            return res.status(500).json({
                error: "Failed to generate hotel details",
                ...getDefaultHotelDetails({ name: req.body.name || "Hotel" })
            });
        }
    }
});
// Default fallback functions
function getDefaultHotelDetails(hotelData) {
    const { name, location, rating, reviewCount, description, amenities, address, nearby, cleanliness, rooms, service, value } = hotelData;
    return {
        whatPeopleSay: getDefaultWhatPeopleSay(name, location, rating),
        reviewSummary: getDefaultReviewSummary(name, rating, reviewCount),
        chooseThisIf: getDefaultChooseThisIf(name, amenities),
        about: getDefaultAbout(description, name, amenities),
        amenitiesClean: Array.isArray(amenities) ? amenities : [],
        locationSummary: getDefaultLocationSummary(address, location, nearby),
        ratingInsights: getDefaultRatingInsights(cleanliness, rooms, service, value),
    };
}
function getDefaultWhatPeopleSay(name, location, rating) {
    const locationText = location ? ` in ${location}` : '';
    const ratingText = rating && rating >= 4.5
        ? "highly rated"
        : rating && rating >= 4.0
            ? "well-rated"
            : "popular";
    return `This property${locationText} is ${ratingText} among guests, with many reviewers praising the accommodations and convenient location. Guests appreciate the amenities and service quality. Some visitors mention minor areas for improvement, but overall satisfaction remains high.`;
}
function getDefaultReviewSummary(name, rating, reviewCount) {
    const ratingText = rating && rating >= 4.5
        ? "highly rated"
        : rating && rating >= 4.0
            ? "well-rated"
            : "popular";
    return `This ${ratingText} property receives consistent positive feedback from guests. Reviewers frequently mention the quality of accommodations and service. The location is often highlighted as a key benefit. Some guests note areas that could be improved, but overall experiences are positive.`;
}
function getDefaultChooseThisIf(name, amenities) {
    const amenityList = Array.isArray(amenities) ? amenities.slice(0, 2).join(' and ') : 'modern amenities';
    return `Choose this if you want a property with ${amenityList} and convenient accommodations.`;
}
function getDefaultAbout(description, name, amenities) {
    if (description && description !== 'No description available' && description.length > 20) {
        return description.length > 200 ? `${description.substring(0, 200)}...` : description;
    }
    const amenityList = Array.isArray(amenities) && amenities.length > 0
        ? amenities.slice(0, 3).join(', ')
        : 'modern amenities';
    return `This property offers accommodations with ${amenityList}.`;
}
function getDefaultLocationSummary(address, location, nearby) {
    if (address && address !== 'Location not specified') {
        return `Located at ${address}.`;
    }
    if (location && location !== 'Location not specified') {
        return `Situated in ${location}.`;
    }
    if (nearby) {
        return `Conveniently located near ${nearby}.`;
    }
    return 'Well-located property with easy access to local attractions.';
}
function getDefaultRatingInsights(cleanliness, rooms, service, value) {
    const ratings = [];
    if (cleanliness)
        ratings.push({ name: 'cleanliness', value: cleanliness });
    if (rooms)
        ratings.push({ name: 'rooms', value: rooms });
    if (service)
        ratings.push({ name: 'service', value: service });
    if (value)
        ratings.push({ name: 'value', value: value });
    if (ratings.length === 0) {
        return 'Guest ratings reflect overall satisfaction with the property.';
    }
    const sorted = ratings.sort((a, b) => b.value - a.value);
    const highest = sorted[0];
    const lowest = sorted[sorted.length - 1];
    if (highest.value === lowest.value) {
        return `Guests consistently rate all categories around ${highest.value.toFixed(1)}.`;
    }
    return `Guests consistently praise the hotel's ${highest.name} (${highest.value.toFixed(1)}), while ${lowest.name} receives slightly lower scores (${lowest.value.toFixed(1)}).`;
}
export default router;

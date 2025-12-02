// src/services/hotelThemeExtractor.ts
import OpenAI from "openai";

// Lazy-load OpenAI client
let clientInstance: OpenAI | null = null;

function getOpenAIClient(): OpenAI {
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

/**
 * 🎯 Perplexity-style Review-Based Theme Extraction
 * 
 * Analyzes hotel reviews to extract the most commonly mentioned themes.
 * Returns only statistically significant themes for that specific hotel.
 * 
 * This matches Perplexity's approach:
 * - Fetches reviews (from any source: TripAdvisor, Google, Booking.com, etc.)
 * - Runs LLM-based classifier to detect most talked-about themes
 * - Shows ONLY themes that are statistically significant for that hotel
 */
export async function extractHotelThemes(
  hotelName: string,
  reviews: string[] | any[],
  hotelData?: any
): Promise<string[]> {
  // If no reviews available, use hotel metadata to infer themes
  if (!reviews || reviews.length === 0) {
    return inferThemesFromMetadata(hotelData);
  }

  try {
    // Extract review text from various formats
    const reviewTexts = reviews
      .map((review: any) => {
        if (typeof review === 'string') return review;
        if (review.text) return review.text;
        if (review.content) return review.content;
        if (review.review) return review.review;
        if (review.comment) return review.comment;
        return '';
      })
      .filter((text: string) => text.length > 20) // Filter out very short reviews
      .slice(0, 50); // Limit to first 50 reviews to avoid token limits

    if (reviewTexts.length === 0) {
      return inferThemesFromMetadata(hotelData);
    }

    // Combine all reviews into one context
    const reviewsContext = reviewTexts.join('\n\n');

    const systemPrompt = `You are a hotel review analyst (similar to Perplexity's review analysis system).

Your job: Analyze hotel reviews and extract the 3-6 MOST commonly mentioned themes that are statistically significant for THIS specific hotel.

🎯 HOW PERPLEXITY DOES THIS:
1. They analyze thousands of reviews
2. They detect themes that appear frequently across reviews
3. They show ONLY themes that are statistically significant (mentioned by many guests)
4. Each hotel gets different themes based on what guests actually talk about

📌 THEME EXTRACTION RULES:

1. **Statistical Significance**: Only include themes if they appear frequently across reviews
2. **Hotel-Specific**: Themes should be specific to THIS hotel, not generic
3. **Standardized Labels**: Map keywords to standard category tags:
   - "close to town", "good location", "walking distance", "convenient location" → "Location"
   - "staff", "service", "friendly", "helpful", "attentive" → "Service"
   - "pool temperature", "hot tub", "water temperature", "jacuzzi" → "Water temperature"
   - "recent remodel", "renovated", "updated", "modern" → "Renovations"
   - "parking", "spa", "pool", "breakfast", "amenities", "facilities" → "Amenities"
   - "rooms", "room size", "accommodations", "suite" → "Rooms"
   - "cleanliness", "clean", "hygiene" → "Cleanliness"
   - "views", "scenic", "mountain view", "ocean view" → "Views"
   - "communication", "response", "booking" → "Communication"
   - "value", "price", "worth", "affordable" → "Value"

4. **Return Format**: Return ONLY a JSON array of theme labels (3-6 themes max)
   Example: ["Location", "Service", "Amenities"]
   Example: ["Service", "Rooms", "Water temperature"]
   Example: ["Service", "Renovations", "Location & Views"]

5. **Quality Over Quantity**: Only include themes if they are genuinely significant
   - If "water temperature" is mentioned by many guests → include it
   - If "location" is barely mentioned → don't include it

6. **Combine Related Themes**: 
   - "Location" and "Views" can be combined as "Location & Views" if both are significant
   - Keep separate if one is much more significant than the other

Return ONLY a JSON array, no explanation, no markdown.`;

    const userPrompt = `Analyze these reviews for "${hotelName}" and extract the 3-6 most commonly mentioned themes:

${reviewsContext}

Return ONLY a JSON array of theme labels (e.g., ["Location", "Service", "Amenities"]).`;

    const client = getOpenAIClient();
    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.3, // Lower temperature for more consistent theme extraction
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
    });

    const content = response.choices[0]?.message?.content || "";
    
    // Parse JSON array from response
    try {
      // Extract JSON array from markdown code blocks if present
      const jsonMatch = content.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        const themes = JSON.parse(jsonMatch[0]);
        if (Array.isArray(themes) && themes.length > 0) {
          return themes.slice(0, 6); // Limit to 6 themes max
        }
      }
    } catch (e) {
      console.error(`❌ Failed to parse theme extraction response for "${hotelName}":`, e);
    }

    // Fallback to metadata-based inference
    return inferThemesFromMetadata(hotelData);
  } catch (err: any) {
    console.error(`❌ Error extracting themes for "${hotelName}":`, err.message);
    return inferThemesFromMetadata(hotelData);
  }
}

/**
 * Fallback: Infer themes from hotel metadata when reviews are not available
 */
function inferThemesFromMetadata(hotelData?: any): string[] {
  const themes: string[] = [];
  
  if (!hotelData) {
    return ["Location", "Amenities", "Service"]; // Default themes
  }

  // Check for location data
  if (hotelData.address || hotelData.location || hotelData.geo) {
    themes.push("Location");
  }
  
  // Check for amenities
  if (hotelData.amenities && Array.isArray(hotelData.amenities) && hotelData.amenities.length > 0) {
    themes.push("Amenities");
  }
  
  // Check for service rating
  if (hotelData.service || hotelData.service_rating) {
    themes.push("Service");
  }

  // Check for rooms rating
  if (hotelData.rooms || hotelData.rooms_rating) {
    themes.push("Rooms");
  }

  // Check for cleanliness rating
  if (hotelData.cleanliness || hotelData.cleanliness_rating) {
    themes.push("Cleanliness");
  }

  // Ensure at least 2-3 themes
  if (themes.length === 0) {
    return ["Location", "Amenities", "Service"];
  }

  return themes.slice(0, 6); // Limit to 6 themes max
}

/**
 * Check if a theme should be shown (has supporting data)
 */
export function hasThemeSupport(theme: string, hotelData: any): boolean {
  const themeLower = theme.toLowerCase();

  if (themeLower.includes("location")) {
    return !!(hotelData.address || hotelData.location || hotelData.geo);
  }

  if (themeLower.includes("amenities")) {
    return !!(hotelData.amenities && Array.isArray(hotelData.amenities) && hotelData.amenities.length > 0);
  }

  if (themeLower.includes("service")) {
    return !!(hotelData.service || hotelData.service_rating);
  }

  if (themeLower.includes("rooms")) {
    return !!(hotelData.rooms || hotelData.rooms_rating);
  }

  if (themeLower.includes("cleanliness")) {
    return !!(hotelData.cleanliness || hotelData.cleanliness_rating);
  }

  if (themeLower.includes("water") || themeLower.includes("temperature")) {
    // Water temperature is review-specific, so if it's in themes, it's supported
    return true;
  }

  if (themeLower.includes("renovations") || themeLower.includes("renovated")) {
    // Renovations are review-specific
    return true;
  }

  if (themeLower.includes("views")) {
    // Views are review-specific
    return true;
  }

  if (themeLower.includes("communication")) {
    // Communication is review-specific
    return true;
  }

  if (themeLower.includes("value")) {
    return !!(hotelData.value || hotelData.value_rating);
  }

  // Default: if theme was extracted, assume it's supported
  return true;
}


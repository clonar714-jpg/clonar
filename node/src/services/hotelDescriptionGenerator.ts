// src/services/hotelDescriptionGenerator.ts
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
 * 🎯 Perplexity-Style Hotel Description Generator
 * 
 * Generates concise 1 sentence summaries exactly like Perplexity:
 * - Uses hotel's reviews, amenities, location, and unique features
 * - Highlights what guests appreciate most
 * - Mentions what makes it stand out
 * - Identifies who it's best suited for (families, couples, business)
 * - Avoids exaggeration, keeps it factual
 * - Travel-guide style, natural and human-written
 */
export async function generateHotelDescription(
  hotelName: string,
  hotelData: any,
  sectionHeading?: string // e.g., "Luxury downtown hotels", "Midrange options"
): Promise<string> {
  try {
    // Extract review texts (top 50, compressed)
    const reviewTexts = (hotelData.reviewTexts || hotelData.reviews || [])
      .map((review: any) => {
        if (typeof review === 'string') return review;
        if (review.text) return review.text;
        if (review.content) return review.content;
        if (review.review) return review.review;
        if (review.comment) return review.comment;
        return '';
      })
      .filter((text: string) => text.length > 20)
      .slice(0, 50) // Top 50 reviews
      .join('\n\n');

    // Extract metadata
    const metadata = {
      name: hotelName,
      rating: hotelData.rating || hotelData.overall_rating || 0,
      reviewCount: hotelData.reviews || hotelData.review_count || 0,
      price: hotelData.price || hotelData.rate_per_night?.lowest || null,
      location: hotelData.address || hotelData.location || '',
      amenities: Array.isArray(hotelData.amenities) ? hotelData.amenities : [],
      category: hotelData.category || hotelData.hotel_class || null,
      sectionHeading: sectionHeading || null,
      // Rating breakdowns
      cleanliness: hotelData.cleanliness || hotelData.cleanliness_rating || null,
      service: hotelData.service || hotelData.service_rating || null,
      rooms: hotelData.rooms || hotelData.rooms_rating || null,
      value: hotelData.value || hotelData.value_rating || null,
      locationRating: hotelData.locationRating || hotelData.location_rating || null,
    };

    const systemPrompt = `You are a travel guide writer creating concise hotel summaries for a search results page (similar to Perplexity's hotel descriptions).

Your task: Write a concise 1 sentence summary of this hotel for a traveler.

🎯 REQUIREMENTS:

1. **Length**: Exactly 1 sentence (no more, no less)
2. **Style**: Travel-guide style, natural, human-written tone
3. **Content Sources**: Use the hotel's reviews, amenities, location, and unique features
4. **Highlights**:
   - What guests appreciate most (from reviews)
   - What makes it stand out (unique features, location, amenities)
   - Who it is best suited for (families, couples, business travelers, solo travelers, etc.)
5. **Tone**: 
   - Factual, avoid exaggeration
   - No marketing hype
   - Objective and helpful
   - Like a travel editor wrote it

📌 WRITING GUIDELINES:

- Start with the hotel's positioning (e.g., "A 4-star luxury hotel in...", "A midrange option...")
- Mention standout features guests appreciate (from reviews) and target audience
- Use natural, flowing sentences
- Avoid bullet points or lists
- Sound like a travel guide, not a sales pitch

📌 EXAMPLE OUTPUTS:

Good: "A 4-star luxury hotel in downtown Park City offering ski-in/ski-out access and world-class service, ideal for couples and families seeking a premium mountain resort experience."

Good: "A well-rated midrange option in the heart of the city, known for its modern amenities and friendly service, best suited for business travelers and budget-conscious families."

Bad: "This amazing hotel is perfect for everyone! You'll love it!" (too generic, exaggerated)

Return ONLY the description text, no markdown, no quotes, no extra formatting.`;

    const userPrompt = `Generate a 2-3 sentence hotel description for:

**Hotel Name**: ${metadata.name}
**Rating**: ${metadata.rating}/5 (${metadata.reviewCount} reviews)
**Location**: ${metadata.location || 'Not specified'}
**Price**: ${metadata.price || 'Not specified'}
**Category**: ${metadata.category || 'Not specified'}
${metadata.sectionHeading ? `**Section**: ${metadata.sectionHeading}` : ''}
**Amenities**: ${metadata.amenities.length > 0 ? metadata.amenities.slice(0, 10).join(', ') : 'Not specified'}

${metadata.cleanliness ? `**Cleanliness Rating**: ${metadata.cleanliness}/5` : ''}
${metadata.service ? `**Service Rating**: ${metadata.service}/5` : ''}
${metadata.rooms ? `**Rooms Rating**: ${metadata.rooms}/5` : ''}
${metadata.value ? `**Value Rating**: ${metadata.value}/5` : ''}

${reviewTexts ? `**Guest Reviews (Top 50)**:\n${reviewTexts.substring(0, 3000)}` : '**Reviews**: Not available'}

Write a concise 1 sentence summary following the guidelines.`;

    const client = getOpenAIClient();
    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.5, // Balanced creativity and consistency
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 100, // ✅ Reduced to enforce 1 sentence
    });

    const description = response.choices[0]?.message?.content?.trim() || '';
    
    // Clean up the description (remove quotes, markdown, etc.)
    let cleanedDescription = description
      .replace(/^["']|["']$/g, '') // Remove surrounding quotes
      .replace(/^\*\*.*?\*\*:\s*/g, '') // Remove markdown headers
      .trim();

    // Fallback if description is empty or too short
    if (!cleanedDescription || cleanedDescription.length < 20) {
      return getFallbackDescription(metadata);
    }

    return cleanedDescription;
  } catch (err: any) {
    console.error(`❌ Error generating hotel description for "${hotelName}":`, err.message);
    return getFallbackDescription({
      name: hotelName,
      rating: hotelData.rating || 0,
      reviewCount: hotelData.reviews || 0,
      location: hotelData.address || hotelData.location || '',
      amenities: Array.isArray(hotelData.amenities) ? hotelData.amenities : [],
    });
  }
}

/**
 * Fallback description when LLM generation fails
 */
function getFallbackDescription(metadata: any): string {
  const locationText = metadata.location ? ` in ${metadata.location}` : '';
  const ratingText = metadata.rating >= 4.5 
    ? 'highly rated' 
    : metadata.rating >= 4.0 
    ? 'well-rated' 
    : 'rated';
  
  const amenityText = metadata.amenities && metadata.amenities.length > 0
    ? ` with ${metadata.amenities.slice(0, 2).join(' and ')}`
    : '';

  return `A ${ratingText} property${locationText}${amenityText}. Guests appreciate the accommodations and convenient location. Suitable for travelers seeking comfortable accommodations.`;
}


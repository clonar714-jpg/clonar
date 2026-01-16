/**
 * ✅ PERPLEXITY-STYLE: Detail endpoints for Products, Hotels, Places, Movies
 * 
 * When user taps a card, this endpoint generates:
 * - "Buy this if" / "Stay here if" / "Visit this if" / "Watch this if"
 * - "What people say" (review summary with sentiment analysis)
 * - "Key features" (specs/amenities/characteristics)
 * - "Traveler insights" (hotels/places only)
 * - "Rating breakdown" (hotels/products only)
 * - "Price comparison" (products only)
 * - "Location context" (hotels/places only)
 * - Additional images
 */

import { Request, Response } from "express";
import OpenAI from "openai";
import axios from "axios";
import { createErrorResponse } from "../utils/errorResponse";

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("Missing OPENAI_API_KEY environment variable");
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}

/**
 * Generate detail content using LLM
 */
async function generateDetailContent(
  domain: 'product' | 'hotel' | 'place' | 'movie',
  title: string,
  description: string,
  additionalInfo?: any
): Promise<{
  buyThisIf?: string;
  whatPeopleSay: string;
  keyFeatures: string[];
  travelerInsights?: string; // Hotels/Places only
  ratingBreakdown?: string; // Hotels/Products only
  priceComparison?: string; // Products only
  locationContext?: string; // Hotels/Places only
  images?: string[];
}> {
  const domainPrompts = {
    product: {
      buyThisIf: "Generate a one-sentence description of who should buy this product and why.",
      whatPeopleSay: "Summarize customer reviews in 2-3 sentences, highlighting common themes.",
      keyFeatures: "List 3-5 key features or specifications of this product.",
    },
    hotel: {
      buyThisIf: "Generate a one-sentence description of who should stay at this hotel and why.",
      whatPeopleSay: "Summarize guest reviews in 2-3 sentences, highlighting common themes.",
      keyFeatures: "List all key amenities or features of this hotel. If amenities are missing from the provided data, infer likely amenities based on hotel type, rating, and description.",
    },
    place: {
      buyThisIf: "Generate a one-sentence description of who should visit this place and why.",
      whatPeopleSay: "Summarize visitor reviews in 2-3 sentences, highlighting common themes.",
      keyFeatures: "List 3-5 key attractions or characteristics of this place.",
    },
    movie: {
      buyThisIf: "Generate a one-sentence description of who should watch this movie and why.",
      whatPeopleSay: "Summarize audience reviews in 2-3 sentences, highlighting common themes.",
      keyFeatures: "List 3-5 key aspects (genre, director, cast, themes) of this movie.",
    },
  };

  const prompts = domainPrompts[domain];
  
  // Build domain-specific system prompt
  let system = `You are analyzing a ${domain} for a detail page.

${domain === 'product' ? 'Product' : domain === 'hotel' ? 'Hotel' : domain === 'place' ? 'Place' : 'Movie'}: ${title}
Description: ${description}
${additionalInfo ? `Additional Info: ${JSON.stringify(additionalInfo)}` : ''}

Generate the following sections:`;

  // Base sections (all domains)
  system += `
1. "${domain === 'product' ? 'Buy this if' : domain === 'hotel' ? 'Stay here if' : domain === 'place' ? 'Visit this if' : 'Watch this if'}" - One sentence describing the ideal user/use case
2. "What people say" - 2-3 sentence summary with sentiment analysis. Analyze review themes and highlight:
   - Positive aspects (what reviewers consistently praise)
   - Common concerns or drawbacks (if any)
   - Overall sentiment (positive, mixed, or critical)
   - Specific themes (cleanliness, service, value, quality, etc.)
3. "Key features" - ${domain === 'hotel' ? 'List all key amenities or features. If amenities are missing from the provided data, infer likely amenities based on hotel type, rating, and description (e.g., WiFi, parking, pool, gym, restaurant, etc.)' : '3-5 bullet points of main features/amenities/characteristics'}`;

  // Domain-specific sections
  if (domain === 'hotel' || domain === 'place') {
    system += `
4. "Traveler insights" - 2-3 sentences about:
   - Best time to visit (seasonal considerations, weather, crowds)
   - Traveler types who enjoy this most (families, couples, solo travelers, business, etc.)
   - Common experiences or highlights mentioned by visitors
   - Any unique aspects that make this special`;
  }

  // Calculate section numbers based on domain
  let sectionNum = 4;
  
  if (domain === 'hotel' || domain === 'product') {
    system += `
${sectionNum}. "Rating breakdown" - Analyze the rating distribution:
   - If rating is provided (${additionalInfo?.rating || 'N/A'}), explain what it means
   - Describe the distribution (e.g., "Most reviews are 4-5 stars, with some 3-star reviews mentioning...")
   - Highlight what the rating indicates about quality/value
   - If review count is available (${additionalInfo?.reviews || 'N/A'}), mention the sample size`;
    sectionNum++;
  }

  if (domain === 'product') {
    system += `
${sectionNum}. "Price comparison" - Provide pricing context:
   - If price is provided (${additionalInfo?.price || 'N/A'}), compare it to similar products
   - Mention typical price range for this category
   - Highlight value proposition (premium, mid-range, budget-friendly)
   - Note if price varies by retailer or variant`;
    sectionNum++;
  }

  if (domain === 'hotel' || domain === 'place') {
    system += `
${sectionNum}. "Location context" - Describe the location:
   - Neighborhood or area characteristics
   - Nearby attractions, restaurants, or points of interest
   - Accessibility (public transport, parking, walkability)
   - Safety and atmosphere
   - Distance from key landmarks or city center`;
  }

  // Build JSON format string
  let jsonFormat = `{
  "${domain === 'product' ? 'buyThisIf' : domain === 'hotel' ? 'stayHereIf' : domain === 'place' ? 'visitThisIf' : 'watchThisIf'}": "...",
  "whatPeopleSay": "...",
  "keyFeatures": ["...", "...", "..."]`;

  // Add domain-specific fields to JSON format
  if (domain === 'hotel' || domain === 'place') {
    jsonFormat += `,
  "travelerInsights": "...",
  "locationContext": "..."`;
  }

  if (domain === 'hotel' || domain === 'product') {
    jsonFormat += `,
  "ratingBreakdown": "..."`;
  }

  if (domain === 'product') {
    jsonFormat += `,
  "priceComparison": "..."`;
  }

  jsonFormat += `
}`;

  system += `

Format as JSON:
${jsonFormat}`;

  try {
    const response = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.3,
      max_tokens: 500,
      messages: [
        { role: "system", content: system },
        { role: "user", content: `Generate detail content for this ${domain}.` },
      ],
    });

    const content = response.choices[0]?.message?.content || '';
    
    // Try to parse JSON from response
    let parsed: any = {};
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        parsed = JSON.parse(jsonMatch[0]);
      }
    } catch (e) {
      // Fallback: generate from text
      const lines = content.split('\n').filter(l => l.trim());
      parsed = {
        whatPeopleSay: lines.find(l => l.toLowerCase().includes('people say') || l.toLowerCase().includes('review')) || 'Customers appreciate the quality and value.',
        keyFeatures: lines.filter(l => l.trim().startsWith('-') || l.trim().startsWith('•')).slice(0, 5).map((l: string) => l.replace(/^[-•]\s*/, '')),
      };
    }

    return {
      buyThisIf: parsed.buyThisIf || parsed.stayHereIf || parsed.visitThisIf || parsed.watchThisIf,
      whatPeopleSay: parsed.whatPeopleSay || 'Customers appreciate the quality and value.',
      keyFeatures: Array.isArray(parsed.keyFeatures) ? parsed.keyFeatures : [],
      travelerInsights: (domain === 'hotel' || domain === 'place') ? (parsed.travelerInsights || undefined) : undefined,
      ratingBreakdown: (domain === 'hotel' || domain === 'product') ? (parsed.ratingBreakdown || undefined) : undefined,
      priceComparison: domain === 'product' ? (parsed.priceComparison || undefined) : undefined,
      locationContext: (domain === 'hotel' || domain === 'place') ? (parsed.locationContext || undefined) : undefined,
      images: additionalInfo?.images || [],
    };
  } catch (error: any) {
    console.error("❌ Failed to generate detail content:", error);
    const fallback: any = {
      whatPeopleSay: 'Customers appreciate the quality and value.',
      keyFeatures: [],
    };
    
    // Add domain-specific fallbacks
    if (domain === 'hotel' || domain === 'place') {
      fallback.travelerInsights = 'This location offers a great experience for various types of travelers throughout the year.';
      fallback.locationContext = 'The location is well-situated with good access to local attractions and amenities.';
    }
    
    if (domain === 'hotel' || domain === 'product') {
      fallback.ratingBreakdown = 'Reviews indicate a generally positive experience with this option.';
    }
    
    if (domain === 'product') {
      fallback.priceComparison = 'This product offers good value within its category.';
    }
    
    return fallback;
  }
}

/**
 * Fetch additional product images/details
 */
async function fetchProductDetails(productId: string, title: string, link?: string): Promise<any> {
  // For products, we can fetch more images from SerpAPI or the product link
  // For now, return empty (images already in main response)
  return { images: [] };
}

/**
 * Fetch additional hotel images/details
 */
async function fetchHotelDetails(hotelId: string, name: string, link?: string): Promise<any> {
  const serpKey = process.env.SERPAPI_KEY;
  if (!serpKey) return { images: [] };

  try {
    const serpUrl = "https://serpapi.com/search.json";
    const params = {
      engine: "google_hotels",
      q: name,
      api_key: serpKey,
      hl: "en",
      gl: "us",
    };

    const response = await axios.get(serpUrl, { params, timeout: 10000 });
    const hotels = response.data.hotels || response.data.hotels_results || [];
    const hotel = hotels.find((h: any) => h.name === name || h.hotel_id === hotelId) || hotels[0];
    
    if (!hotel) return { images: [] };

    const images: string[] = [];
    if (hotel.thumbnail) images.push(hotel.thumbnail);
    if (hotel.image) images.push(hotel.image);
    if (hotel.images && Array.isArray(hotel.images)) {
      hotel.images.slice(0, 10).forEach((img: any) => {
        const imgUrl = img?.original_image || img?.thumbnail || img;
        if (imgUrl && !images.includes(imgUrl)) images.push(imgUrl);
      });
    }

    return { images };
  } catch (error: any) {
    console.warn("⚠️ Failed to fetch hotel details:", error.message);
    return { images: [] };
  }
}

/**
 * Fetch additional place images/details
 */
async function fetchPlaceDetails(placeId: string, name: string, link?: string): Promise<any> {
  // For places, we can fetch more images from Google Places API
  // For now, return empty (images already in main response)
  return { images: [] };
}

/**
 * Fetch additional movie images/details
 */
async function fetchMovieDetails(movieId: string, title: string): Promise<any> {
  const tmdbKey = process.env.TMDB_API_KEY;
  if (!tmdbKey) return { images: [] };

  try {
    const tmdbUrl = `https://api.themoviedb.org/3/movie/${movieId}`;
    const params = {
      api_key: tmdbKey,
      language: 'en-US',
      append_to_response: 'images',
    };

    const response = await axios.get(tmdbUrl, { params, timeout: 10000 });
    const movie = response.data;
    
    const images: string[] = [];
    if (movie.poster_path) images.push(`https://image.tmdb.org/t/p/w500${movie.poster_path}`);
    if (movie.backdrop_path) images.push(`https://image.tmdb.org/t/p/w1280${movie.backdrop_path}`);
    if (movie.images?.posters) {
      movie.images.posters.slice(0, 5).forEach((poster: any) => {
        images.push(`https://image.tmdb.org/t/p/w500${poster.file_path}`);
      });
    }
    if (movie.images?.backdrops) {
      movie.images.backdrops.slice(0, 5).forEach((backdrop: any) => {
        images.push(`https://image.tmdb.org/t/p/w1280${backdrop.file_path}`);
      });
    }

    return { images, genre: movie.genres?.map((g: any) => g.name) || [] };
  } catch (error: any) {
    console.warn("⚠️ Failed to fetch movie details:", error.message);
    return { images: [] };
  }
}

/**
 * Unified detail handler
 */
export async function handleDetailRequest(req: Request, res: Response): Promise<void> {
  try {
    const { domain, id, title, description, price, rating, source, link, ...additionalInfo } = req.body;

    if (!domain || !['product', 'hotel', 'place', 'movie'].includes(domain)) {
      res.status(400).json(
        createErrorResponse('Invalid domain. Must be: product, hotel, place, or movie')
      );
      return;
    }

    if (!title) {
      res.status(400).json(
        createErrorResponse('Title is required')
      );
      return;
    }

    console.log(`🔍 Generating detail content for ${domain}: "${title}"`);

    // Fetch additional details (images, etc.)
    let additionalDetails: any = {};
    try {
      if (domain === 'product') {
        additionalDetails = await fetchProductDetails(id || title, title, link);
      } else if (domain === 'hotel') {
        additionalDetails = await fetchHotelDetails(id || title, title, link);
      } else if (domain === 'place') {
        additionalDetails = await fetchPlaceDetails(id || title, title, link);
      } else if (domain === 'movie') {
        additionalDetails = await fetchMovieDetails(id || title, title);
      }
    } catch (error: any) {
      console.warn("⚠️ Failed to fetch additional details:", error.message);
    }

    // Generate LLM content
    const detailContent = await generateDetailContent(
      domain,
      title,
      description || '',
      { ...additionalInfo, ...additionalDetails }
    );

    res.json({
      success: true,
      domain,
      ...detailContent,
      images: detailContent.images || additionalDetails.images || [],
    });
  } catch (err: any) {
    console.error("❌ Detail request error:", err);
    res.status(500).json(
      createErrorResponse("Request failed", err.message)
    );
  }
}


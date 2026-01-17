
import axios from "axios";
import OpenAI from "openai";


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


async function fetchGooglePlacesAmenities(
  placeId: string | null,
  hotelName: string,
  location: string
): Promise<string[]> {
  const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
  if (!apiKey || !placeId) {
    
    try {
      const searchQuery = `${hotelName}, ${location}`;
      const searchUrl = `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(searchQuery)}&key=${apiKey}`;
      const searchResponse = await axios.get(searchUrl, { timeout: 5000 });
      
      if (searchResponse.data.status === 'OK' && searchResponse.data.results?.[0]?.place_id) {
        placeId = searchResponse.data.results[0].place_id;
      } else {
        return [];
      }
    } catch (err: any) {
      console.error(`❌ Error searching for place_id for "${hotelName}":`, err.message);
      return [];
    }
  }

  try {
    
    const detailsUrl = `https://places.googleapis.com/v1/places/${placeId}?fields=hotelAmenities,roomFeatures,propertyHighlights,accessibilityOptions,foodAndDrink,wellness,parkingOptions&key=${apiKey}`;
    
    const response = await axios.get(detailsUrl, {
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
      },
      timeout: 5000,
    });

    const amenities: string[] = [];
    
   
    if (response.data.hotelAmenities) {
      amenities.push(...(Array.isArray(response.data.hotelAmenities) ? response.data.hotelAmenities : []));
    }
    if (response.data.roomFeatures) {
      amenities.push(...(Array.isArray(response.data.roomFeatures) ? response.data.roomFeatures : []));
    }
    if (response.data.propertyHighlights) {
      amenities.push(...(Array.isArray(response.data.propertyHighlights) ? response.data.propertyHighlights : []));
}
    if (response.data.accessibilityOptions) {
      amenities.push(...(Array.isArray(response.data.accessibilityOptions) ? response.data.accessibilityOptions : []));
    }
    if (response.data.foodAndDrink) {
      amenities.push(...(Array.isArray(response.data.foodAndDrink) ? response.data.foodAndDrink : []));
    }
    if (response.data.wellness) {
      amenities.push(...(Array.isArray(response.data.wellness) ? response.data.wellness : []));
    }
    if (response.data.parkingOptions) {
      amenities.push(...(Array.isArray(response.data.parkingOptions) ? response.data.parkingOptions : []));
    }

   
    return amenities
      .map(a => typeof a === 'string' ? a : (a?.displayName || a?.name || String(a)))
      .filter(a => a && a.length > 0)
      .map(a => a.trim());
  } catch (err: any) {
    
    try {
      const legacyUrl = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${placeId}&fields=amenities&key=${apiKey}`;
      const legacyResponse = await axios.get(legacyUrl, { timeout: 5000 });
      
      if (legacyResponse.data.result?.amenities) {
        return Array.isArray(legacyResponse.data.result.amenities)
          ? legacyResponse.data.result.amenities.map((a: any) => String(a).trim()).filter(Boolean)
          : [];
      }
    } catch (legacyErr: any) {
      console.error(`❌ Error fetching Google Places amenities for "${hotelName}":`, err.message);
    }
    return [];
  }
}


async function fetchTripadvisorAmenities(
  hotelName: string,
  location: string
): Promise<string[]> {
  
  return [];
}


async function extractAmenitiesFromReviews(
  reviews: string[],
  hotelName: string
): Promise<string[]> {
  if (!reviews || reviews.length === 0) {
    return [];
  }

  try {
    
    const reviewTexts = reviews
      .map((review: any) => {
        if (typeof review === 'string') return review;
        if (review.text) return review.text;
        if (review.content) return review.content;
        if (review.review) return review.review;
        if (review.comment) return review.comment;
        return '';
      })
      .filter((text: string) => text.length > 20)
      .slice(0, 50)
      .join('\n\n');

    if (reviewTexts.length < 50) {
      return []; 
    }

    const systemPrompt = `You are an amenity extraction system for a hotel search engine (similar to Perplexity).

Your task: Analyze hotel reviews and identify amenities that guests frequently mention or that differentiate this hotel.

🎯 EXTRACTION RULES:

1. **Identify amenities mentioned in reviews** (e.g., "the hot tub was amazing", "free breakfast", "EV chargers available")
2. **Prefer amenities frequently mentioned** across multiple reviews
3. **Prefer amenities that differentiate** this hotel from others
4. **Output 4-8 SHORT labels** suitable for UI tags
5. **Use concise, traveler-friendly language**

📌 AMENITY EXAMPLES:

Good: "Free Wi-Fi", "Indoor pool", "Hot tub", "Free breakfast", "Ski access", "Pet-friendly", "Airport shuttle", "Rooftop bar", "EV chargers", "Mountain views", "Spa services", "Business center"

Bad: "The hotel has a pool" (too long), "WiFi" (incomplete), "Breakfast" (should be "Free breakfast" if mentioned as free)

📌 OUTPUT FORMAT:

Return ONLY a JSON array of strings, no explanation, no markdown.

Example: ["Free Wi-Fi", "Indoor pool", "Hot tub", "Free breakfast", "Ski access"]`;

    const userPrompt = `Analyze these reviews for "${hotelName}" and extract 4-8 amenities that are:
1. Frequently mentioned by guests
2. Important to travelers
3. Differentiate this hotel

Reviews:
${reviewTexts.substring(0, 3000)} // Limit to avoid token limits

Return ONLY a JSON array of amenity strings (4-8 items).`;

    const client = getOpenAIClient();
    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.3,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 200,
    });

    const content = response.choices[0]?.message?.content?.trim() || '';
    
    try {
      const jsonMatch = content.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        const amenities = JSON.parse(jsonMatch[0]);
        if (Array.isArray(amenities) && amenities.length > 0) {
          return amenities.slice(0, 8).map((a: any) => String(a).trim()).filter(Boolean);
        }
      }
    } catch (e) {
      console.error(`❌ Failed to parse amenities from reviews for "${hotelName}":`, e);
    }
  } catch (err: any) {
    console.error(`❌ Error extracting amenities from reviews for "${hotelName}":`, err.message);
  }

  return [];
}


function mergeAndCleanAmenities(
  googleAmenities: string[],
  tripadvisorAmenities: string[],
  reviewAmenities: string[],
  existingAmenities: string[]
): string[] {
  
  const allAmenities = [
    ...googleAmenities,
    ...tripadvisorAmenities,
    ...reviewAmenities,
    ...(Array.isArray(existingAmenities) ? existingAmenities : []),
  ];

  
  const normalized = allAmenities
    .map(a => {
      if (typeof a !== 'string') return String(a);
      return a.trim();
    })
    .filter(a => a.length > 0 && a.length < 50) // Filter out too long/short
    .map(a => {
     
      return a.charAt(0).toUpperCase() + a.slice(1).toLowerCase();
    });

  
  const seen = new Set<string>();
  const unique = normalized.filter(a => {
    const lower = a.toLowerCase();
    if (seen.has(lower)) return false;
    seen.add(lower);
    return true;
  });

  return unique;
}


async function selectTopAmenities(
  allAmenities: string[],
  reviews: string[],
  hotelMetadata: any
): Promise<string[]> {
  if (allAmenities.length === 0) {
    return [];
  }

  
  if (allAmenities.length <= 8) {
    return allAmenities;
  }
  
  try {
    const reviewContext = reviews
      .slice(0, 30)
      .map((r: any) => typeof r === 'string' ? r : (r?.text || r?.content || ''))
      .filter((r: string) => r.length > 20)
      .join('\n\n')
      .substring(0, 2000);

    const systemPrompt = `You are an amenity selection system for a hotel search engine (similar to Perplexity).

Your task: From a list of amenities, select the 4-8 MOST IMPORTANT ones for travelers.

🎯 SELECTION CRITERIA:

1. **Prefer amenities frequently mentioned in reviews** (if reviews provided)
2. **Prefer amenities that differentiate this hotel** from competitors
3. **Prefer amenities important to travelers** (Wi-Fi, breakfast, pool, parking, etc.)
4. **Output 4-8 items** (prefer 6-8 if many good options)
5. **Use SHORT, clear labels** suitable for UI chips

📌 OUTPUT FORMAT:

Return ONLY a JSON array of strings, no explanation, no markdown.

Example: ["Free Wi-Fi", "Indoor pool", "Hot tub", "Free breakfast", "Ski access", "Pet-friendly"]`;

    const userPrompt = `Select the 4-8 most important amenities from this list for a hotel:

**Hotel**: ${hotelMetadata.name || 'Hotel'}
**Rating**: ${hotelMetadata.rating || 'N/A'}/5
**Location**: ${hotelMetadata.location || hotelMetadata.address || 'N/A'}

**All Available Amenities**:
${allAmenities.join(', ')}

${reviewContext ? `**Guest Reviews** (for context on what guests mention):
${reviewContext}` : ''}

Select 4-8 amenities that are:
1. Most important to travelers
2. Frequently mentioned in reviews (if reviews provided)
3. Differentiate this hotel

Return ONLY a JSON array of selected amenity strings.`;

    const client = getOpenAIClient();
    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.3,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 200,
    });

    const content = response.choices[0]?.message?.content?.trim() || '';
    
    try {
      const jsonMatch = content.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        const selected = JSON.parse(jsonMatch[0]);
        if (Array.isArray(selected) && selected.length > 0) {
         
          const selectedLower = selected.map((s: any) => String(s).toLowerCase());
          const filtered = allAmenities.filter(a => 
            selectedLower.includes(a.toLowerCase())
          );
          return filtered.slice(0, 8);
        }
      }
    } catch (e) {
      console.error(`❌ Failed to parse selected amenities:`, e);
    }
  } catch (err: any) {
    console.error(`❌ Error selecting top amenities:`, err.message);
  }
  
  
  return allAmenities.slice(0, 8);
}

export async function extractHotelAmenities(
  hotelData: any
): Promise<string[]> {
  try {
    const hotelName = hotelData.name || hotelData.title || 'Hotel';
    const location = hotelData.location || hotelData.address || '';
    const placeId = hotelData.place_id || hotelData.googlePlaceId || null;
    const existingAmenities = hotelData.amenities || [];
    const reviews = hotelData.reviewTexts || hotelData.reviews || [];
    const hotelMetadata = {
      name: hotelName,
      rating: hotelData.rating || hotelData.overall_rating || 0,
      location: location,
      address: hotelData.address || location,
    };

    console.log(`🏨 Extracting amenities for "${hotelName}"...`);

   
    const googlePromise = fetchGooglePlacesAmenities(placeId, hotelName, location);
    const googleTimeout = new Promise<string[]>((resolve) => 
      setTimeout(() => resolve([]), 3000)
    );
    const googleAmenities = await Promise.race([googlePromise, googleTimeout]);
  
    
    const tripadvisorAmenities = await fetchTripadvisorAmenities(hotelName, location);

    
    const reviewPromise = extractAmenitiesFromReviews(reviews, hotelName);
    const reviewTimeout = new Promise<string[]>((resolve) => 
      setTimeout(() => resolve([]), 4000)
    );
    const reviewAmenities = await Promise.race([reviewPromise, reviewTimeout]);

    
    const mergedAmenities = mergeAndCleanAmenities(
      googleAmenities,
      tripadvisorAmenities,
      reviewAmenities,
      existingAmenities
    );

    if (mergedAmenities.length === 0) {
      
      return Array.isArray(existingAmenities) 
        ? existingAmenities.slice(0, 8).map(a => String(a).trim()).filter(Boolean)
        : [];
    }

    
    const topAmenities = await selectTopAmenities(mergedAmenities, reviews, hotelMetadata);

    console.log(`✅ Extracted ${topAmenities.length} amenities for "${hotelName}"`);

    return topAmenities.length > 0 ? topAmenities : mergedAmenities.slice(0, 8);
  } catch (err: any) {
    console.error(`❌ Error extracting amenities:`, err.message);
    
    const existing = hotelData.amenities || [];
    return Array.isArray(existing) 
      ? existing.slice(0, 8).map(a => String(a).trim()).filter(Boolean)
      : [];
  }
}


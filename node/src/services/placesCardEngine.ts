// src/services/placesCardEngine.ts
import { generatePlacesSections, PlacesSection } from "./placesSectionGenerator";
import { searchPlaces, PlaceItem, extractLocationFromQuery } from "./brightDataPlaces";

export interface PlacesSectionCard {
  title: string;
  items: PlaceItem[];
}

export interface PlacesCardResult {
  sections: PlacesSectionCard[];
  location: string | null;
}

/**
 * 🎯 Places Card Engine (FULL CODE)
 * Builds Perplexity-style grouped places cards with sections
 */
export async function buildPlacesCards(
  query: string,
  location: string | null = null
): Promise<PlacesCardResult> {
  // Extract location from query if not provided
  const geoArea = location || extractLocationFromQuery(query) || query;

  try {
    // 1. Generate Sections (Nature, Cities, Beaches...)
    const sectionResponse = await generatePlacesSections(geoArea);
    const sections = sectionResponse.sections;

    // 2. Fetch places list
    const places = await searchPlaces(query, geoArea);

    if (places.length === 0) {
      console.warn("⚠️ No places found, returning empty sections");
      return {
        sections: sections.map(sec => ({ title: sec.title, items: [] })),
        location: geoArea,
      };
    }

    // 3. Group places into sections based on category/type
    const grouped: PlacesSectionCard[] = sections.map((sec) => {
      const matchingPlaces = places.filter((place) => {
        const placeCategory = (place.category || "").toLowerCase();
        const placeName = (place.name || "").toLowerCase();
        
        // Check if place matches any type in this section
        return sec.types.some((type) => {
          const typeLower = type.toLowerCase();
          return (
            placeCategory.includes(typeLower) ||
            placeName.includes(typeLower) ||
            // Fallback matching
            (typeLower === "temple" && placeCategory.includes("temple")) ||
            (typeLower === "beach" && (placeCategory.includes("beach") || placeName.includes("beach"))) ||
            (typeLower === "island" && (placeCategory.includes("island") || placeName.includes("island"))) ||
            (typeLower === "mountain" && (placeCategory.includes("mountain") || placeName.includes("mountain"))) ||
            (typeLower === "waterfall" && (placeCategory.includes("waterfall") || placeName.includes("waterfall"))) ||
            (typeLower === "national_park" && (placeCategory.includes("park") || placeCategory.includes("national"))) ||
            (typeLower === "city" && (placeCategory.includes("city") || placeCategory.includes("urban"))) ||
            (typeLower === "landmark" && (placeCategory.includes("landmark") || placeCategory.includes("monument")))
          );
        });
      });

      return {
        title: sec.title,
        items: matchingPlaces.slice(0, 10), // Limit to 10 per section
      };
    });

    // 4. Filter out empty sections
    const nonEmptySections = grouped.filter((sec) => sec.items.length > 0);

    // 5. If we have places but no sections matched, create a default "All Places" section
    if (nonEmptySections.length === 0 && places.length > 0) {
      return {
        sections: [
          {
            title: "Top Places to Visit",
            items: places.slice(0, 20),
          },
        ],
        location: geoArea,
      };
    }

    return {
      sections: nonEmptySections,
      location: geoArea,
    };
  } catch (err: any) {
    console.error("❌ Places card engine error:", err.message);
    return {
      sections: [],
      location: geoArea,
    };
  }
}


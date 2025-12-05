// src/services/flightSearch.ts
import axios from "axios";
import { refineQuery } from "./llmQueryRefiner";

function safeString(v: any): string {
  return v ? v.toString() : "";
}

function safeNumber(v: any): number {
  if (!v) return 0;
  return Number(String(v).replace(/[^\d.]/g, "")) || 0;
}

function normalizeFlight(item: any) {
  // Build title from departure/arrival if not provided
  const departureAirport = safeString(item.departure?.airport || item.departure || item.from || "");
  const arrivalAirport = safeString(item.arrival?.airport || item.arrival || item.to || "");
  const title = item.title || (departureAirport && arrivalAirport 
    ? `${departureAirport} → ${arrivalAirport}` 
    : "Flight");

  return {
    title, // Keep for compatibility
    airline: safeString(item.airline || item.carrier),
    price: safeString(item.price || item.extracted_price || item.total_price || "0"),
    duration: safeString(item.duration || item.flight_duration),
    stops: safeString(item.stops || item.stop_count || "0"),
    departure: safeString(item.departure?.airport || item.departure || item.from),
    arrival: safeString(item.arrival?.airport || item.arrival || item.to),
    link: safeString(item.link || item.url),
    source: safeString(item.airline || item.carrier || "Flight"), // Keep for compatibility
    // Keep raw departure/arrival objects if they exist for detailed info
    departureDetails: item.departure || undefined,
    arrivalDetails: item.arrival || undefined,
  };
}

/**
 * 🚀 C6 PATCH #7 — Primary flight search (SerpAPI)
 */
async function serpFlightSearch(query: string): Promise<any[]> {
  const serpUrl = "https://serpapi.com/search.json";
  const serpKey = process.env.SERPAPI_KEY;

  if (!serpKey) {
    throw new Error("Missing SERPAPI_KEY");
  }

  const params: any = {
    engine: "google_flights",
    q: query,
    hl: "en",
    gl: "us",
    api_key: serpKey,
    num: 10,
  };

  const res = await axios.get(serpUrl, { params });
  const items = res.data.flights || [];
  return items.map(normalizeFlight);
}

/**
 * 🚀 C6 PATCH #7 — Fallback flight APIs (placeholder for future integration)
 */
async function fallbackFlightAPIs(query: string): Promise<any[]> {
  // Placeholder for future APIs (Aviata, FlightAPI.io, Kayak, etc.)
  // For now, return empty array
  return [];
}

/**
 * 🚀 C6 PATCH #7 — Multi-API fallback for flights
 */
export async function searchFlights(query: string): Promise<any[]> {
  try {
    console.log("✈️ Flight search:", query);

    const results: any[] = [];

    // Attempt 1 — Primary SerpAPI
    try {
      const primary = await serpFlightSearch(query);
      results.push(...primary);
      if (results.length >= 3) {
        console.log(`✈️ Found ${results.length} flights (primary)`);
        return results.slice(0, 10);
      }
    } catch (err: any) {
      console.error("❌ Primary flight search failed:", err.message);
    }

    // Attempt 2 — LLM-refined query
    try {
      const refinedQuery = await refineQuery(query, "flights");
      const refined = await serpFlightSearch(refinedQuery);
      results.push(...refined);
      if (results.length >= 3) {
        console.log(`✈️ Found ${results.length} flights (refined query)`);
        return results.slice(0, 10);
      }
    } catch (err: any) {
      console.error("❌ Refined flight search failed:", err.message);
    }

    // Attempt 3 — Fallback APIs
    try {
      const fallback = await fallbackFlightAPIs(query);
      results.push(...fallback);
    } catch (err: any) {
      console.error("❌ Fallback flight APIs failed:", err.message);
    }

    // Deduplicate results
    const seen = new Set<string>();
    const merged = results.filter((f: any) => {
      const key = `${f.departure || ""}_${f.arrival || ""}_${f.price || ""}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });

    if (merged.length > 0) {
      console.log(`✈️ Found ${merged.length} flights (merged)`);
      return merged.slice(0, 10);
    }

    // ✅ C6 PATCH #8 — Never return empty cards
    console.warn("⚠️ No flights found, returning error card");
    return [
      {
        title: "No flights found",
        airline: "",
        price: "0",
        duration: "",
        stops: "0",
        departure: "",
        arrival: "",
        link: "",
        source: "Search",
      },
    ];
  } catch (err: any) {
    console.error("❌ Flight search error:", err.message || err);
    // ✅ C6 PATCH #8 — Never return empty cards
    return [
      {
        title: "Error loading flights",
        airline: "",
        price: "0",
        duration: "",
        stops: "0",
        departure: "",
        arrival: "",
        link: "",
        source: "Error",
      },
    ];
  }
}

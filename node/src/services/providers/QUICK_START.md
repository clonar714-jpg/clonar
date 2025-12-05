# Quick Start: Adding Any New API

## The Process is ALWAYS the Same

### 1. Create Provider File

```typescript
// node/src/services/providers/myApiProvider.ts
import { BaseProvider, FieldType, SearchOptions } from "./baseProvider";
import axios from "axios";

export class MyApiProvider implements BaseProvider {
  name = "MyAPI";
  fieldType: FieldType = "shopping"; // Change to "hotels", "flights", etc.

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    const apiKey = process.env.MY_API_KEY;
    if (!apiKey) throw new Error("Missing MY_API_KEY");

    // Call your API (query is already optimized!)
    const response = await axios.get("https://api.example.com/search", {
      headers: { 'Authorization': `Bearer ${apiKey}` },
      params: { q: query, limit: options?.limit || 20 }
    });

    // Map to standard format
    return response.data.results.map((item: any) => ({
      title: item.name,
      price: item.price || "0",
      // ... map all fields
    }));
  }
}
```

### 2. Register Provider

```typescript
// In productSearch.ts, hotelSearch.ts, flightSearch.ts, etc.
import { providerManager } from "./providers/providerManager";
import { MyApiProvider } from "./providers/myApiProvider";

providerManager.register(new MyApiProvider());
```

### 3. Done! ✅

That's it! The system automatically:
- Optimizes queries
- Tries your provider
- Falls back if it fails
- Applies filters
- Returns results

## Examples by Field

### Shopping (Shopify, Amazon, eBay)
```typescript
fieldType: FieldType = "shopping";
// See exampleProviders.ts → ShopifyProvider, AmazonProvider
```

### Hotels (TripAdvisor, Booking.com)
```typescript
fieldType: FieldType = "hotels";
// See exampleProviders.ts → TripAdvisorProvider, BookingProvider
```

### Flights (Kiwi, Amadeus)
```typescript
fieldType: FieldType = "flights";
// See exampleProviders.ts → KiwiProvider, AmadeusProvider
```

### Restaurants (Yelp, OpenTable)
```typescript
fieldType: FieldType = "restaurants";
// See exampleProviders.ts → YelpProvider
```

### Places (Google Places, Foursquare)
```typescript
fieldType: FieldType = "places";
// See exampleProviders.ts → GooglePlacesProvider
```

## Same Process, Any API! 🎯


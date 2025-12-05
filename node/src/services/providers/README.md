# Unified Provider Abstraction Layer

## Overview
**One unified system for ALL fields** (shopping, hotels, flights, restaurants, places, movies, etc.)
**Same process for ANY API** (Shopify, TripAdvisor, Kiwi, Amazon, etc.)

## Architecture

### Single Unified Interface
- **BaseProvider**: One interface for all field types
- **ProviderManager**: Manages all providers with automatic fallback
- **QueryOptimizer**: Perplexity-style query optimization for all fields
- **Backend Filters**: Universal filtering system

### How It Works

```
User Query → Query Optimization → Provider Search → Backend Filtering → Results
```

1. **Query Optimization** (Perplexity-style)
   - Removes price constraints (filter on backend)
   - Improves natural language queries
   - Field-specific optimizations

2. **Provider Search**
   - Tries providers in order
   - Automatic fallback if one fails
   - Same pattern for all fields

3. **Backend Filtering**
   - Applies price, gender, rating, etc. filters
   - More accurate than API text search

## Adding a New API (Any Field)

### Step 1: Create Provider Class

```typescript
// node/src/services/providers/myNewProvider.ts
import { BaseProvider, FieldType, SearchOptions } from "./baseProvider";

export class MyNewProvider implements BaseProvider {
  name = "MyNewAPI";
  fieldType: FieldType = "shopping"; // or "hotels", "flights", etc.

  async search(query: string, options?: SearchOptions): Promise<any[]> {
    // 1. Get API credentials
    const apiKey = process.env.MY_NEW_API_KEY;
    if (!apiKey) {
      throw new Error("Missing MY_NEW_API_KEY");
    }

    // 2. Call API (query is already optimized by ProviderManager)
    const response = await axios.get("https://api.example.com/search", {
      headers: { 'Authorization': `Bearer ${apiKey}` },
      params: {
        q: query, // Already optimized!
        limit: options?.limit || 20,
      }
    });

    // 3. Map API response to standard format
    return response.data.results.map((item: any) => ({
      title: item.name || item.title,
      price: item.price || "0",
      rating: item.rating || 0,
      // ... map all fields to standard format
    }));
  }
}
```

### Step 2: Register Provider

```typescript
// In the service file (e.g., productSearch.ts, hotelSearch.ts)
import { providerManager } from "./providers/providerManager";
import { MyNewProvider } from "./providers/myNewProvider";

// Register at startup
providerManager.register(new MyNewProvider());
```

### Step 3: Done!

The ProviderManager automatically:
- ✅ Optimizes queries (Perplexity-style)
- ✅ Tries your provider first
- ✅ Falls back to other providers if yours fails
- ✅ Applies backend filters
- ✅ Returns standardized results

## Examples

### Shopping APIs
- ✅ SerpAPI (Google Shopping) - **Implemented**
- 📝 Shopify - Template ready
- 📝 Amazon - Template ready
- 📝 eBay - Copy template

### Hotel APIs
- ✅ Google Hotels - **Implemented**
- 📝 TripAdvisor - Template ready
- 📝 Booking.com - Template ready
- 📝 Expedia - Copy template

### Flight APIs
- ✅ Current implementation
- 📝 Kiwi - Template ready
- 📝 Amadeus - Template ready
- 📝 Skyscanner - Copy template

### Restaurant APIs
- ✅ Current implementation
- 📝 Yelp - Template ready
- 📝 OpenTable - Copy template

### Places APIs
- ✅ Current implementation
- 📝 Google Places (unified) - Template ready
- 📝 Foursquare - Copy template

## Key Features

### 1. Universal Query Optimization
```typescript
// Before: "nike shoes under $200"
// After: "nike shoes" (price removed, filtered on backend)
QueryOptimizer.optimize(query, "shopping");
```

### 2. Automatic Fallback
```typescript
// Tries providers in order until one succeeds
providerManager.search(query, "shopping");
// → Tries SerpAPI → If fails, tries Shopify → If fails, tries Amazon
```

### 3. Backend Filtering
```typescript
// Price, gender, rating filters applied after fetching
// More accurate than relying on API text search
```

### 4. Same Pattern Everywhere
```typescript
// Shopping
providerManager.search(query, "shopping");

// Hotels
providerManager.search(query, "hotels");

// Flights
providerManager.search(query, "flights");

// Any field - same pattern!
```

## Files

- `baseProvider.ts` - Unified interface and query optimization
- `providerManager.ts` - Provider management and search
- `serpApiProvider.ts` - SerpAPI implementation (shopping)
- `exampleProviders.ts` - Templates for all field types
- `README.md` - This file

## Benefits

1. **One Pattern**: Same code structure for all APIs
2. **Easy Integration**: Just implement BaseProvider interface
3. **Automatic Optimization**: Queries optimized automatically
4. **Automatic Fallback**: Tries multiple providers automatically
5. **Future-Proof**: Works with any API you get tomorrow

## Migration Guide

### Old Way (Field-Specific)
```typescript
// Different interfaces for each field
ShoppingProvider, HotelProvider, FlightProvider...
```

### New Way (Unified)
```typescript
// One interface for all fields
BaseProvider<ResultType>
```

**All existing code still works!** The unified system is backward-compatible.

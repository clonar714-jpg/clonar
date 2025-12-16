# Refinement Detection Optimization

## Overview

This optimization reduces unnecessary LLM calls for follow-up/refinement detection by using a two-tier approach:

1. **Rule-Based Classifier** (High Confidence): Fast pattern matching for common, unambiguous refinements
2. **LLM Extraction** (Fallback): Used only when rules aren't confident enough or for edge cases
3. **Caching**: LLM results are cached for 1 hour to avoid redundant calls

## High-Confidence Patterns

The rule-based classifier detects these patterns with 85-95% confidence:

### Price/Luxury Modifiers (95% confidence)
- "only luxury", "just premium", "show expensive"
- "cheaper ones", "budget options", "affordable hotels"
- "only cheap", "just budget"

### Star Ratings (95% confidence)
- "only 5 star", "just 4 stars"
- "5-star hotels", "4 star only"

### Location Refinements (90% confidence)
- "near airport", "close to downtown", "around beach"
- "near [location]"

### Vague Refinements (85% confidence, requires parent context)
- "only more", "just ones", "show them"
- "cheaper", "luxury" (standalone)

## Decision Flow

```
Query → Rule-Based Classifier
  ├─ Confidence >= 0.85 → Use Rules (No LLM call)
  └─ Confidence < 0.85 → Check Cache
      ├─ Cache Hit → Use Cached LLM Result
      └─ Cache Miss → Call LLM → Cache Result
```

## Confidence Scores

- **Rules (High Confidence)**: 0.85 - 0.95
- **LLM (Medium Confidence)**: 0.70 - 0.90
- **Fallback (Low Confidence)**: 0.50

The system uses the highest-confidence decision available.

## Caching

- **Key**: MD5 hash of (query + parentQuery + conversationHistory hash)
- **TTL**: 1 hour
- **Storage**: In-memory Map
- **Cleanup**: Automatic every 30 minutes

## Performance Impact

### Before Optimization
- Every follow-up query → LLM call
- ~500-1000ms per LLM call
- High API costs

### After Optimization
- ~60-70% of follow-up queries → Rule-based (0ms)
- ~20-30% of follow-up queries → Cached LLM (0ms)
- ~10-20% of follow-up queries → Fresh LLM call (~500ms)

**Expected reduction**: 80-90% reduction in LLM calls for follow-up queries

## Debug Logging

In development mode, the system logs:
- Rule-based decisions with confidence scores
- Cache hits/misses
- LLM calls with confidence scores
- Decision method (rules/llm-cached/llm/fallback)

Example logs:
```
✅ Rule-based extraction (confidence: 0.95): "only luxury"
💾 Cached LLM extraction (confidence: 0.85): "near airport"
🧠 LLM extraction (confidence: 0.80, method: llm): "something ambiguous"
```

## Configuration

No configuration needed. The system automatically:
- Uses rules for high-confidence patterns
- Falls back to LLM for ambiguous queries
- Caches LLM results automatically

## Backward Compatibility

- Same API surface
- Same behavior for users
- No breaking changes
- LLM remains available as fallback


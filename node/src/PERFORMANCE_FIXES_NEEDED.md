# Performance Fixes Needed: Why 64 Seconds?

## 🔍 Root Cause Analysis

From logs: **64 seconds total** for "michael kors waatch"

### Identified Bottlenecks:

1. **LLM Answer Generation (BLOCKING) - 2-5 seconds**
   - Line 63: `await getAnswerNonStream()` 
   - **Problem**: Blocks EVERYTHING before search starts
   - **Impact**: Adds 2-5 seconds to every query

2. **Follow-up Suggestions (BLOCKING) - 3-10 seconds**
   - Line 664: `await followUpPromise`
   - **Problem**: Waits for follow-ups before sending response
   - **Impact**: Adds 3-10 seconds
   - **Details**: `rerankFollowUps` makes 12 embedding calls (12 × 300ms = 3.6s)

3. **Query Refinement (Sequential) - 1-2 seconds**
   - Line 154: `await refineQueryC11()`
   - **Problem**: Sequential LLM call before search
   - **Impact**: Adds 1-2 seconds

4. **Batch Summarization (Should be fast) - 0.6-0.8 seconds**
   - Line 72: Batch summarization
   - **Status**: Should be fast, but verify

## 📊 Time Breakdown Estimate

| Operation | Time | Status |
|-----------|------|--------|
| LLM Answer (blocking) | 2-5s | ❌ Blocking |
| Query Refinement | 1-2s | ❌ Sequential |
| SerpAPI Search | 2-5s | ✅ Fast |
| Filtering/Reranking | 0.5-1s | ✅ Fast |
| Batch Summarization | 0.6-0.8s | ✅ Fast |
| Follow-up Reranking (12 embeddings) | 3-6s | ❌ Blocking |
| **Total Expected** | **9-20s** | ❌ But logs show 64s! |

**64 seconds is WAY too long!** Something else is blocking.

## 🔍 Possible Additional Causes

1. **Network latency** - Multiple API calls with network delays
2. **Rate limiting** - OpenAI rate limits causing retries
3. **Large payload** - Batch summarization with 15 products might be slow
4. **Sequential operations** - Not enough parallelization

## ✅ Solutions

### Priority 1: Make LLM Answer Non-Blocking for Shopping
- Start answer generation in parallel
- Continue with search immediately
- Await answer only when needed (for `correctCards`)

### Priority 2: Make Follow-ups Non-Blocking
- Don't wait for follow-ups before sending response
- Add 5-second timeout
- Send response immediately, add follow-ups when ready

### Priority 3: Optimize Follow-up Reranking
- Cache embeddings
- Reduce number of candidates before reranking
- Use faster embedding model if available

### Priority 4: Add Performance Logging
- Log time for each major operation
- Identify exact bottleneck

## 🎯 Expected Performance After Fixes

| Operation | Before | After | Improvement |
|-----------|--------|-------|-------------|
| LLM Answer | 2-5s (blocking) | 0s (parallel) | **2-5s saved** |
| Follow-ups | 3-10s (blocking) | 0s (timeout) | **3-10s saved** |
| **Total** | **64s** | **5-10s** | **6-13× faster** |


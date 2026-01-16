# Follow-Up Suggestions System - Complete Explanation

## 🎯 Overview

The follow-up suggestions system generates contextual follow-up questions after each answer. It uses a **Perplexity-style multi-step approach** with templates, LLM-based gap extraction, and intelligent scoring.

---

## 📍 Where It's Called

### **Backend: `node/src/agent/APISearchAgent.ts` (Line 847-888)**

After the answer is generated, the system calls:

```typescript
// Step 8: Generate follow-up suggestions using Perplexity-style system
const followUpResult = await getFollowUpSuggestions({
  query: input.followUp,
  answer: answerText,
  intent,
  cards,
  sessionId: session.id,
});

followUpSuggestions = followUpResult.suggestions;
```

**Location in flow:**
1. Query classification ✅
2. Widget execution ✅
3. Research execution ✅
4. Answer generation ✅
5. **Follow-up suggestions generation** ← HERE
6. Final event sent to frontend

---

## 🔧 Main Implementation

### **File: `node/src/followup/index.ts`**

This is the **main orchestrator** that combines multiple strategies:

#### **Step-by-Step Process:**

1. **Slot Extraction** (`cardAnalyzer.ts`)
   - Extracts: `brand`, `category`, `price`, `city` from query
   - Example: "hotels in Charlotte" → `{ city: 'Charlotte' }`

2. **Template Selection** (`templates.ts`)
   - Domain-specific templates based on intent:
     - `shopping` → "Compare popular models?", "Any alternatives under {price}?"
     - `hotels` → "Which areas are best to stay in {city}?", "Best budget-friendly options?"
     - `restaurants` → "Top dishes to try?", "Cheapest good-rated places?"
     - `places` → "Best waterfalls?", "Top temples?"
     - `general` → "Want more details?", "Need examples?"

3. **Slot Filling** (`slotFiller.ts`)
   - Fills templates with extracted slots
   - Example: "Which areas are best to stay in {city}?" → "Which areas are best to stay in Charlotte?"

4. **Attribute Extraction** (`attributeExtractor.ts`)
   - Extracts attributes from answer text (purpose, style, etc.)

5. **Answer Coverage Detection** (`answerCoverage.ts`)
   - Detects what was already answered (comparison, price, durability, use case)
   - Prevents redundant follow-ups

6. **Answer Gap Extraction** (`answerGapExtractor.ts`) ⭐ **LLM-BASED**
   - Uses GPT-4o-mini to analyze answer and identify information gaps
   - Generates 2-3 follow-ups based on missing information
   - Example: If answer doesn't mention prices → suggests "What are the prices?"

7. **Template-Based Follow-ups**
   - Combines slot-filled templates + attribute-based follow-ups

8. **Filtering**
   - Removes follow-ups that were already answered
   - Example: If answer already compares items → removes "Compare..." follow-ups

9. **Embedding-Based Reranking** (`rerankFollowups.ts`)
   - Uses embeddings to rank follow-ups by relevance to query + answer

10. **Smart Follow-ups Fallback** (`smartFollowups.ts`) ⭐ **LLM-BASED**
    - If not enough ranked follow-ups (< 3), uses GPT-4o-mini to generate more
    - Fallback: ["Tell me more", "What else should I know?", "Any related information?"]

11. **Multi-Factor Scoring** (`followupScorer.ts`)
    - Scores each follow-up based on:
      - **Embedding score**: Semantic relevance
      - **Behavior score**: Matches user's inferred goal (comparison, budget, etc.)
      - **Stage match**: Matches intent stage (explore, compare, narrow, act)
      - **Gap match**: Addresses information gaps
      - **Novelty score**: Not repeated from history

12. **Intent Stage Inference** (`intentStage.ts`)
    - Infers user's intent stage:
      - `explore`: "best hotels", "top restaurants"
      - `compare`: "compare X vs Y"
      - `narrow`: "under $100", "only luxury"
      - `act`: "book", "buy", "reserve"

13. **Final Selection**
    - Sorts by score, takes top 3
    - Updates behavior state (follow-up history, user goal)

---

## 📊 Data Flow

```
User Query: "hotels in Charlotte"
  ↓
Answer Generated: "Here are the best hotels in Charlotte..."
  ↓
getFollowUpSuggestions() called
  ↓
┌─────────────────────────────────────────────────┐
│ 1. Extract slots: { city: 'Charlotte' }       │
│ 2. Select templates: hotels domain              │
│ 3. Fill slots: "Which areas are best..."       │
│ 4. Extract attributes from answer               │
│ 5. Detect answer coverage                       │
│ 6. Extract gaps (LLM): "What about prices?"     │
│ 7. Combine all follow-ups                       │
│ 8. Filter redundant ones                        │
│ 9. Rerank by embedding                          │
│ 10. Add smart follow-ups if needed (LLM)        │
│ 11. Score each follow-up                        │
│ 12. Return top 3                                │
└─────────────────────────────────────────────────┘
  ↓
Follow-up suggestions: [
  "Which areas are best to stay in Charlotte?",
  "Best budget-friendly options?",
  "Hotels near major attractions?"
]
  ↓
Sent to frontend via SSE 'end' event
  ↓
Displayed in UI as clickable chips
```

---

## 🔑 Key Components

### **1. Templates (`templates.ts`)**
- **Purpose**: Domain-specific follow-up templates
- **Domains**: shopping, hotels, restaurants, flights, places, location, general
- **Example**: `hotels` domain has 8 templates like "Which areas are best to stay in {city}?"

### **2. Answer Gap Extractor (`answerGapExtractor.ts`)**
- **Purpose**: LLM-based gap detection
- **Model**: GPT-4o-mini
- **Input**: Query + Answer (first 1000 chars)
- **Output**: 2-3 follow-up questions about missing information
- **Example**: If answer doesn't mention prices → suggests price-related follow-ups

### **3. Smart Follow-ups (`smartFollowups.ts`)**
- **Purpose**: LLM-based fallback generator
- **Model**: GPT-4o-mini
- **When used**: If < 3 ranked follow-ups
- **Input**: Query, answer, intent, slots (brand, category, price, city)
- **Output**: 3-4 contextual follow-up questions

### **4. Follow-up Scorer (`followupScorer.ts`)**
- **Purpose**: Multi-factor scoring
- **Factors**:
  - Embedding score (semantic relevance)
  - Behavior score (matches user goal)
  - Stage match (matches intent stage)
  - Novelty score (not repeated)
  - Gap match (addresses information gaps)

### **5. Reranker (`rerankFollowups.ts`)**
- **Purpose**: Embedding-based reranking
- **Method**: Uses embeddings to rank follow-ups by relevance to query + answer

---

## 🎨 Frontend Display

### **Where It's Shown:**
- **PerplexityAnswerWidget** (`lib/widgets/PerplexityAnswerWidget.dart`)
- **Method**: `_buildFollowUps(context)`
- **Display**: Clickable chips below the answer

### **How It's Used:**
- User clicks a follow-up chip
- Frontend calls `agentControllerProvider.submitFollowUp(followUpText, previousQuery)`
- New query is submitted with context from previous query

---

## 📝 Current Implementation Summary

### **Backend Flow:**
```
APISearchAgent.searchAsync()
  ↓
Answer generation complete
  ↓
getFollowUpSuggestions() from node/src/followup/index.ts
  ↓
Multi-step process (templates + LLM + scoring)
  ↓
Returns top 3 suggestions
  ↓
Sent to frontend in 'end' event
```

### **Frontend Flow:**
```
PerplexityAnswerWidget receives session.followUpSuggestions
  ↓
_buildFollowUps() displays as chips
  ↓
User clicks chip
  ↓
submitFollowUp() called
  ↓
New query submitted with previous context
```

---

## 🔍 Key Files

### **Backend:**
- `node/src/followup/index.ts` - Main orchestrator
- `node/src/followup/templates.ts` - Domain templates
- `node/src/followup/answerGapExtractor.ts` - LLM gap extraction
- `node/src/followup/smartFollowups.ts` - LLM fallback generator
- `node/src/followup/followupScorer.ts` - Multi-factor scoring
- `node/src/followup/rerankFollowups.ts` - Embedding reranking
- `node/src/followup/cardAnalyzer.ts` - Slot extraction
- `node/src/followup/slotFiller.ts` - Template slot filling
- `node/src/followup/answerCoverage.ts` - Coverage detection
- `node/src/followup/intentStage.ts` - Intent stage inference
- `node/src/agent/APISearchAgent.ts` - Calls follow-up generator (line 847-888)

### **Frontend:**
- `lib/widgets/PerplexityAnswerWidget.dart` - Displays follow-ups
- `lib/providers/agent_provider.dart` - Handles follow-up submission

---

## 💡 Example Flow

**Query**: "hotels in Charlotte"

**Answer Generated**: "Here are the best hotels in Charlotte: [list of hotels with ratings, prices, locations]"

**Follow-up Generation Process:**
1. Extract slots: `{ city: 'Charlotte' }`
2. Select `hotels` domain templates
3. Fill slots: "Which areas are best to stay in Charlotte?"
4. Extract gaps (LLM): "What about hotels with free breakfast?"
5. Combine: 8 templates + 2 gap-based = 10 candidates
6. Filter: Remove if already answered
7. Rerank: By embedding relevance
8. Score: Multi-factor scoring
9. Return top 3: 
   - "Which areas are best to stay in Charlotte?"
   - "Best budget-friendly options?"
   - "Hotels near major attractions?"

**Frontend Display:**
- Shows 3 clickable chips below answer
- User clicks "Which areas are best to stay in Charlotte?"
- New query submitted with previous context

---

## 🎯 Summary

**Follow-up suggestions come from:**
1. **Templates** (domain-specific, slot-filled)
2. **LLM Gap Extraction** (identifies missing information)
3. **LLM Smart Follow-ups** (fallback if needed)
4. **Scored and ranked** (multi-factor scoring + embedding reranking)
5. **Top 3 returned** to frontend

**Current implementation is sophisticated** with:
- ✅ Domain-specific templates
- ✅ LLM-based gap detection
- ✅ Multi-factor scoring
- ✅ Embedding-based reranking
- ✅ Behavior tracking (follow-up history)
- ✅ Intent stage inference

---

**Last Updated**: 2024
**Version**: 1.0


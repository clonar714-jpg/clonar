# 🧪 Testing LLM-Based Context Understanding

## ✅ Implementation Complete

**What's Been Done:**
1. ✅ Created `llmContextExtractor.ts` - LLM-based context extraction
2. ✅ Integrated into `agent.ts` - Replaced brittle keyword matching
3. ✅ Added fallback mechanisms - Always works
4. ✅ No linter errors - Code is clean

---

## 🧪 How to Test

### Test Case 1: Case Sensitivity (Original Issue)

**Steps:**
1. Query 1: `"hotels in bangkok"` (lowercase)
2. Query 2: `"only 5 star hotels"` (in same chat)

**Expected Result:**
- ✅ Should return 5-star hotels in **Bangkok** (not Boston or other cities)
- ✅ Logs should show: `🧠 LLM Context Extraction` and `🔗 LLM Query Merging`

**What to Check:**
- Look for logs: `"5 star hotels in Bangkok"` or similar
- Verify hotels returned are in Bangkok

---

### Test Case 2: Implicit Context

**Steps:**
1. Query 1: `"nike shoes"`
2. Query 2: `"cheaper ones"`

**Expected Result:**
- ✅ Should return cheaper Nike shoes
- ✅ LLM should understand "ones" refers to Nike shoes

---

### Test Case 3: Location Preservation

**Steps:**
1. Query 1: `"restaurants in paris"`
2. Query 2: `"luxury ones"`

**Expected Result:**
- ✅ Should return luxury restaurants in **Paris**
- ✅ Location should be preserved from parent query

---

### Test Case 4: Case Variations

**Steps:**
1. Query 1: `"hotels in BANGKOK"` (uppercase)
2. Query 2: `"only 5 star hotels"`

**Expected Result:**
- ✅ Should work regardless of case
- ✅ Should return Bangkok hotels

---

## 📊 What to Look For in Logs

### Success Indicators:

```
🧠 LLM Context Extraction: "only 5 star hotels" → { city: null, needsParentContext: true, ... }
🔗 LLM Query Merging: "only 5 star hotels" + "hotels in bangkok" → "5 star hotels in Bangkok"
```

### Fallback Indicators (if LLM fails):

```
❌ LLM context extraction failed, falling back to rule-based: [error]
📍 Fallback: Merged location from parent: "Bangkok" → "..."
```

### Error Indicators (should not happen):

```
❌ LLM context extraction error: [error]
❌ LLM query merging error: [error]
```

---

## 🔍 Debugging

### If It Doesn't Work:

1. **Check OpenAI API Key:**
   - Ensure `OPENAI_API_KEY` is set in `.env`
   - Check if API key is valid

2. **Check Logs:**
   - Look for LLM extraction logs
   - Check for fallback triggers
   - Verify error messages

3. **Check Fallback:**
   - If LLM fails, fallback should still work
   - Check fallback logs

4. **Test LLM Directly:**
   - Try calling `extractContextWithLLM` directly
   - Check if OpenAI API is accessible

---

## 🎯 Expected Behavior

### Scenario: "hotels in bangkok" → "only 5 star hotels"

**What Should Happen:**

1. **Context Extraction:**
   ```
   Query: "only 5 star hotels"
   Parent: "hotels in bangkok"
   Extracted: {
     city: null,
     needsParentContext: true,
     isRefinement: true,
     modifiers: ["5-star"]
   }
   ```

2. **Query Merging:**
   ```
   Current: "only 5 star hotels"
   Parent: "hotels in bangkok"
   Merged: "5 star hotels in Bangkok"
   ```

3. **Search:**
   ```
   Search query: "5 star hotels in Bangkok"
   Results: Hotels in Bangkok (5-star rated)
   ```

---

## 📝 Test Checklist

- [ ] Test case sensitivity (bangkok vs Bangkok)
- [ ] Test implicit context ("cheaper ones")
- [ ] Test location preservation
- [ ] Test refinement queries ("only 5 star")
- [ ] Check logs for LLM extraction
- [ ] Verify fallback works if LLM fails
- [ ] Test with different intents (hotels, restaurants, shopping)

---

## 🚀 Quick Test Command

**Start your server:**
```bash
cd node
npm run dev
```

**Test in your app:**
1. Open your Flutter app
2. Query 1: "hotels in bangkok"
3. Query 2: "only 5 star hotels" (in same chat)
4. Check results - should be Bangkok hotels
5. Check server logs - should see LLM extraction logs

---

## 💡 Tips

1. **Monitor Logs:** Watch for `🧠 LLM Context Extraction` logs
2. **Check Fallback:** If you see fallback logs, LLM might have failed (check API key)
3. **Test Variations:** Try different case variations to verify robustness
4. **Compare Results:** Before vs after - should see better context understanding

---

## ✅ Success Criteria

**The system is working if:**
- ✅ Follow-up queries preserve location from parent query
- ✅ Case variations work (bangkok, Bangkok, BANGKOK)
- ✅ Implicit context is understood ("cheaper ones", "luxury ones")
- ✅ Logs show LLM extraction (or fallback if LLM fails)
- ✅ Results are correct (not random cities)

---

**Ready to test!** 🎉


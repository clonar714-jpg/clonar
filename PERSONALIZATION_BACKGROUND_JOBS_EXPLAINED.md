# 🕐 Background Aggregation - Simple Explanation

## What Does "Runs Every Hour" Mean?

In simple terms: **Every hour, the system automatically reviews all users' search history and updates their preferences.**

Think of it like a **personal assistant that works in the background** - you don't see it working, but it's constantly learning about you and updating your profile.

---

## 🎯 Simple Analogy

**Like a Personal Shopper Learning Your Tastes:**

Imagine you have a personal shopper who:
1. **Watches what you search for** (Phase 1 - collects signals)
2. **Takes notes** (stores in database)
3. **Every hour, reviews their notes** (background job)
4. **Updates your profile** (aggregates preferences)
5. **Uses the profile to help you** (Phases 2 & 3)

You don't see them reviewing notes - they do it automatically in the background!

---

## 🔄 What Happens Every Hour?

### Step-by-Step (Simple Terms)

**Every hour, the system:**

1. **Looks at all users** who have made searches
   - "Who has been searching recently?"

2. **For each user, checks:**
   - "Have they made 5+ searches since we last updated their preferences?"
   - "OR has it been 24 hours since we last updated?"

3. **If yes, it:**
   - Reviews all their recent searches
   - Counts what they searched for:
     * How many times did they search for "luxury"?
     * How many times did they search for "Prada"?
     * What price ranges did they mention?
   - Calculates patterns:
     * "They searched for 'luxury' in 3 out of 5 searches = 60% → They prefer luxury!"
     * "They searched for 'Prada' in 2 out of 5 searches = 40% → They like Prada!"
   - Updates their preference profile:
     * "This user prefers: luxury style, Prada brand, under $500"

4. **Cleans up old data:**
   - Keeps last 100 searches
   - Deletes older searches (to save space)

---

## 📊 Real Example

### User's Search History (Last 5 Searches)

```
Search 1: "prada luxury glasses"
Search 2: "luxury watches under $500"
Search 3: "gucci bags"
Search 4: "luxury hotels in miami"
Search 5: "prada sunglasses"
```

### What the Background Job Does (Every Hour)

**Reviews these 5 searches and finds:**
- "luxury" appears in 3 searches (60%) → **Strong preference!**
- "Prada" appears in 2 searches (40%) → **Preference!**
- "under $500" appears in 1 search (20%) → **Mild preference**

**Updates user profile:**
```
User Preferences:
  - Style: luxury (60% confidence)
  - Brand: Prada (40% confidence)
  - Price: under $500 (20% confidence)
```

**Now when user searches:**
- "glasses" → System knows they want "Prada luxury glasses"
- "hotels" → System knows they want "luxury hotels"
- "of my taste" → System knows their taste preferences

---

## ⏰ Why Every Hour?

### Two Triggers for Aggregation

**Trigger 1: Conversation Count**
- User makes 5 searches → **Aggregate immediately!**
- Doesn't wait for the hour

**Trigger 2: Time-Based (Every Hour)**
- Even if user only made 2 searches
- After 24 hours → **Aggregate anyway!**
- Ensures preferences stay up-to-date

### Why Not Real-Time?

**Too Expensive:**
- Analyzing preferences takes time
- If done after every search → Slows down responses
- Users would wait longer for results

**Not Necessary:**
- Preferences don't change that fast
- Hourly updates are frequent enough
- Immediate updates happen after 5 searches anyway

---

## 🎬 Simple Timeline Example

### Day 1 - Morning

**9:00 AM**: User searches "action movies"
- Signal stored: `genres: ["action"]`
- Count: 1

**10:00 AM**: Background job runs
- Checks user: Only 1 search → **Skip** (need 5+)

**11:00 AM**: User searches "thriller movies"
- Signal stored: `genres: ["thriller"]`
- Count: 2

**12:00 PM**: Background job runs
- Checks user: Only 2 searches → **Skip**

### Day 1 - Afternoon

**1:00 PM**: User searches "best movies 2024"
- Signal stored: `rating: ["high"]`
- Count: 3

**2:00 PM**: User searches "sci-fi movies"
- Signal stored: `genres: ["sci-fi"]`
- Count: 4

**3:00 PM**: User searches "movies with 8 rating"
- Signal stored: `rating_min: 8`
- Count: 5

**3:00 PM**: Background job runs
- Checks user: **5 searches!** → **Aggregate!**
- Reviews all 5 searches
- Finds: User prefers action/thriller/sci-fi, high ratings
- Updates preferences
- Resets count to 0

**4:00 PM**: User searches "movies of my kind"
- System uses NEW preferences
- Returns: Action/thriller/sci-fi movies with 8+ rating!

---

## 🔍 What Gets Updated?

### Before Aggregation
```
User has 5 signals:
  - Search 1: "luxury hotels"
  - Search 2: "luxury watches"
  - Search 3: "budget flights"
  - Search 4: "luxury restaurants"
  - Search 5: "luxury bags"
```

### After Aggregation (Every Hour)
```
System analyzes:
  - "luxury" appears 4 times (80%) → Strong preference!
  - "budget" appears 1 time (20%) → Not strong enough

User Preferences Updated:
  - style_keywords: ["luxury"]
  - confidence_score: 0.4 (4 searches / 10 = 0.4)
```

### Now System Knows:
- User prefers luxury items
- When they search "hotels" → Add "luxury"
- When they search "of my taste" → Match luxury items

---

## 💡 Key Points (Simple Terms)

1. **"Runs Every Hour"** = System automatically reviews all users every hour
2. **"Background"** = Happens automatically, you don't see it
3. **"Aggregation"** = System looks at all your searches and figures out your preferences
4. **"Updates Preferences"** = System saves what it learned about you
5. **"Cleans Up"** = Deletes old search data (keeps last 100)

---

## 🎯 Why This Matters

**Without Background Job:**
- System collects signals but never learns from them
- Preferences never get updated
- "Of my taste" queries wouldn't work
- System can't personalize results

**With Background Job:**
- System automatically learns from your behavior
- Preferences get updated regularly
- "Of my taste" queries work perfectly
- System gets smarter over time

---

## 📈 Real-World Example

### Week 1
```
Monday: User searches "luxury hotels" (1 search)
Tuesday: User searches "luxury watches" (2 searches)
Wednesday: User searches "luxury restaurants" (3 searches)
Thursday: User searches "luxury bags" (4 searches)
Friday: User searches "luxury glasses" (5 searches)
    ↓
Background job runs (Friday evening):
  - Analyzes 5 searches
  - Finds: "luxury" in ALL 5 searches (100%!)
  - Updates: User prefers luxury (high confidence)
```

### Week 2
```
Monday: User searches "hotels"
  - System: "I know they prefer luxury!"
  - Enhanced: "luxury hotels"
  - Returns: Luxury hotels (personalized!)

Tuesday: User searches "of my taste"
  - System: "I know their taste preferences!"
  - Matches: Luxury items
  - Returns: Personalized results
```

---

## ✅ Summary

**"Runs Every Hour" means:**

Every hour, like clockwork, the system:
1. ✅ Checks all users
2. ✅ Reviews their search history
3. ✅ Figures out their preferences
4. ✅ Updates their profile
5. ✅ Cleans up old data

**You don't see it happening** - it's like a background process that makes the system smarter automatically!

**Result:** The system learns your preferences and uses them to give you better, more personalized results! 🎯


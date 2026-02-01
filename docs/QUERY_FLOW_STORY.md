# What Happens Between Your Question and the Answer You See

This document explains, in plain language, what happens from the moment you type a question and tap search until the answer appears on your screen. No technical jargon required—just a step-by-step story with real examples.

We’ll follow **two example questions** through the whole flow:

1. **“Hotels in Boston under $150 with good wifi”** — one clear request (hotels).
2. **“Flights to NYC and hotels near the airport”** — two requests in one (flights + hotels).

---

## Step 1: You Type and Send

You type your question in the search bar (e.g. *“Hotels in Boston under $150 with good wifi”* or *“Flights to NYC and hotels near the airport”*). You may have already said something earlier in the chat (e.g. *“I’m going to Boston next month”*). You also choose **Quick** or **Deep** mode on the Shop screen before searching—Quick is faster; Deep does extra research and refinement.

The app sends to the server:

- Your **message** (the question you just typed)
- **History** (the last few messages in the chat, so “there” or “this weekend” can be understood)
- **Mode** (Quick or Deep)

**Example:**  
If you said *“I’m thinking Boston”* and then *“Hotels there under $150 with good wifi”*, the server receives both so it can turn “there” into “Boston.”

---

## Step 2: The System Figures Out What You Want (The Plan)

The server’s first job is to **understand your question** and build a **plan**: what you’re asking for, where, when, and what matters to you. It does **not** search the web or databases yet—it only decides *what* to look for.

### 2.1 Making Your Question Clear

The system rewrites your message into one clear, full sentence. It uses your chat history to fill in missing bits.

| What you typed | What the system understands |
|----------------|-----------------------------|
| *“Hotels there under $150 with good wifi”* (after you said “Boston”) | *“Hotels in Boston under $150 with good wifi.”* |
| *“Flights to NYC and hotels near the airport”* | *“Flights to NYC and hotels near the NYC airport.”* (it knows “the airport” means NYC’s airports.) |
| *“Something nice for this weekend”* (after you said “Boston”) | *“Something nice in Boston for [specific dates, e.g. Jan 31–Feb 2].”* |

It also turns vague times into real dates when needed (e.g. “this weekend” → actual dates like Jan 31–Feb 2) so filters and search use exact dates.

### 2.2 Splitting One Message Into Parts (When You Ask for More Than One Thing)

If your clear sentence has **more than one kind of request**, the system splits it into **parts** and labels each part.

**Example — “Flights to NYC and hotels near the airport”:**

- **Part 1:** “Flights to NYC” → labeled **flights**
- **Part 2:** “Hotels near the NYC airport” → labeled **hotels**

**Example — “Hotels in Boston under $150 with good wifi”:**

- One part only: “Hotels in Boston under $150 with good wifi” → labeled **hotels**

The system uses five labels: **products** (things to buy), **hotels**, **flights**, **movies** (showtimes), and **other** (everything else—weather, things to do, general questions). So “things to do in NYC and a family-friendly hotel” becomes two parts: one **hotels**, one **other**.

### 2.3 What You Want To Do (Browse, Compare, Buy, Book)

For each part, the system decides your **intent**:

- **Browse** — “Show me options,” “What’s good,” “Ideas for…”
- **Compare** — “Which is better,” “MacBook vs ThinkPad”
- **Buy** — “I want to buy this”
- **Book** — “Reserve it,” “Book a room”

**Example:**  
*“Compare flights to NYC and suggest some nice hotels”* → flights: **compare**; hotels: **browse**.

### 2.4 What Matters To You (Preferences)

Besides place and dates, the system pulls out **preferences** in plain language (e.g. “under $150,” “good wifi,” “quiet,” “near the airport”). It also **orders** them by importance (e.g. price first, then location, then wifi). That order is used later when results are thin: the system can suggest relaxing the **least important** preference first to get more options.

**Example — “Cheap flights to JFK and a quiet hotel near LaGuardia”:**

- Flight part: preference “cheap”
- Hotel part: preferences “quiet,” “near LaGuardia”

**Example — “Hotels under $150 with good wifi near the airport”:**

- Preferences: e.g. “under $150” (first), “near airport” (second), “good wifi” (third). If few results are found, the system might say: “You might relax ‘good wifi’ for more options.”

Those preferences are used when searching and when writing the answer so results and text match what you care about.

### 2.5 Filling In the “Form” (Dates, Places, Guests, etc.)

For hotels, flights, products, and movies, the system fills in a **form**:

- **Hotels:** city, area, check-in/out dates, number of guests
- **Flights:** origin, destination, depart/return dates, adults
- **Products:** what you’re looking for, category, budget
- **Movies:** city, movie name, date, number of tickets

**Example — “Hotels in Boston under $150 with good wifi”:**

- City: Boston  
- Dates: default or from “this weekend” if you said that  
- Preferences (not in the form, but used for ranking): under $150, good wifi  

**Example — “Flights to NYC and hotels near the airport”:**

- Flight form: destination NYC, dates default or from your message  
- Hotel form: city NYC, area “near airport,” dates same idea  

### 2.6 The Plan Is Ready

At the end of this step, the server has a **plan** that says:

- What you meant (one clear rewritten sentence)
- How many parts (e.g. two: flights + hotels) and what type each is
- Your intent and **ordered** preferences per part (most important first)
- Filled-in “forms” for each type (hotel, flight, etc.)
- Any **soft** bits (e.g. “airport” not pinned to JFK/LGA until results are in)

It still has **not** run any search. It only decided *what* to look for. If you ask the same question again (or retry), the server can reuse this plan from cache so it doesn’t recompute everything.

---

## Step 3: The System Looks Up Answers (Search and Summarize)

Now the server uses the plan to **actually look things up** and **write an answer**.

### 3.1 Which “Desks” Get Used

The plan has a list of **candidates** (e.g. “flights” and “hotels”). The server picks which of these to run: usually the main one plus any other that scored close enough. For *“Flights to NYC and hotels near the airport”* it runs **both** flights and hotels at the same time (in parallel), so the total wait is about as long as the slower of the two, not the sum.

### 3.2 What Each “Desk” Does

- **Hotels, Flights, Products, Movies:**  
  The server runs **search** using the form (city, dates, etc.) and your preferences. It pulls in multiple bits of text (snippets), drops duplicates, and then **one summarizer** writes a short answer and **cites** which snippet each fact came from (e.g. [1], [2]). It can also use your preferences to rank results (e.g. “good wifi,” “near airport”) and to add extra search phrasings when your request has several parts (e.g. “cheap” and “quiet”) so it doesn’t miss good options.  
  The result: a **summary**, a list of **cards** (e.g. hotel or flight options), and a list of **sources** (citations).

- **Other (weather, things to do, general questions):**  
  For **time-sensitive** questions (e.g. weather, “what’s happening”), the server calls a **web overview** (e.g. Perplexity-style) and gets an answer plus sources. For **timeless** questions it may use a general-knowledge assistant without web search.  
  The result: a **summary** and, when the provider returns them, **sources**.

### 3.3 Who Goes First on the Screen

The server doesn’t always show results in the order it *guessed* (e.g. flights first). It checks **how good** each “desk’s” results were (e.g. how many items, how relevant). The one with the **best** results becomes the **main** answer you see first; the others appear as “Also relevant (flights)” or “Also relevant (hotels)” below.

**Example:**  
If hotel search returned many strong results and flight search returned few, the **hotels** block can be shown first and flights second, so you see what actually worked best.

### 3.4 Putting Everything Into One Answer

The server merges all results into **one** response:

- **Summary:** Best part’s summary first, then “Also relevant (flights):” or “Also relevant (hotels):” with the next summary.
- **Cards:** The best part’s cards in the main area (e.g. hotel cards); the other part’s cards in a secondary area (e.g. flight cards below).
- **Sources:** All citations from every part are combined into one numbered list (e.g. “1. Title – domain – Updated 2025-01-15”).

If the main part had **weak** results (very few or low quality) but the “other” part (e.g. web overview) had a good answer, the server can still show the weak part’s cards and **add** a “Web overview (due to limited structured results):” section with the overview and its sources. Your original sources are kept, not dropped.

---

## Step 4: Fallbacks, Deep Mode, and How the App Should Show It

### 4.1 When Structured Results Are Thin (Fallback)

If the main search (e.g. hotels or flights) returned very few or low-quality items, the server **adds** a web overview. It **reframes** it so you know why it’s there: e.g. *“We found few structured options. You might relax ‘good wifi’ for more options. Here’s a broader view from the web:”* then the overview **with** its sources. Your original results and their sources stay; nothing is removed. The relaxation hint uses your **lowest-priority** preference (from the plan) so you know what to loosen first if you try again.

### 4.2 Deep Mode (Extra Research and Polish)

If you chose **Deep** mode, the server can do extra work:

- **Planner:** Decides whether to do more research.
- **Extra research:** May run another search with a slightly different phrasing to get more angles.
- **Alternate phrasings:** For hotels/flights/products/movies, it may run the same type of search again with different query wording and merge the summaries and sources.
- **Critique:** A refinement step improves the summary (e.g. clearer, more neutral). If the critique suggests a better question, that can be shown as “For a better answer, try: …” but the server does **not** throw away your answer or restart from scratch.

All of this stays in the **same** response: longer summary, more sources, same structure.

### 4.3 Hints for the App (How To Present the Answer)

Before sending the response, the server attaches **hints** for the app: e.g. “show cards,” “show a map” (for hotels with multiple results), “use list layout.” The **app** (Flutter) decides the exact layout and styling within those hints; the server doesn’t dictate pixels.

### 4.4 What Gets Sent Back (The Payload)

The server builds the **final payload** for the app. It includes:

- **Summary** (the full answer text, with “Also relevant …” sections when there are multiple parts)
- **Short answer** (first 2–4 sentences for the definition box; kept plain and non-marketing)
- **References** (numbered list: “1. Title – domain – Updated YYYY-MM-DD”)
- **Cards** (e.g. hotels, flights, products, showtimes) in main and secondary slots
- **UI hints** (show cards, show map, etc.)
- **Follow-up suggestions** (short “next question” chips the user can tap)
- **Suggested query** (when Deep mode critique suggested a better question; may be “already used” if the server replanned)
- **Cross-part hint** (when flights and hotels point to different airports, e.g. “You’re flying into JFK but hotels are for LaGuardia — want hotels near JFK?”)
- **When the answer was generated**

In Quick mode, this payload can be **cached** so the same question + history + mode returns immediately next time.

---

## Step 5: The App Receives the Response

The app sent your question to the server (e.g. POST to `/api/query`). The server now sends back **one JSON payload** with everything above. The app parses it and stores it as the **answer for this search** (e.g. in the current session). It knows: summary, cards, references, UI hints, follow-ups, etc.

---

## Step 6: What You See on Screen

The **answer screen** (e.g. ClonarAnswerWidget) uses that payload to draw what you see:

1. **Short answer** at the top (2–4 sentences in the definition box), when present.
2. **Full summary** below: the main answer and, if there were multiple parts, “Also relevant (flights)” or “Also relevant (hotels)” sections. For **comparisons** (e.g. “MacBook vs ThinkPad”), the layout is: short answer → “When to choose A vs B” block → details → references.
3. **Cards:** Hotel cards, flight cards, product cards, or movie showtime cards—with a **map** for hotels when the server said so.
4. **Sources:** A numbered list of references (e.g. “1. Title – domain – Updated 2025-01-15”) you can tap to open.
5. **Follow-up chips:** Suggested next questions you can tap.

**Example — “Hotels in Boston under $150 with good wifi”:**  
You see a short answer at the top, a paragraph or two about Boston hotels under $150 with good wifi, then hotel cards (and maybe a map), then numbered sources, then follow-up chips like “Which area is best for first-time visitors?” or “Show me mid-range options.”

**Example — “Flights to NYC and hotels near the airport”:**  
You might see hotels first if hotel results were stronger, or flights first if flight results were stronger. Either way: short answer, then the main summary and cards (e.g. hotels), then “Also relevant (flights):” with flight summary and flight cards below, then one combined source list, then follow-ups. If your flights are into JFK but hotel results were for LaGuardia, you may also see a hint: *“You’re flying into JFK but hotel results are for LaGuardia — want hotels near JFK to match your flight?”*

---

## Summary: One Path, Two Examples

| Step | What happens (in short) | “Hotels in Boston under $150” | “Flights to NYC and hotels near airport” |
|------|--------------------------|--------------------------------|------------------------------------------|
| 1 | You type and send (message + history + mode) | One question: hotels | One message, two requests |
| 2 | Server builds a plan (rewrite, split into parts, intent, preferences, forms) | One part: hotels; Boston, dates, preferences “under $150, good wifi” | Two parts: flights + hotels; “airport” = NYC airport; both get forms |
| 3 | Server runs search (parallel when multiple parts), merges, picks who’s first by quality | Hotel search → summary + cards + sources | Flight + hotel search in parallel → merge → e.g. hotels first if better results |
| 4 | Fallback (add web overview if results weak), Deep extras, UI hints, build payload | Usually no fallback; Deep adds polish if on | Same; sources from both parts combined |
| 5 | App receives one JSON payload | Stored as this search’s answer | Same |
| 6 | Screen shows short answer, summary, cards, sources, follow-ups | Definition + hotel summary + hotel cards + map? + sources + chips | Definition + main summary + main cards + “Also relevant” + secondary cards + sources + chips |

That’s the full path: from your question to the UI you see, with nothing left out in between.

---

## More Example Queries You Can Try

| You type | What happens in short |
|---------|------------------------|
| *“What’s the weather in Boston?”* | One part → **other** → web overview with sources. |
| *“Compare MacBook Air M3 vs ThinkPad X1”* | One part → **product**, intent **compare** → comparison layout (short answer → “When to choose A vs B” → details → references). |
| *“Weekend in NYC with kids – things to do and a family-friendly hotel”* | Two parts: **hotel** + **other** (things to do). Hotel gets form (NYC, weekend dates); “other” gets web overview. You see hotel summary + cards and a “things to do” section with sources. |
| *“Movie showtimes for Dune 2 in Seattle this weekend”* | One part → **movie**; “this weekend” becomes real dates → showtime cards + sources. |
| *“Best running shoes 2024”* | One part → **product** → product summary + cards + sources. |
| *“Cheap flights to JFK and a quiet hotel near LaGuardia”* | Two parts: **flight** (JFK) + **hotel** (LGA). If results show different airports, you may see a **cross-part hint**: “You’re flying into JFK but hotel results are for LaGuardia — want hotels near JFK?” |

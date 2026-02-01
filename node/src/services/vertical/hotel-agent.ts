import { VerticalPlan } from '@/types/verticals';
import { Hotel } from '@/services/providers/hotels/hotel-provider';
import { HotelRetriever } from '@/services/providers/hotels/hotel-retriever';
import { callMainLLM } from '@/services/llm-main';
import { setCache } from '@/services/cache';
import type { Citation } from '@/services/orchestrator';
import { searchReformulationPerPart } from '@/services/query-understanding';

const RETRIEVED_CONTENT_CACHE_TTL_SECONDS = 60;

type HotelPlan = Extract<VerticalPlan, { vertical: 'hotel' }>;

export interface HotelAgentResult {
  summary: string;
  hotels: Hotel[];
  citations?: Citation[];
  retrievalStats?: { vertical: 'hotel'; itemCount: number; maxItems?: number; avgScore?: number; topKAvg?: number };
}

const GROUNDING_SYSTEM = `You are a hotel search assistant. You receive two separate sections: Working memory (conversation context) and Retrieved content (factual source only). Use ONLY the Retrieved content section for factual claims and recommendations; Working memory is for intent and preferences only. This separation prevents context contamination.

Citation-first: Every factual claim or recommendation must cite a source using [1], [2], etc. corresponding to the numbered list of retrieved passages below. Do not make claims without a citation.

Rules:
- Answer based only on the Retrieved content list. If something is not covered, say you don't have enough information; don't invent details.
- Structure your answer by the user's criteria when it makes sense: e.g. a short opening summary that reflects their full request, then a "Why these fit" section that ties each recommendation back to what they asked for. Cite [1], [2], etc. after each fact.
- Say what matches their preferences and what we don't have data for.
- Use conditional language when the answer depends on unstated factors (e.g. "depending on...", "if you're okay with...").
- If the list doesn't contain anything suitable, say that you don't have good matches instead of making things up.`;

function hotelKey(h: { id?: string; name?: string; location?: string }): string {
  if (h.id) return String(h.id);
  return `${(h.name ?? '').trim()}|${(h.location ?? '').trim()}`;
}

/**
 * Fallback when LLM reformulation returns empty: rule-based queries from plan.
 */
function getSearchQueriesFallback(plan: HotelPlan): string[] {
  const main = plan.rewrittenPrompt.trim();
  const filters = plan.hotel;
  const queries: string[] = [main];
  if (filters.area?.trim() && filters.destination?.trim()) {
    const areaQuery = `hotels in ${filters.destination} near ${filters.area}`.trim();
    if (areaQuery !== main) queries.push(areaQuery);
  }
  return queries;
}

export async function runHotelAgent(
  plan: HotelPlan,
  deps: { retriever: HotelRetriever; retrievedContentCacheKey?: string },
): Promise<HotelAgentResult> {
  const filters = plan.hotel;
  const text = plan.decomposedContext?.hotel ?? plan.rewrittenPrompt;
  const llmQueries = await searchReformulationPerPart(text, 'hotel');
  let queriesToRun = llmQueries.length > 0 ? llmQueries : getSearchQueriesFallback(plan);
  // Perplexity-aligned: when decomposed slice has multiple segments (e.g. "flights NYC; cheap"), add each as a retrieval variant for broader recall.
  const slice = plan.decomposedContext?.hotel;
  if (slice?.includes(';')) {
    const segments = slice.split(';').map((s) => s.trim()).filter(Boolean).slice(0, 3);
    for (const seg of segments) {
      if (seg && !queriesToRun.some((q) => q.trim().toLowerCase() === seg.toLowerCase())) {
        queriesToRun = [...queriesToRun, seg];
      }
    }
  }
  // Perplexity-aligned: feed landmark/entity signals into at least one retrieval variant for better recall (e.g. "hotels near Stanford campus").
  const locations = plan.entities?.locations ?? [];
  const entities = plan.entities?.entities ?? [];
  const landmarks = [...locations, ...entities].filter(Boolean).slice(0, 2);
  for (const landmark of landmarks) {
    const variant = `${text} near ${landmark}`.trim();
    if (variant && !queriesToRun.some((q) => q.toLowerCase().includes(landmark.toLowerCase()))) {
      queriesToRun = [...queriesToRun, variant];
    }
  }

  const allHotels: Hotel[] = [];
  const allSnippets: Array<{ id: string; url: string; title?: string; text: string; score?: number }> = [];
  const seenHotelKeys = new Set<string>();

  for (const query of queriesToRun) {
    const { hotels, snippets } = await deps.retriever.searchHotels({
      ...filters,
      rewrittenQuery: query,
      ...(plan.preferenceContext != null && { preferenceContext: plan.preferenceContext }),
    });
    for (const h of hotels) {
      const key = hotelKey(h);
      if (!seenHotelKeys.has(key)) {
        seenHotelKeys.add(key);
        allHotels.push(h);
      }
    }
    for (const s of snippets) {
      allSnippets.push({
        id: s.id,
        url: s.url,
        title: s.title,
        text: s.text,
        score: s.score,
      });
    }
  }

  const hotels = allHotels;
  // Perplexity-aligned: boost entity-relevant snippets so summarizer sees them first (entity signals in ranking, not only query expansion).
  const entityTerms = [...(plan.entities?.locations ?? []), ...(plan.entities?.entities ?? [])].filter(Boolean).map((t) => t.toLowerCase());
  const snippets = entityTerms.length === 0
    ? allSnippets
    : [...allSnippets].sort((a, b) => {
        const aMatch = entityTerms.some((t) => (a.text + ' ' + (a.title ?? '')).toLowerCase().includes(t));
        const bMatch = entityTerms.some((t) => (b.text + ' ' + (b.title ?? '')).toLowerCase().includes(t));
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });

  // Dual memory: store retrieved content in cache (keyed by plan + vertical) so it is first-class and reusable.
  if (deps.retrievedContentCacheKey) {
    await setCache(`retrieved:${deps.retrievedContentCacheKey}:hotel`, snippets, RETRIEVED_CONTENT_CACHE_TTL_SECONDS);
  }

  // Dual memory: Working memory (conversation context) vs Retrieved content (factual source only). Citation-first: numbered passages [1], [2], ...
  const workingMemory = {
    userQuery: plan.rewrittenPrompt,
    preferenceContext: plan.preferenceContext ?? undefined,
    filters,
  };
  const retrievedPassages = snippets.map((s, i) => `[${i + 1}] ${(s.title ? s.title + ': ' : '')}${s.text.replace(/\s+/g, ' ').slice(0, 400)}`).join('\n');
  const userContent = `
Working memory (conversation context — for intent and preferences only; do not cite as factual source):
${JSON.stringify(workingMemory)}

Retrieved content (use only these for factual claims; cite as [1], [2], ...):
${retrievedPassages}

Hotel list (from retrieved content): ${JSON.stringify(hotels.slice(0, 20).map((h) => ({ name: h.name, location: h.location })))}
`;

  const summary = await callMainLLM(GROUNDING_SYSTEM, userContent);

  const citations: Citation[] = snippets.map((s) => ({
    id: s.id,
    url: s.url,
    title: s.title,
    snippet: s.text,
  }));

  const avgScore =
    snippets.length > 0
      ? snippets.reduce((a, s) => a + (s.score ?? 0), 0) / snippets.length
      : 0;
  const topKAvg =
    snippets.length > 0
      ? (() => {
          const sorted = [...snippets].sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
          const top3 = sorted.slice(0, 3);
          return top3.reduce((a, s) => a + (s.score ?? 0), 0) / top3.length;
        })()
      : undefined;

  return {
    summary: summary.trim(),
    hotels,
    citations,
    retrievalStats: {
      vertical: 'hotel',
      itemCount: hotels.length,
      maxItems: deps.retriever.getMaxItems?.(),
      avgScore,
      topKAvg,
    },
  };
}

// src/services/vertical/flight-agent.ts
import { VerticalPlan } from '@/types/verticals';
import { Flight } from '@/services/providers/flights/flight-provider';
import { FlightRetriever } from '@/services/providers/flights/flight-retriever';
import { callMainLLM } from '@/services/llm-main';
import { setCache } from '@/services/cache';
import type { Citation } from '@/services/orchestrator';
import { searchReformulationPerPart } from '@/services/query-understanding';

const RETRIEVED_CONTENT_CACHE_TTL_SECONDS = 60;

type FlightPlan = Extract<VerticalPlan, { vertical: 'flight' }>;

export interface FlightAgentResult {
  summary: string;
  flights: Flight[];
  citations?: Citation[];
  retrievalStats?: { vertical: 'flight'; itemCount: number; maxItems?: number; avgScore?: number; topKAvg?: number };
}

const GROUNDING_SYSTEM = `You are a flight booking assistant. You receive two separate sections: Working memory (conversation context) and Retrieved content (factual source only). Use ONLY the Retrieved content section for factual claims and recommendations; Working memory is for intent and preferences only. This separation prevents context contamination.

Citation-first: Every factual claim or recommendation must cite a source using [1], [2], etc. corresponding to the numbered list of retrieved passages below. Do not make claims without a citation.

Rules:
- Answer based only on the Retrieved content list. If something is not covered, say you don't have enough information; don't invent details.
- Structure your answer by the user's criteria when it makes sense. Cite [1], [2], etc. after each fact.
- Say what matches their preferences and what we don't have data for.
- Use conditional language when the answer depends on unstated factors (e.g. "depending on...", "if you're okay with...").
- If the list doesn't contain anything suitable, say that you don't have good matches instead of making things up.`;

function flightKey(f: Flight): string {
  return f.id ?? `${f.carrier}|${f.flightNumber}|${f.departTime}`;
}

export async function runFlightAgent(
  plan: FlightPlan,
  deps: { retriever: FlightRetriever; retrievedContentCacheKey?: string },
): Promise<FlightAgentResult> {
  const filters = plan.flight;
  const text = plan.decomposedContext?.flight ?? plan.rewrittenPrompt;
  const llmQueries = await searchReformulationPerPart(text, 'flight');
  let queriesToRun = llmQueries.length > 0 ? llmQueries : [plan.rewrittenPrompt.trim()];
  // Perplexity-aligned: feed location/entity signals into at least one retrieval variant (e.g. "flights to JFK").
  const locations = plan.entities?.locations ?? [];
  const entities = plan.entities?.entities ?? [];
  const anchors = [...locations, ...entities].filter(Boolean).slice(0, 2);
  for (const anchor of anchors) {
    const variant = `${text} ${anchor}`.trim();
    if (variant && !queriesToRun.some((q) => q.toLowerCase().includes(anchor.toLowerCase()))) {
      queriesToRun = [...queriesToRun, variant];
    }
  }

  const allFlights: Flight[] = [];
  const allSnippets: Array<{ id: string; url: string; title?: string; text: string; score?: number }> = [];
  const seenFlightKeys = new Set<string>();

  for (const query of queriesToRun) {
    const { flights, snippets } = await deps.retriever.searchFlights({
      ...filters,
      rewrittenQuery: query,
      ...(plan.preferenceContext != null && { preferenceContext: plan.preferenceContext }),
    });
    for (const f of flights) {
      const key = flightKey(f);
      if (!seenFlightKeys.has(key)) {
        seenFlightKeys.add(key);
        allFlights.push(f);
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

  const flights = allFlights;
  // Perplexity-aligned: boost entity-relevant snippets so summarizer sees them first.
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

  if (deps.retrievedContentCacheKey) {
    await setCache(`retrieved:${deps.retrievedContentCacheKey}:flight`, snippets, RETRIEVED_CONTENT_CACHE_TTL_SECONDS);
  }

  const workingMemory = { userQuery: plan.rewrittenPrompt, preferenceContext: plan.preferenceContext ?? undefined, filters };
  const retrievedPassages = snippets.map((s, i) => `[${i + 1}] ${(s.title ? s.title + ': ' : '')}${s.text.replace(/\s+/g, ' ').slice(0, 400)}`).join('\n');
  const userContent = `
Working memory (conversation context — for intent and preferences only; do not cite as factual source):
${JSON.stringify(workingMemory)}

Retrieved content (use only these for factual claims; cite as [1], [2], ...):
${retrievedPassages}

Flight list (from retrieved content): ${JSON.stringify(flights.slice(0, 15).map((f) => ({ carrier: f.carrier, flightNumber: f.flightNumber, departTime: f.departTime })))}
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
    flights,
    citations,
    retrievalStats: {
      vertical: 'flight',
      itemCount: flights.length,
      maxItems: deps.retriever.getMaxItems?.(),
      avgScore,
      topKAvg,
    },
  };
}

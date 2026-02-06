// Hybrid retriever: BM25 + dense scoring, optional LLM rerank and dedup.
import { FlightFilters } from '@/types/verticals';
import { Flight, FlightProvider } from '@/services/providers/flights/flight-provider';
import { FlightRetriever } from '@/services/providers/flights/flight-retriever';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';
import type { Embedder } from '@/services/providers/retrieval-vector-utils';
import { tokenize, bm25LikeScore, cosineSimilarity } from '@/services/providers/retrieval-vector-utils';
import { rerankWithLLm } from '@/services/rerank';
import { dedupByKey, buildDedupKey, type ScoredItem } from '@/services/dedup-utils';
import { logger } from '@/services/logger';

export interface FlightHybridRetrieverOptions {
  bm25Weight?: number;
  denseWeight?: number;
  maxItems?: number;
  useRerank?: boolean;
}

function flightToText(f: Flight): string {
  return [f.carrier, f.flightNumber, f.origin, f.destination, f.cabin].filter(Boolean).join(' ');
}

export class HybridFlightRetriever implements FlightRetriever {
  constructor(
    private readonly provider: FlightProvider,
    private readonly embedder: Embedder,
    private readonly options: FlightHybridRetrieverOptions = {},
  ) {
    this.options = { bm25Weight: 0.6, denseWeight: 0.4, maxItems: 20, useRerank: true, ...options };
  }

  getMaxItems?(): number {
    return this.options.maxItems ?? 20;
  }

  async searchFlights(
    filters: FlightFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ flights: Flight[]; snippets: RetrievedSnippet[] }> {
    const { rewrittenQuery } = filters;
    const maxItems = this.options.maxItems ?? 20;
    const flights = await this.provider.searchFlights(filters);
    if (!flights.length) return { flights: [], snippets: [] };

    const queryTokens = tokenize(rewrittenQuery);
    const docs = flights.map((f) => flightToText(f));
    const docTokens = docs.map((d) => tokenize(d));
    const avgDocLength = docTokens.reduce((s, t) => s + t.length, 0) / Math.max(docTokens.length, 1);
    const queryEmbedding = await this.embedder.embed(rewrittenQuery);
    const docEmbeddings = await Promise.all(docs.map((d) => this.embedder.embed(d)));

    const scored: ScoredItem<Flight>[] = flights.map((f, i) => {
      const bm25 = bm25LikeScore(queryTokens, docTokens[i], avgDocLength);
      const dense = cosineSimilarity(queryEmbedding, docEmbeddings[i]);
      const combined = (this.options.bm25Weight ?? 0.6) * Math.min(1, bm25 / 10) + (this.options.denseWeight ?? 0.4) * Math.max(0, dense);
      return { item: f, score: combined };
    });
    scored.sort((a, b) => b.score - a.score);
    let top = scored.slice(0, Math.min(maxItems * 2, scored.length));

    if (this.options.useRerank && top.length > 0) {
      try {
        const reranked = await rerankWithLLm({ query: rewrittenQuery, items: top.map((s) => s.item), toText: flightToText, maxItems });
        top = reranked.map((r) => ({ item: r.item, score: r.score }));
      } catch (e) {
        logger.warn('flight hybrid rerank failed', { err: String(e) });
      }
    }
    const getKey = (f: Flight) => buildDedupKey(f, { nameFields: ['id', 'flightNumber'], locationFields: ['origin', 'destination'] });
    const deduped = dedupByKey(top, getKey);
    const final = deduped.slice(0, maxItems);
    const snippets: RetrievedSnippet[] = final.map((s, i) => ({
      id: s.item.id || `flight-${i}`,
      title: `${s.item.carrier} ${s.item.flightNumber}`,
      url: s.item.bookingUrl || '',
      text: `${s.item.origin} to ${s.item.destination} ${s.item.cabin}`.trim(),
      score: s.score ?? 0,
    }));
    return { flights: final.map((s) => s.item), snippets };
  }
}

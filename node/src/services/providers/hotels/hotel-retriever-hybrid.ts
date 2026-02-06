// Hybrid retriever: BM25-like + dense (embedding) scoring, then optional LLM rerank and dedup.
import { HotelFilters } from '@/types/verticals';
import { Hotel, HotelProvider } from '@/services/providers/hotels/hotel-provider';
import { HotelRetriever } from '@/services/providers/hotels/hotel-retriever';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';
import type { Embedder } from '@/services/providers/retrieval-vector-utils';
import { tokenize, bm25LikeScore, cosineSimilarity } from '@/services/providers/retrieval-vector-utils';
import { rerankWithLLm } from '@/services/rerank';
import { dedupByKey, buildDedupKey, type ScoredItem } from '@/services/dedup-utils';
import { logger } from '@/services/logger';

export interface HotelHybridRetrieverOptions {
  bm25Weight?: number;
  denseWeight?: number;
  maxItems?: number;
  useRerank?: boolean;
}

function hotelToText(h: Hotel): string {
  return [h.name, h.location, h.thumbnailUrl].filter(Boolean).join(' ');
}

export class HybridHotelRetriever implements HotelRetriever {
  constructor(
    private readonly provider: HotelProvider,
    private readonly embedder: Embedder,
    private readonly options: HotelHybridRetrieverOptions = {},
  ) {
    this.options = {
      bm25Weight: 0.6,
      denseWeight: 0.4,
      maxItems: 20,
      useRerank: true,
      ...options,
    };
  }

  getMaxItems?(): number {
    return this.options.maxItems ?? 20;
  }

  async searchHotels(
    filters: HotelFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ hotels: Hotel[]; snippets: RetrievedSnippet[] }> {
    const { rewrittenQuery } = filters;
    const maxItems = this.options.maxItems ?? 20;

    const hotels = await this.provider.searchHotels(filters);
    if (!hotels.length) {
      return { hotels: [], snippets: [] };
    }

    const queryTokens = tokenize(rewrittenQuery);
    const docs = hotels.map((h) => hotelToText(h));
    const docTokens = docs.map((d) => tokenize(d));
    const avgDocLength =
      docTokens.reduce((s, t) => s + t.length, 0) / Math.max(docTokens.length, 1);

    const queryEmbedding = await this.embedder.embed(rewrittenQuery);
    const docEmbeddings = await Promise.all(docs.map((d) => this.embedder.embed(d)));

    const scored: ScoredItem<Hotel>[] = hotels.map((h, i) => {
      const bm25 = bm25LikeScore(queryTokens, docTokens[i], avgDocLength);
      const dense = cosineSimilarity(queryEmbedding, docEmbeddings[i]);
      const bm25Norm = Math.min(1, bm25 / 10);
      const combined =
        (this.options.bm25Weight ?? 0.6) * bm25Norm +
        (this.options.denseWeight ?? 0.4) * Math.max(0, dense);
      return { item: h, score: combined };
    });

    scored.sort((a, b) => b.score - a.score);
    let top = scored.slice(0, Math.min(maxItems * 2, scored.length));

    if (this.options.useRerank && top.length > 0) {
      try {
        const reranked = await rerankWithLLm({
          query: rewrittenQuery,
          items: top.map((s) => s.item),
          toText: hotelToText,
          maxItems: maxItems,
        });
        top = reranked.map((r) => ({ item: r.item, score: r.score }));
      } catch (e) {
        logger.warn('hotel hybrid rerank failed', { err: String(e) });
      }
    }

    const deduped = dedupByKey(top, (h) =>
      buildDedupKey(h, { nameFields: ['name'], locationFields: ['location'] }),
    );
    const final = deduped.slice(0, maxItems);

    const snippets: RetrievedSnippet[] = final.map((s, i) => ({
      id: s.item.id || `hotel-${i}`,
      title: s.item.name,
      url: s.item.bookingUrl || '',
      text: `${s.item.name} – ${s.item.location}`.trim(),
      score: s.score ?? 0,
    }));

    return {
      hotels: final.map((s) => s.item),
      snippets,
    };
  }
}

// Hybrid retriever: BM25-like + dense scoring, then optional LLM rerank and dedup.
import { MovieTicketFilters } from '@/types/verticals';
import { MovieShowtime, MovieProvider } from '@/services/providers/movies/movie-provider';
import { MovieRetriever } from '@/services/providers/movies/movie-retriever';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';
import type { Embedder } from '@/services/providers/retrieval-vector-utils';
import { tokenize, bm25LikeScore, cosineSimilarity } from '@/services/providers/retrieval-vector-utils';
import { rerankWithLLm } from '@/services/rerank';
import { dedupByKey, buildDedupKey, type ScoredItem } from '@/services/dedup-utils';
import { logger } from '@/services/logger';

export interface MovieHybridRetrieverOptions {
  bm25Weight?: number;
  denseWeight?: number;
  maxItems?: number;
  useRerank?: boolean;
}

function showtimeToText(m: MovieShowtime): string {
  return [m.movieTitle, m.cinemaName, m.city, m.format].filter(Boolean).join(' ');
}

export class HybridMovieRetriever implements MovieRetriever {
  constructor(
    private readonly provider: MovieProvider,
    private readonly embedder: Embedder,
    private readonly options: MovieHybridRetrieverOptions = {},
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

  async searchShowtimes(
    filters: MovieTicketFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ showtimes: MovieShowtime[]; snippets: RetrievedSnippet[] }> {
    const { rewrittenQuery } = filters;
    const maxItems = this.options.maxItems ?? 20;

    const showtimes = await this.provider.searchShowtimes(filters);
    if (!showtimes.length) {
      return { showtimes: [], snippets: [] };
    }

    const queryTokens = tokenize(rewrittenQuery);
    const docs = showtimes.map((m) => showtimeToText(m));
    const docTokens = docs.map((d) => tokenize(d));
    const avgDocLength =
      docTokens.reduce((s, t) => s + t.length, 0) / Math.max(docTokens.length, 1);

    const queryEmbedding = await this.embedder.embed(rewrittenQuery);
    const docEmbeddings = await Promise.all(docs.map((d) => this.embedder.embed(d)));

    const scored: ScoredItem<MovieShowtime>[] = showtimes.map((m, i) => {
      const bm25 = bm25LikeScore(queryTokens, docTokens[i], avgDocLength);
      const dense = cosineSimilarity(queryEmbedding, docEmbeddings[i]);
      const bm25Norm = Math.min(1, bm25 / 10);
      const combined =
        (this.options.bm25Weight ?? 0.6) * bm25Norm +
        (this.options.denseWeight ?? 0.4) * Math.max(0, dense);
      return { item: m, score: combined };
    });

    scored.sort((a, b) => b.score - a.score);
    let top = scored.slice(0, Math.min(maxItems * 2, scored.length));

    if (this.options.useRerank && top.length > 0) {
      try {
        const reranked = await rerankWithLLm({
          query: rewrittenQuery,
          items: top.map((s) => s.item),
          toText: showtimeToText,
          maxItems: maxItems,
        });
        top = reranked.map((r) => ({ item: r.item, score: r.score }));
      } catch (e) {
        logger.warn('movie hybrid rerank failed', { err: String(e) });
      }
    }

    const deduped = dedupByKey(top, (m) =>
      buildDedupKey(m, { nameFields: ['id', 'movieTitle', 'cinemaName'], locationFields: ['city'] }),
    );
    const final = deduped.slice(0, maxItems);

    const snippets: RetrievedSnippet[] = final.map((s, i) => ({
      id: s.item.id || `movie-${i}`,
      title: s.item.movieTitle,
      url: s.item.bookingUrl || '',
      text: `${s.item.movieTitle} at ${s.item.cinemaName}, ${s.item.city}`.trim(),
      score: s.score ?? 0,
    }));

    return {
      showtimes: final.map((s) => s.item),
      snippets,
    };
  }
}

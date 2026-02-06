// Hybrid retriever: BM25 + dense scoring, optional LLM rerank and dedup.
import { ProductFilters } from '@/types/verticals';
import { Product, CatalogProvider } from '@/services/providers/catalog/catalog-provider';
import { ProductRetriever } from '@/services/providers/catalog/product-retriever';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';
import type { Embedder } from '@/services/providers/retrieval-vector-utils';
import { tokenize, bm25LikeScore, cosineSimilarity } from '@/services/providers/retrieval-vector-utils';
import { rerankWithLLm } from '@/services/rerank';
import { dedupByKey, buildDedupKey, type ScoredItem } from '@/services/dedup-utils';
import { logger } from '@/services/logger';

export interface ProductHybridRetrieverOptions {
  bm25Weight?: number;
  denseWeight?: number;
  maxItems?: number;
  useRerank?: boolean;
}

function productToText(p: Product): string {
  return [p.title, p.description, p.merchantName].filter(Boolean).join(' ');
}

export class HybridProductRetriever implements ProductRetriever {
  constructor(
    private readonly provider: CatalogProvider,
    private readonly embedder: Embedder,
    private readonly options: ProductHybridRetrieverOptions = {},
  ) {
    this.options = { bm25Weight: 0.6, denseWeight: 0.4, maxItems: 20, useRerank: true, ...options };
  }

  getMaxItems?(): number {
    return this.options.maxItems ?? 20;
  }

  async searchProducts(
    filters: ProductFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ products: Product[]; snippets: RetrievedSnippet[] }> {
    const { rewrittenQuery } = filters;
    const maxItems = this.options.maxItems ?? 20;
    const products = await this.provider.searchProducts(filters);
    if (!products.length) return { products: [], snippets: [] };

    const queryTokens = tokenize(rewrittenQuery);
    const docs = products.map((p) => productToText(p));
    const docTokens = docs.map((d) => tokenize(d));
    const avgDocLength = docTokens.reduce((s, t) => s + t.length, 0) / Math.max(docTokens.length, 1);
    const queryEmbedding = await this.embedder.embed(rewrittenQuery);
    const docEmbeddings = await Promise.all(docs.map((d) => this.embedder.embed(d)));

    const scored: ScoredItem<Product>[] = products.map((p, i) => {
      const bm25 = bm25LikeScore(queryTokens, docTokens[i], avgDocLength);
      const dense = cosineSimilarity(queryEmbedding, docEmbeddings[i]);
      const combined = (this.options.bm25Weight ?? 0.6) * Math.min(1, bm25 / 10) + (this.options.denseWeight ?? 0.4) * Math.max(0, dense);
      return { item: p, score: combined };
    });
    scored.sort((a, b) => b.score - a.score);
    let top = scored.slice(0, Math.min(maxItems * 2, scored.length));

    if (this.options.useRerank && top.length > 0) {
      try {
        const reranked = await rerankWithLLm({ query: rewrittenQuery, items: top.map((s) => s.item), toText: productToText, maxItems });
        top = reranked.map((r) => ({ item: r.item, score: r.score }));
      } catch (e) {
        logger.warn('product hybrid rerank failed', { err: String(e) });
      }
    }
    const deduped = dedupByKey(top, (p) => buildDedupKey(p, { nameFields: ['title', 'id'] }));
    const final = deduped.slice(0, maxItems);
    const snippets: RetrievedSnippet[] = final.map((s, i) => ({
      id: s.item.id || `product-${i}`,
      title: s.item.title,
      url: s.item.productUrl || '',
      text: (s.item.description || s.item.title).slice(0, 300),
      score: s.score ?? 0,
    }));
    return { products: final.map((s) => s.item), snippets };
  }
}

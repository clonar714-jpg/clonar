// src/services/vertical/product-agent.ts — product vertical + prompt A/B (Phase 5)
import { VerticalPlan } from '@/types/verticals';
import { Product } from '@/services/providers/catalog/catalog-provider';
import { ProductRetriever } from '@/services/providers/catalog/product-retriever';
import { callMainLLMForSummary } from '@/services/llm-main';
import { setCache } from '@/services/cache';
import { buildSummaryPrompt, type SummaryPromptVariant } from '@/services/prompt-templates';
import { logger } from '@/services/logger';
import type { Citation } from '@/services/orchestrator';
import { searchReformulationPerPart } from '@/services/query-understanding';

const RETRIEVED_CONTENT_CACHE_TTL_SECONDS = 60;

type ProductPlan = Extract<VerticalPlan, { vertical: 'product' }>;

export interface ProductAgentResult {
  summary: string;
  products: Product[];
  citations?: Citation[];
  retrievalStats?: { vertical: 'product'; itemCount: number; maxItems?: number; avgScore?: number; topKAvg?: number };
}

/** 90% A, 10% B for prompt A/B testing. */
function chooseSummaryVariant(): SummaryPromptVariant {
  return Math.random() < 0.1 ? 'B' : 'A';
}

function productKey(p: { id?: string; title?: string }): string {
  if (p.id) return String(p.id);
  return (p.title ?? '').trim();
}

/**
 * Fallback when LLM reformulation returns empty: rule-based queries from plan.
 */
function getSearchQueriesFallback(plan: ProductPlan): string[] {
  const main = plan.rewrittenPrompt.trim();
  const q = plan.product?.query?.trim();
  if (q && q !== main) return [main, q];
  return [main];
}

export async function runProductAgent(
  plan: ProductPlan,
  deps: { retriever: ProductRetriever; retrievedContentCacheKey?: string },
): Promise<ProductAgentResult> {
  const filters = plan.product;
  const text = plan.decomposedContext?.product ?? plan.rewrittenPrompt;
  const llmQueries = await searchReformulationPerPart(text, 'product');
  let queriesToRun = llmQueries.length > 0 ? llmQueries : getSearchQueriesFallback(plan);
  // Perplexity-aligned: when decomposed slice has multiple segments, add each as a retrieval variant for broader recall.
  const slice = plan.decomposedContext?.product;
  if (slice?.includes(';')) {
    const segments = slice.split(';').map((s) => s.trim()).filter(Boolean).slice(0, 3);
    for (const seg of segments) {
      if (seg && !queriesToRun.some((q) => q.trim().toLowerCase() === seg.toLowerCase())) {
        queriesToRun = [...queriesToRun, seg];
      }
    }
  }
  // Perplexity-aligned: feed entity/landmark signals into at least one retrieval variant (e.g. brand + query) for better recall.
  const entities = plan.entities?.entities ?? [];
  const locations = plan.entities?.locations ?? [];
  const anchors = [...entities, ...locations].filter(Boolean).slice(0, 2);
  for (const anchor of anchors) {
    const variant = `${text} ${anchor}`.trim();
    if (variant && !queriesToRun.some((q) => q.toLowerCase().includes(anchor.toLowerCase()))) {
      queriesToRun = [...queriesToRun, variant];
    }
  }

  const allProducts: Product[] = [];
  const allSnippets: Array<{ id: string; url: string; title?: string; text: string; score?: number }> = [];
  const seenProductKeys = new Set<string>();

  for (const query of queriesToRun) {
    const { products, snippets } = await deps.retriever.searchProducts({
      ...filters,
      query: query,
      rewrittenQuery: query,
      ...(plan.preferenceContext != null && { preferenceContext: plan.preferenceContext }),
    });
    for (const p of products) {
      const key = productKey(p);
      if (!seenProductKeys.has(key)) {
        seenProductKeys.add(key);
        allProducts.push(p);
      }
    }
    for (const s of snippets) {
      allSnippets.push({ id: s.id, url: s.url, title: s.title, text: s.text, score: s.score });
    }
  }

  const products = allProducts;
  const snippets = allSnippets;

  if (deps.retrievedContentCacheKey) {
    await setCache(`retrieved:${deps.retrievedContentCacheKey}:product`, snippets, RETRIEVED_CONTENT_CACHE_TTL_SECONDS);
  }

  const variant = chooseSummaryVariant();
  const prompt = buildSummaryPrompt(variant, {
    userQuery: plan.rewrittenPrompt,
    items: products,
    snippets: snippets.map((s) => ({ snippet: (s as { text: string }).text, text: (s as { text: string }).text })),
    ...(plan.preferenceContext != null && { preferenceContext: plan.preferenceContext }),
  });

  const mode = (deps as { mode?: 'quick' | 'deep' }).mode ?? 'quick';
  const summary = await callMainLLMForSummary(prompt, mode);

  logger.info('summary_prompt:used', {
    vertical: 'product',
    variant,
  });

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
    products,
    citations,
    retrievalStats: {
      vertical: 'product',
      itemCount: products.length,
      maxItems: deps.retriever.getMaxItems?.(),
      avgScore,
      topKAvg,
    },
  };
}

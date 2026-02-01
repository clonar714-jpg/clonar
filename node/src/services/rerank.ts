// node/src/services/rerank.ts

import { callSmallLlmJson } from './llm-small';

export interface RerankRequest<T> {
  query: string;
  items: T[];
  toText: (item: T) => string;
  maxItems?: number;
}

/**
 * Simple LLM-small reranker on top of hybrid scores.
 */
export async function rerankWithLLm<T>(
  req: RerankRequest<T>,
): Promise<{ item: T; score: number }[]> {
  const { query, items, toText, maxItems = 15 } = req;
  if (!items.length) return [];

  const payload = items.map((it, idx) => ({
    id: idx,
    text: toText(it),
  }));

  const prompt = `
You are reranking hotel search results.

User query: "${query}"

For each item, assign a relevance score between 0 and 1.
Consider semantic match and how well the hotel fits the query (location, price range if mentioned, etc.).

Return JSON only in the format:
[
  { "id": number, "score": number },
  ...
]
`;

  const llmInput = {
    system: 'You are a ranking model that outputs compact JSON only.',
    user: `${prompt}\n\nItems:\n${JSON.stringify(payload, null, 2)}`,
  };

  const raw = await callSmallLlmJson(llmInput);

  let parsed: { id: number; score: number }[] = [];
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = payload.map((p) => ({ id: p.id, score: 0.5 }));
  }

  const byId = new Map<number, number>();
  for (const r of parsed) {
    if (typeof r.id === 'number' && typeof r.score === 'number') {
      const s = Math.max(0, Math.min(1, r.score));
      byId.set(r.id, s);
    }
  }

  const scored = items.map((it, idx) => ({
    item: it,
    score: byId.get(idx) ?? 0,
  }));

  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, maxItems);
}

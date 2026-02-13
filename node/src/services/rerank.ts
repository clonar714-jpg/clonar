// node/src/services/rerank.ts

import { callSmallLlmJson } from './llm-small';

export interface RerankRequest<T> {
  query: string;
  items: T[];
  toText: (item: T) => string;
  maxItems?: number;
  /**
   * Subjective/fuzzy preference criteria (e.g. "good workspace", "close to restaurants").
   * When provided, score each item by how well it satisfies these preferences in addition to query relevance.
   */
  preferenceCriteria?: string;
}

/**
 * Simple LLM-small reranker on top of hybrid scores.
 * When preferenceCriteria is set, the LLM explicitly scores how well each item satisfies those fuzzy preferences.
 */
export async function rerankWithLLm<T>(
  req: RerankRequest<T>,
): Promise<{ item: T; score: number }[]> {
  const { query, items, toText, maxItems = 15, preferenceCriteria } = req;
  if (!items.length) return [];

  const payload = items.map((it, idx) => ({
    id: idx,
    text: toText(it),
  }));

  const preferenceBlock = preferenceCriteria?.trim()
    ? `
User preference criteria: ${preferenceCriteria}

Only score an item higher for a preference if the item's text (description, amenities, reviews) contains evidence supporting it. Do NOT assume or infer satisfaction. If there is no evidence for a preference, assign neutral (not negative) weight.`
    : '';

  const prompt = `
You are reranking search results.

User query: "${query}"${preferenceBlock}

For each item, assign a relevance score between 0 and 1.
Consider semantic match to the query and how well the item fits any stated preferences (location, price, style, amenities, proximity to places, etc.).

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

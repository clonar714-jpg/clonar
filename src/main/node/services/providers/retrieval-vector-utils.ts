// node/src/services/providers/retrieval-vector-utils.ts — shared BM25-like + vector helpers for hybrid retrieval

export type Embedding = number[];

export interface Embedder {
  embed(text: string): Promise<Embedding>;
}

export function cosineSimilarity(a: Embedding, b: Embedding): number {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/g)
    .filter(Boolean);
}

/** Very simple BM25-like scorer (not full BM25, but close enough for mock data). */
export function bm25LikeScore(
  queryTokens: string[],
  docTokens: string[],
  avgDocLength: number,
  k1 = 1.5,
  b = 0.75,
): number {
  if (docTokens.length === 0 || queryTokens.length === 0) return 0;

  const docLength = docTokens.length;
  const termFreq: Record<string, number> = {};
  for (const t of docTokens) {
    termFreq[t] = (termFreq[t] ?? 0) + 1;
  }

  let score = 0;
  const uniqueQueryTokens = Array.from(new Set(queryTokens));
  for (const qt of uniqueQueryTokens) {
    const tf = termFreq[qt] ?? 0;
    if (tf === 0) continue;

    const idf = 1.5;
    const numerator = tf * (k1 + 1);
    const denominator =
      tf + k1 * (1 - b + (b * docLength) / Math.max(avgDocLength, 1));

    score += idf * (numerator / denominator);
  }

  return score;
}

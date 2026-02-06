// src/services/eval-retrieval.ts
// Standard retrieval metrics: MRR, Recall@K, NDCG@K (MS MARCO / BEIR style).
// Use with a dataset of { queryId, relevantIds, retrieved } per sample.

export interface RetrievalEvalSample {
  /** Optional identifier for the query. */
  queryId?: string;
  /** Optional query text (for logging). */
  query?: string;
  /** Ground-truth relevant document IDs (order doesn't matter for MRR/Recall; matters for NDCG if you have relevance grades). */
  relevantIds: string[];
  /** Retrieved list in rank order (top first). */
  retrieved: { id: string; score?: number }[];
}

/** Mean Reciprocal Rank: 1/rank of first relevant doc, averaged over samples. */
export function computeMRR(relevantIds: Set<string>, retrieved: { id: string }[]): number {
  for (let i = 0; i < retrieved.length; i++) {
    if (relevantIds.has(retrieved[i].id)) return 1 / (i + 1);
  }
  return 0;
}

/** Recall@K: fraction of relevant docs found in top K. */
export function computeRecallAtK(relevantIds: Set<string>, retrieved: { id: string }[], k: number): number {
  if (relevantIds.size === 0) return 0;
  const topK = retrieved.slice(0, k);
  let hit = 0;
  for (const r of topK) {
    if (relevantIds.has(r.id)) hit++;
  }
  return hit / relevantIds.size;
}

/** NDCG@K: normalized DCG at K. Assumes binary relevance (1 if in relevantIds, 0 else). */
export function computeNDCGAtK(relevantIds: Set<string>, retrieved: { id: string }[], k: number): number {
  const topK = retrieved.slice(0, k);
  let dcg = 0;
  for (let i = 0; i < topK.length; i++) {
    const rel = relevantIds.has(topK[i].id) ? 1 : 0;
    dcg += rel / Math.log2(i + 2);
  }
  const idealRelevant = Math.min(relevantIds.size, k);
  let idcg = 0;
  for (let i = 0; i < idealRelevant; i++) {
    idcg += 1 / Math.log2(i + 2);
  }
  if (idcg === 0) return 0;
  return dcg / idcg;
}

export interface RetrievalEvalResult {
  mrr: number;
  recallAtK: number;
  ndcgAtK: number;
  sampleCount: number;
  k: number;
}

const DEFAULT_K = 10;

/** Run retrieval eval over samples; returns averaged MRR, Recall@K, NDCG@K. */
export function runRetrievalEval(
  samples: RetrievalEvalSample[],
  options?: { k?: number },
): RetrievalEvalResult {
  const k = options?.k ?? DEFAULT_K;
  if (samples.length === 0) {
    return { mrr: 0, recallAtK: 0, ndcgAtK: 0, sampleCount: 0, k };
  }
  let sumMrr = 0;
  let sumRecall = 0;
  let sumNdcg = 0;
  for (const s of samples) {
    const relSet = new Set(s.relevantIds);
    sumMrr += computeMRR(relSet, s.retrieved);
    sumRecall += computeRecallAtK(relSet, s.retrieved, k);
    sumNdcg += computeNDCGAtK(relSet, s.retrieved, k);
  }
  const n = samples.length;
  return {
    mrr: sumMrr / n,
    recallAtK: sumRecall / n,
    ndcgAtK: sumNdcg / n,
    sampleCount: n,
    k,
  };
}

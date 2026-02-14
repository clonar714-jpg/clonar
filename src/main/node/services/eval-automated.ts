
import { tokenize } from './providers/retrieval-vector-utils';


export function scoreRewriteQuality(original: string, rewritten: string): number {
  if (!original.trim()) return rewritten.trim() ? 0.5 : 0;
  const origTokens = new Set(tokenize(original.toLowerCase()));
  const rewrTokens = new Set(tokenize(rewritten.toLowerCase()));
  let overlap = 0;
  for (const t of rewrTokens) {
    if (origTokens.has(t)) overlap++;
  }
  const jaccard = origTokens.size + rewrTokens.size - overlap === 0 ? 0 : overlap / (origTokens.size + rewrTokens.size - overlap);
  const lenRatio = rewritten.length / (original.length || 1);
  const lengthOk = lenRatio >= 0.5 && lenRatio <= 3 ? 1 : lenRatio < 0.5 ? 0.5 : 0.8;
  return jaccard * 0.7 + lengthOk * 0.3;
}


export function scoreFilterAppropriateness(query: string, filters: Record<string, unknown>): number {
  const q = query.toLowerCase();
  const flat = JSON.stringify(filters).toLowerCase();
  const filterTerms = flat.replace(/[^a-z0-9\s]/g, ' ').split(/\s+/).filter((s) => s.length > 2);
  if (filterTerms.length === 0) return 1;
  let match = 0;
  for (const t of filterTerms) {
    if (t.length < 4) continue;
    if (q.includes(t) || q.includes(t.slice(0, 4))) match++;
  }
  return filterTerms.length > 0 ? match / Math.min(filterTerms.length, 10) : 1;
}


export function scoreRoutingCorrectness(
  primaryRoute: string | null,
  sourcesUsed: string[],
  retrievalCounts: { hotel?: number; flight?: number; product?: number; movie?: number },
): number {
  const counts = [
    { v: 'hotel', n: retrievalCounts.hotel ?? 0 },
    { v: 'flight', n: retrievalCounts.flight ?? 0 },
    { v: 'product', n: retrievalCounts.product ?? 0 },
    { v: 'movie', n: retrievalCounts.movie ?? 0 },
  ].filter((x) => x.n > 0);
  if (counts.length === 0) return primaryRoute === 'other' || primaryRoute == null ? 1 : 0.5;
  const best = counts.reduce((a, b) => (a.n >= b.n ? a : b));
  if (primaryRoute === best.v) return 1;
  if (sourcesUsed?.includes(primaryRoute ?? '')) return 0.7;
  return 0.5;
}

export interface AutomatedEvalScores {
  rewriteQuality: number;
  filterAppropriateness: number;
  routingCorrectness: number;
}


export function runAutomatedEvals(params: {
  originalQuery: string;
  rewrittenQuery: string;
  extractedFilters?: Record<string, unknown>;
  primaryRoute?: string | null;
  sourcesUsed?: string[];
  retrievalCounts?: { hotel?: number; flight?: number; product?: number; movie?: number };
}): AutomatedEvalScores {
  const rewriteQuality = scoreRewriteQuality(params.originalQuery, params.rewrittenQuery);
  const filterAppropriateness = params.extractedFilters
    ? scoreFilterAppropriateness(params.rewrittenQuery, params.extractedFilters)
    : 1;
  const routingCorrectness = scoreRoutingCorrectness(
    params.primaryRoute ?? null,
    params.sourcesUsed ?? [],
    params.retrievalCounts ?? {},
  );
  return { rewriteQuality, filterAppropriateness, routingCorrectness };
}

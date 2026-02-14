import { logger } from '@/utils/logger';
import { tokenize } from './providers/retrieval-vector-utils';

export type RetrievalSource = 'hotel' | 'flight' | 'product' | 'movie' | 'web';


export interface RetrievedChunk {
  id: string;
  url: string;
  title?: string;
  text: string;
  score: number;
  source: RetrievalSource;
  
  date?: string;
  
  rawItem?: unknown;
}


export interface PassageReranker {
  rerank(query: string, chunks: RetrievedChunk[]): Promise<RetrievedChunk[]>;
}


export interface RoutingDecision {
  sourcesUsed: RetrievalSource[];
  primary: RetrievalSource | null;
  confidence: number;
  intentBasedNarrowed: boolean;
  rationale?: string;
}


function termVectorCosine(tokensA: string[], tokensB: string[]): number {
  const vecA = new Map<string, number>();
  const vecB = new Map<string, number>();
  for (const t of tokensA) vecA.set(t, (vecA.get(t) ?? 0) + 1);
  for (const t of tokensB) vecB.set(t, (vecB.get(t) ?? 0) + 1);
  let dot = 0, na = 0, nb = 0;
  const allTerms = new Set([...vecA.keys(), ...vecB.keys()]);
  for (const t of allTerms) {
    const a = vecA.get(t) ?? 0, b = vecB.get(t) ?? 0;
    dot += a * b;
    na += a * a;
    nb += b * b;
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}


function normalizeForDedupe(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}


function jaccardTokens(tokensA: string[], tokensB: string[]): number {
  const setA = new Set(tokensA);
  const setB = new Set(tokensB);
  let intersection = 0;
  for (const t of setA) if (setB.has(t)) intersection++;
  const union = setA.size + setB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}


function chunkQuality(c: RetrievedChunk): number {
  const len = (c.text?.length ?? 0) + (c.title?.length ?? 0) * 2;
  const meta = (c.title ? 5 : 0) + (c.date ? 3 : 0);
  return len * 0.01 + (c.score ?? 0) * 10 + meta;
}


export function smartDedupeChunks(chunks: RetrievedChunk[]): { kept: RetrievedChunk[]; droppedCount: number } {
  const byId = new Map<string, RetrievedChunk>();
  for (const c of chunks) {
    const key = c.id || `${c.url}|${c.title ?? ''}`;
    const existing = byId.get(key);
    if (!existing || chunkQuality(c) > chunkQuality(existing)) byId.set(key, c);
  }
  const afterId = Array.from(byId.values());
  const kept: RetrievedChunk[] = [];
  let droppedCount = 0;
  const SIMILARITY_THRESHOLD = 0.85;
  for (const c of afterId) {
    const normText = normalizeForDedupe(c.text);
    const tokensC = tokenize(normText);
    let isDuplicate = false;
    for (const k of kept) {
      const tokensK = tokenize(normalizeForDedupe(k.text));
      if (jaccardTokens(tokensC, tokensK) >= SIMILARITY_THRESHOLD) {
        if (chunkQuality(c) <= chunkQuality(k)) {
          isDuplicate = true;
          droppedCount++;
          break;
        }
        const idx = kept.findIndex((x) => x === k);
        if (idx >= 0) kept.splice(idx, 1);
        droppedCount++;
        break;
      }
    }
    if (!isDuplicate) kept.push(c);
  }
  return { kept, droppedCount };
}


function domainFromUrl(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '') || url.slice(0, 50);
  } catch {
    return url.slice(0, 50);
  }
}

function parseDateToTime(dateStr: string | undefined): number {
  if (!dateStr) return 0;
  const t = Date.parse(dateStr);
  return Number.isNaN(t) ? 0 : t;
}


export function rerankChunks(chunks: RetrievedChunk[], subQueries: string[]): RetrievedChunk[] {
  const queryTokenLists = subQueries.map((q) => tokenize(q));
  const now = Date.now();
  const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  const domainCount = new Map<string, number>();
  for (const c of chunks) {
    const d = domainFromUrl(c.url);
    domainCount.set(d, (domainCount.get(d) ?? 0) + 1);
  }

  const scored = chunks.map((c) => {
    let composite = c.score;

    const chunkTokens = tokenize(c.text + ' ' + (c.title ?? ''));
    let bestSim = 0;
    for (const qt of queryTokenLists) {
      const sim = termVectorCosine(qt, chunkTokens);
      if (sim > bestSim) bestSim = sim;
    }
    composite += bestSim * 0.4;

    if (c.date && c.source === 'web') {
      const t = parseDateToTime(c.date);
      if (t > 0) {
        const ageMs = now - t;
        if (ageMs < ONE_YEAR_MS) composite += 0.1 * (1 - ageMs / ONE_YEAR_MS);
      }
    }

    const count = domainCount.get(domainFromUrl(c.url)) ?? 0;
    if (count > 2) composite -= 0.15 * (count - 2);

    return { chunk: c, composite };
  });

  scored.sort((a, b) => b.composite - a.composite);
  const result = scored.map((s) => s.chunk);
  logger.info('flow:rerank', {
    step: 'rerank',
    inputCount: chunks.length,
    outputCount: result.length,
    subQueriesCount: subQueries.length,
  });
  return result;
}

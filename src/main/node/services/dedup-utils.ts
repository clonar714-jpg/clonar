// node/src/services/dedup-utils.ts

export interface ScoredItem<T> {
  item: T;
  score: number;
}

export interface DedupKeyOptions {
  nameFields: string[];
  locationFields?: string[];
}

function normalizeString(s: string | undefined | null): string {
  if (!s) return '';
  return s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function buildDedupKey(item: any, opts: DedupKeyOptions): string {
  const parts: string[] = [];

  for (const f of opts.nameFields) {
    parts.push(normalizeString(item[f]));
  }

  if (opts.locationFields) {
    for (const f of opts.locationFields) {
      parts.push(normalizeString(item[f]));
    }
  }

  return parts.filter(Boolean).join('|');
}

export function dedupByKey<T>(
  items: ScoredItem<T>[],
  getKey: (item: T) => string,
): ScoredItem<T>[] {
  const bestByKey = new Map<string, ScoredItem<T>>();

  for (const si of items) {
    const key = getKey(si.item);
    const existing = bestByKey.get(key);
    if (!existing || si.score > existing.score) {
      bestByKey.set(key, si);
    }
  }

  return Array.from(bestByKey.values());
}

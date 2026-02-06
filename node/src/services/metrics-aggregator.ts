// src/services/metrics-aggregator.ts
// In-memory aggregation for routing distribution, retrieval quality by route, rewrite rate.
// Push metrics via record(); query via getRoutingDistribution(), getRetrievalQualityByRoute(), getRewriteRate(), getBaseline().
// Optional: wire setMetricsCallback(aggregator.record) from app startup to feed this.
import type { RequestMetrics } from './query-processing-metrics';

const DEFAULT_WINDOW_SIZE = 10_000;
const WINDOW_SIZE_ENV = 'QUERY_METRICS_WINDOW_SIZE';

function getWindowSize(): number {
  const v = process.env[WINDOW_SIZE_ENV];
  if (v == null || v === '') return DEFAULT_WINDOW_SIZE;
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_WINDOW_SIZE;
}

interface WindowedMetrics {
  metrics: RequestMetrics[];
  maxSize: number;
}

const window: WindowedMetrics = {
  metrics: [],
  maxSize: getWindowSize(),
};

/** Record one request's metrics (sliding window; drops oldest when full). */
export function record(metrics: RequestMetrics): void {
  window.metrics.push(metrics);
  if (window.metrics.length > window.maxSize) {
    window.metrics.shift();
  }
}

/** Routing distribution: count and share per primary route (including "other" when no primary). */
export function getRoutingDistribution(): { route: string; count: number; share: number }[] {
  const total = window.metrics.length;
  if (total === 0) return [];
  const byRoute = new Map<string, number>();
  for (const m of window.metrics) {
    const route = m.primaryRoute ?? (m.routingSources?.length ? m.routingSources[0] : 'other') ?? 'other';
    byRoute.set(route, (byRoute.get(route) ?? 0) + 1);
  }
  return Array.from(byRoute.entries())
    .map(([route, count]) => ({ route, count, share: count / total }))
    .sort((a, b) => b.count - a.count);
}

/** Retrieval quality by route: for each primary route, avg retrievalQualityScore and sample count. */
export function getRetrievalQualityByRoute(): { route: string; avgQuality: number; count: number }[] {
  const byRoute = new Map<string, { sum: number; count: number }>();
  for (const m of window.metrics) {
    const route = m.primaryRoute ?? (m.routingSources?.length ? m.routingSources[0] : 'other') ?? 'other';
    const cur = byRoute.get(route) ?? { sum: 0, count: 0 };
    cur.sum += m.retrievalQualityScore ?? 0;
    cur.count += 1;
    byRoute.set(route, cur);
  }
  return Array.from(byRoute.entries()).map(([route, { sum, count }]) => ({
    route,
    avgQuality: count > 0 ? sum / count : 0,
    count,
  }));
}

/** Rewrite rate in the window (share of requests where rewrite was applied). */
export function getRewriteRate(): number {
  const total = window.metrics.length;
  if (total === 0) return 0;
  const applied = window.metrics.filter((m) => m.rewriteApplied).length;
  return applied / total;
}

/** Baseline snapshot: rewrite rate, routing distribution, avg retrieval quality. Used for degradation alerts. */
export interface AggregatorBaseline {
  rewriteRate: number;
  routingDistribution: { route: string; count: number; share: number }[];
  avgRetrievalQuality: number;
  sampleCount: number;
  at: string;
}

export function getBaseline(): AggregatorBaseline | null {
  if (window.metrics.length === 0) return null;
  const total = window.metrics.length;
  const rewriteRate = getRewriteRate();
  const routingDistribution = getRoutingDistribution();
  const sumQuality = window.metrics.reduce((a, m) => a + (m.retrievalQualityScore ?? 0), 0);
  const avgRetrievalQuality = total > 0 ? sumQuality / total : 0;
  return {
    rewriteRate,
    routingDistribution,
    avgRetrievalQuality,
    sampleCount: total,
    at: new Date().toISOString(),
  };
}

/** Optional: record user satisfaction for a request (e.g. from feedback API). Enables satisfaction-by-route. */
const satisfactionByTraceId = new Map<string, { route: string; score: number }>();

export function recordSatisfaction(traceId: string, route: string, score: number): void {
  satisfactionByTraceId.set(traceId, { route, score });
  if (satisfactionByTraceId.size > window.maxSize) {
    const first = satisfactionByTraceId.keys().next().value;
    if (first != null) satisfactionByTraceId.delete(first);
  }
}

/** Average satisfaction by route (only for requests that have been labeled). */
export function getSatisfactionByRoute(): { route: string; avgScore: number; count: number }[] {
  const byRoute = new Map<string, { sum: number; count: number }>();
  for (const { route, score } of satisfactionByTraceId.values()) {
    const cur = byRoute.get(route) ?? { sum: 0, count: 0 };
    cur.sum += score;
    cur.count += 1;
    byRoute.set(route, cur);
  }
  return Array.from(byRoute.entries()).map(([route, { sum, count }]) => ({
    route,
    avgScore: count > 0 ? sum / count : 0,
    count,
  }));
}

/** Current window size (for debugging). */
export function getWindowLength(): number {
  return window.metrics.length;
}

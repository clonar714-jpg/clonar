// src/services/query-processing-metrics.ts
// Component-level metrics per request for online evaluation (rewrite, decompose, route, retrieval).
// Aligns with: "Quality metrics for query processing" — log or push to callback.
import { logger } from './logger';

export interface RequestMetrics {
  /** Whether rewrite was applied (vs. used original). */
  rewriteApplied: boolean;
  /** Number of sub-queries produced by decomposition. */
  decompositionSubQueryCount: number;
  /** Sources used in routing (e.g. ["hotel", "web"]). */
  routingSources: string[];
  /** Primary vertical from intent-based routing when confidence high; for distribution and quality-by-route. */
  primaryRoute?: string;
  /** Routing confidence 0–1; high = single clear intent. */
  routingConfidence?: number;
  /** True when retrieval was narrowed to primary + web due to high confidence. */
  intentBasedNarrowed?: boolean;
  /** Retrieval quality score (e.g. topKAvg or avgScore 0–1). */
  retrievalQualityScore: number;
  /** Whether grounding was skipped (no retrieval). */
  groundingSkipped: boolean;
  /** Total pipeline duration ms. */
  durationMs: number;
}

export type MetricsCallback = (metrics: RequestMetrics) => void;

let globalMetricsCallback: MetricsCallback | null = null;

/** Set a callback to receive metrics for each request (e.g. push to observability). */
export function setMetricsCallback(cb: MetricsCallback | null): void {
  globalMetricsCallback = cb;
}

/** Create a per-request metrics collector. */
export function createRequestMetrics(): {
  recordRewrite: (applied: boolean) => void;
  recordDecomposition: (subQueryCount: number) => void;
  recordRouting: (sources: string[]) => void;
  recordRoutingDecision: (primary: string | null, confidence: number, intentBasedNarrowed: boolean) => void;
  recordRetrievalQuality: (score: number) => void;
  recordGroundingSkipped: (skipped: boolean) => void;
  finish: (startedAt: number) => void;
} {
  const state: Partial<RequestMetrics> = {
    rewriteApplied: false,
    decompositionSubQueryCount: 0,
    routingSources: [],
    retrievalQualityScore: 0,
    groundingSkipped: false,
  };

  return {
    recordRewrite(applied: boolean) {
      state.rewriteApplied = applied;
    },
    recordDecomposition(subQueryCount: number) {
      state.decompositionSubQueryCount = subQueryCount;
    },
    recordRouting(sources: string[]) {
      state.routingSources = sources;
    },
    recordRoutingDecision(primary: string | null, confidence: number, intentBasedNarrowed: boolean) {
      state.primaryRoute = primary ?? undefined;
      state.routingConfidence = confidence;
      state.intentBasedNarrowed = intentBasedNarrowed;
    },
    recordRetrievalQuality(score: number) {
      state.retrievalQualityScore = score;
    },
    recordGroundingSkipped(skipped: boolean) {
      state.groundingSkipped = skipped;
    },
    finish(startedAt: number) {
      const durationMs = Date.now() - startedAt;
      const metrics: RequestMetrics = {
        rewriteApplied: state.rewriteApplied ?? false,
        decompositionSubQueryCount: state.decompositionSubQueryCount ?? 0,
        routingSources: state.routingSources ?? [],
        primaryRoute: state.primaryRoute,
        routingConfidence: state.routingConfidence,
        intentBasedNarrowed: state.intentBasedNarrowed,
        retrievalQualityScore: state.retrievalQualityScore ?? 0,
        groundingSkipped: state.groundingSkipped ?? false,
        durationMs,
      };
      logger.info('query_processing_metrics', metrics);
      if (globalMetricsCallback) {
        try {
          globalMetricsCallback(metrics);
        } catch (err) {
          logger.warn('query_processing_metrics:callback_failed', { err: err instanceof Error ? err.message : String(err) });
        }
      }
    },
  };
}

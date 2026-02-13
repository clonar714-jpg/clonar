
import { logger } from './logger';

export interface RequestMetrics {
 
  rewriteApplied: boolean;
  
  decompositionSubQueryCount: number;
  
  routingSources: string[];
  
  primaryRoute?: string;
  
  routingConfidence?: number;
  
  intentBasedNarrowed?: boolean;
  
  retrievalQualityScore: number;
  
  groundingSkipped: boolean;
 
  durationMs: number;
}

export type MetricsCallback = (metrics: RequestMetrics) => void;

let globalMetricsCallback: MetricsCallback | null = null;


export function setMetricsCallback(cb: MetricsCallback | null): void {
  globalMetricsCallback = cb;
}


export function createRequestMetrics(): {
  recordRewrite: (applied: boolean) => void;
  recordDecomposition: (subQueryCount: number) => void;
  recordRouting: (sources: string[]) => void;
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

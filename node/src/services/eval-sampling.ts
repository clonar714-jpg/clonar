
import { logger } from './logger';
import type { QueryProcessingTrace } from './query-processing-trace';
import { getRoutingDistribution } from './metrics-aggregator';

const SAMPLE_RATE_ENV = 'QUERY_EVAL_SAMPLE_RATE';
const HUMAN_REVIEW_DIR_ENV = 'QUERY_EVAL_HUMAN_REVIEW_DIR';
const LOW_CONFIDENCE_SAMPLE_RATE_ENV = 'QUERY_EVAL_LOW_CONFIDENCE_SAMPLE_RATE';
const LOW_CONFIDENCE_THRESHOLD_ENV = 'QUERY_EVAL_LOW_CONFIDENCE_THRESHOLD';
const STRATIFIED_ENV = 'QUERY_EVAL_STRATIFIED';

function getSampleRate(): number {
  const v = process.env[SAMPLE_RATE_ENV];
  if (v == null || v === '') return 0;
  const n = parseFloat(v);
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0;
}


function getLowConfidenceSampleRate(): number {
  const v = process.env[LOW_CONFIDENCE_SAMPLE_RATE_ENV];
  if (v == null || v === '') return 0.2;
  const n = parseFloat(v);
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0.2;
}


function getLowConfidenceThreshold(): number {
  const v = process.env[LOW_CONFIDENCE_THRESHOLD_ENV];
  if (v == null || v === '') return 0.6;
  const n = parseFloat(v);
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0.6;
}


function isStratifiedEnabled(): boolean {
  return process.env[STRATIFIED_ENV] === '1' || process.env[STRATIFIED_ENV] === 'true';
}

export interface ShouldSampleForEvalOptions {
 
  routingConfidence?: number;
  
  primaryRoute?: string | null;
  
  automatedEvalScores?: { rewriteQuality: number; filterAppropriateness: number; routingCorrectness: number };
}


export function shouldSampleForEval(options?: ShouldSampleForEvalOptions): boolean {
  let rate = getSampleRate();
  if (rate <= 0) return false;
  if (rate >= 1) return true;

  
  if (options?.routingConfidence != null) {
    const threshold = getLowConfidenceThreshold();
    if (options.routingConfidence < threshold) {
      rate = getLowConfidenceSampleRate();
    }
  }

 
  if (isStratifiedEnabled() && options?.primaryRoute != null) {
    const route = options.primaryRoute || 'other';
    const distribution = getRoutingDistribution();
    const total = distribution.reduce((s, r) => s + r.count, 0);
    if (total > 0) {
      const routeShare = distribution.find((r) => r.route === route)?.share ?? 0;
      const minShare = 0.1;
      if (routeShare < minShare) {
        rate = Math.min(1, rate * (minShare / Math.max(routeShare, 0.01)));
      }
    }
  }

  return Math.random() < rate;
}

export interface HumanReviewPayload {
  traceId: string;
  trace: QueryProcessingTrace;
  originalQuery: string;
  rewrittenQuery: string;
  searchQueries?: string[];
  routing?: unknown;
  summary?: string;
  timestamp: string;
 
  label?: {
    rewritingQuality?: 'good' | 'bad' | 'neutral';
    routingCorrect?: boolean;
    retrievalRelevant?: boolean;
    notes?: string;
  };
}


export function submitForHumanReview(payload: Omit<HumanReviewPayload, 'label' | 'timestamp'>): void {
  const dir = process.env[HUMAN_REVIEW_DIR_ENV];
  const full: HumanReviewPayload = {
    ...payload,
    timestamp: new Date().toISOString(),
  };
  if (dir) {
    try {
      const fs = require('fs');
      const path = require('path');
      const name = `review_${payload.traceId}_${Date.now()}.json`;
      const file = path.join(dir, name);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(file, JSON.stringify(full, null, 2), 'utf8');
      logger.info('eval:submitted_for_review', { traceId: payload.traceId, file });
    } catch (err) {
      logger.warn('eval:submit_for_review_failed', { traceId: payload.traceId, err: err instanceof Error ? err.message : String(err) });
    }
  } else {
    logger.info('eval:sample', { traceId: payload.traceId, originalQuery: payload.originalQuery?.slice(0, 80) });
  }
}

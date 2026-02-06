// src/services/eval-alerting.ts
// Baselines and degradation alerts for query processing metrics.
// Call updateBaseline() after a warm-up period; then checkAlerts() on a timer or after each batch.
import { logger } from './logger';
import {
  getBaseline,
  getRewriteRate,
  getRoutingDistribution,
  getRetrievalQualityByRoute,
  type AggregatorBaseline,
} from './metrics-aggregator';

const REWRITE_RATE_DROP_THRESHOLD = 0.2;
const RETRIEVAL_QUALITY_DROP_THRESHOLD = 0.15;
const ALERT_WEBHOOK_ENV = 'QUERY_EVAL_ALERT_WEBHOOK_URL';

let storedBaseline: AggregatorBaseline | null = null;

/** Capture current window as baseline (call after warm-up). */
export function updateBaseline(): AggregatorBaseline | null {
  storedBaseline = getBaseline();
  if (storedBaseline) {
    logger.info('eval_alerting:baseline_updated', {
      sampleCount: storedBaseline.sampleCount,
      rewriteRate: storedBaseline.rewriteRate,
      avgRetrievalQuality: storedBaseline.avgRetrievalQuality,
    });
  }
  return storedBaseline;
}

/** Get current baseline if set. */
export function getStoredBaseline(): AggregatorBaseline | null {
  return storedBaseline;
}

export interface Alert {
  type: 'rewrite_rate_drop' | 'retrieval_quality_drop' | 'routing_distribution_shift';
  message: string;
  severity: 'warn' | 'error';
  current?: number;
  baseline?: number;
}

/** Compare current window to baseline and return any alerts. */
export function checkAlerts(): Alert[] {
  const baseline = storedBaseline;
  const alerts: Alert[] = [];
  if (!baseline || baseline.sampleCount < 100) return alerts;

  const currentRewriteRate = getRewriteRate();
  if (currentRewriteRate < baseline.rewriteRate - REWRITE_RATE_DROP_THRESHOLD) {
    alerts.push({
      type: 'rewrite_rate_drop',
      message: `Rewrite rate dropped from ${baseline.rewriteRate.toFixed(2)} to ${currentRewriteRate.toFixed(2)}`,
      severity: 'warn',
      current: currentRewriteRate,
      baseline: baseline.rewriteRate,
    });
  }

  const qualityByRoute = getRetrievalQualityByRoute();
  const currentAvgQuality =
    qualityByRoute.length > 0
      ? qualityByRoute.reduce((a, r) => a + r.avgQuality * r.count, 0) /
        qualityByRoute.reduce((a, r) => a + r.count, 0)
      : 0;
  if (currentAvgQuality < baseline.avgRetrievalQuality - RETRIEVAL_QUALITY_DROP_THRESHOLD) {
    alerts.push({
      type: 'retrieval_quality_drop',
      message: `Avg retrieval quality dropped from ${baseline.avgRetrievalQuality.toFixed(2)} to ${currentAvgQuality.toFixed(2)}`,
      severity: 'warn',
      current: currentAvgQuality,
      baseline: baseline.avgRetrievalQuality,
    });
  }

  return alerts;
}

/** Check alerts and log them; optionally POST to webhook if QUERY_EVAL_ALERT_WEBHOOK_URL is set. */
export async function checkAlertsAndNotify(): Promise<Alert[]> {
  const alerts = checkAlerts();
  for (const a of alerts) {
    logger.warn('eval_alerting:alert', { type: a.type, message: a.message, ...a });
  }
  const webhook = process.env[ALERT_WEBHOOK_ENV];
  if (webhook && alerts.length > 0) {
    try {
      await fetch(webhook, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alerts, at: new Date().toISOString() }),
      });
    } catch (err) {
      logger.warn('eval_alerting:webhook_failed', { err: err instanceof Error ? err.message : String(err) });
    }
  }
  return alerts;
}

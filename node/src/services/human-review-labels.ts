// src/services/human-review-labels.ts
// Ingest human review JSON files (with labels), compute accuracy metrics, output report.
// Usage: run from a script or cron that reads QUERY_EVAL_HUMAN_REVIEW_DIR for *labeled* files.
import * as fs from 'fs';
import * as path from 'path';
import type { HumanReviewPayload } from './eval-sampling';

export interface LabelStats {
  total: number;
  withRewritingQuality: number;
  rewritingGood: number;
  rewritingBad: number;
  rewritingNeutral: number;
  withRoutingCorrect: number;
  routingCorrect: number;
  withRetrievalRelevant: number;
  retrievalRelevant: number;
}

export interface HumanReviewReport {
  stats: LabelStats;
  rewritingQualityPct: number;
  routingCorrectPct: number;
  retrievalRelevantPct: number;
  at: string;
}

function emptyStats(): LabelStats {
  return {
    total: 0,
    withRewritingQuality: 0,
    rewritingGood: 0,
    rewritingBad: 0,
    rewritingNeutral: 0,
    withRoutingCorrect: 0,
    routingCorrect: 0,
    withRetrievalRelevant: 0,
    retrievalRelevant: 0,
  };
}

/** Load and parse a single review file. */
function loadReviewFile(filePath: string): HumanReviewPayload | null {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as HumanReviewPayload;
  } catch {
    return null;
  }
}

/** Recursively find review_*.json files under dir that have a .label property. */
function findLabeledReviews(dir: string): string[] {
  const out: string[] = [];
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) return out;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      out.push(...findLabeledReviews(full));
    } else if (e.isFile() && e.name.startsWith('review_') && e.name.endsWith('.json')) {
      try {
        const payload = loadReviewFile(full);
        if (payload?.label) out.push(full);
      } catch {
        // skip
      }
    }
  }
  return out;
}

/** Aggregate stats from labeled review files. */
export function computeLabelStats(reviewDir: string): LabelStats {
  const stats = emptyStats();
  const files = findLabeledReviews(reviewDir);
  for (const f of files) {
    const payload = loadReviewFile(f);
    if (!payload?.label) continue;
    stats.total++;
    const label = payload.label;
    if (label.rewritingQuality != null) {
      stats.withRewritingQuality++;
      if (label.rewritingQuality === 'good') stats.rewritingGood++;
      else if (label.rewritingQuality === 'bad') stats.rewritingBad++;
      else stats.rewritingNeutral++;
    }
    if (typeof label.routingCorrect === 'boolean') {
      stats.withRoutingCorrect++;
      if (label.routingCorrect) stats.routingCorrect++;
    }
    if (typeof label.retrievalRelevant === 'boolean') {
      stats.withRetrievalRelevant++;
      if (label.retrievalRelevant) stats.retrievalRelevant++;
    }
  }
  return stats;
}

/** Build report from stats. */
export function buildReport(stats: LabelStats): HumanReviewReport {
  const rewritingQualityPct =
    stats.withRewritingQuality > 0 ? stats.rewritingGood / stats.withRewritingQuality : 0;
  const routingCorrectPct = stats.withRoutingCorrect > 0 ? stats.routingCorrect / stats.withRoutingCorrect : 0;
  const retrievalRelevantPct =
    stats.withRetrievalRelevant > 0 ? stats.retrievalRelevant / stats.withRetrievalRelevant : 0;
  return {
    stats,
    rewritingQualityPct,
    routingCorrectPct,
    retrievalRelevantPct,
    at: new Date().toISOString(),
  };
}

/** Ingest directory and return report. Optionally write report to path. */
export function ingestHumanReviews(
  reviewDir: string,
  options?: { reportPath?: string },
): HumanReviewReport {
  const stats = computeLabelStats(reviewDir);
  const report = buildReport(stats);
  if (options?.reportPath) {
    fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });
    fs.writeFileSync(options.reportPath, JSON.stringify(report, null, 2), 'utf8');
  }
  return report;
}

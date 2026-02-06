// src/services/grounding-decision.ts
// Perplexity-style: decide whether the query needs external grounding (web/providers)
// before decomposition and retrieval. When false, we skip retrieval and answer with LLM only.
import type { QueryContext } from '@/types/core';
import { callSmallLLM } from './llm-small';
import { safeParseJson } from './query-understanding';
import { logger } from './logger';

export interface GroundingDecision {
  needs_grounding: boolean;
  reason: string;
}

const GROUNDING_USER_TEMPLATE = `You are deciding whether a user's query requires external information retrieval.

Return ONLY valid JSON.

Rules:
- needs_grounding = true if the answer depends on:
  - real-world places, businesses, prices, availability
  - recent events, current data, or factual verification
  - comparison of real entities (hotels, products, flights, movies)
- needs_grounding = false if the query is:
  - conceptual, theoretical, or explanatory
  - general knowledge (definitions, explanations, how things work)
  - advice or reasoning that does not require factual lookup

Query:
<rewrittenQuery>

Return JSON:
{
  "needs_grounding": boolean,
  "reason": string
}`;

/**
 * Decides whether the rewritten query needs external grounding (web/providers).
 * Called AFTER rewrite and BEFORE decomposeIntoSubQueries and any retrieval.
 * Uses a small/cheap LLM (same as callSmallLLM).
 *
 * @returns Strict boolean needs_grounding + reason. On parse failure, defaults to true (safe: continue with retrieval).
 */
/** Timeout for grounding LLM so we never block the pipeline (default: continue with retrieval). */
const GROUNDING_TIMEOUT_MS = 8_000;

export async function shouldUseGroundedRetrieval(
  ctx: QueryContext,
  rewrittenPrompt: string,
): Promise<GroundingDecision> {
  const rewrittenQuery = rewrittenPrompt?.trim() || ctx.message.trim();
  const userPrompt = GROUNDING_USER_TEMPLATE.replace(
    '<rewrittenQuery>',
    rewrittenQuery,
  );

  const run = async (): Promise<GroundingDecision> => {
    try {
      const raw = await callSmallLLM(userPrompt);
      const parsed = safeParseJson(raw, 'grounding-decision');

      const needs_grounding =
        typeof parsed?.needs_grounding === 'boolean'
          ? parsed.needs_grounding
          : true;
      const reason =
        typeof parsed?.reason === 'string' && parsed.reason.trim()
          ? parsed.reason.trim()
          : needs_grounding
            ? 'Default (parse or missing field)'
            : 'No external lookup required';

      if (typeof parsed?.needs_grounding !== 'boolean') {
        logger.warn('grounding-decision:parse_fallback', {
          raw: raw.slice(0, 200),
          defaultNeedsGrounding: true,
        });
      }

      logger.info('grounding-decision:done', {
        needs_grounding,
        reason: reason.slice(0, 120),
      });

      return { needs_grounding, reason };
    } catch (err) {
      logger.warn('grounding-decision:error', {
        err: err instanceof Error ? err.message : String(err),
      });
      return { needs_grounding: true, reason: 'Error, defaulting to retrieval' };
    }
  };

  const timeout = new Promise<GroundingDecision>((resolve) => {
    setTimeout(
      () => {
        logger.warn('grounding-decision:timeout', { ms: GROUNDING_TIMEOUT_MS });
        resolve({ needs_grounding: true, reason: 'Timeout, defaulting to retrieval' });
      },
      GROUNDING_TIMEOUT_MS,
    );
  });

  return Promise.race([run(), timeout]);
}

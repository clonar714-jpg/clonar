/**
 * Perplexity-style UI intent: page shape from INTENT + CONFIDENCE (grounding + planned vertical).
 * No LLMs. Single responsibility: early phase decides PAGE SHAPE; attachUiDecision refines from REAL DATA.
 */
import type { UiIntent, Vertical } from '@/types/core';
import type { GroundingDecision } from './grounding-decision';

/**
 * Compute UI intent from grounding decision and (when available) planned primary vertical.
 * Call after grounding for none/hybrid (planned = 'other' for hybrid); for full, call when plannedPrimaryVertical is available (e.g. after plan/retrieval).
 */
export function computeUiIntent(
  groundingDecision: GroundingDecision,
  plannedPrimaryVertical?: Vertical,
): UiIntent {
  const mode = groundingDecision.grounding_mode;

  if (mode === 'none') {
    return {
      preferredLayout: 'answer-first',
      confidenceExpectation: 'medium',
    };
  }

  if (mode === 'hybrid') {
    return {
      preferredLayout: 'answer-first',
      expectedVertical: 'other',
      confidenceExpectation: 'low',
    };
  }

  // full
  if (plannedPrimaryVertical != null && plannedPrimaryVertical !== 'other') {
    return {
      preferredLayout: 'cards-first',
      expectedVertical: plannedPrimaryVertical,
      confidenceExpectation: 'high',
    };
  }

  return {
    preferredLayout: 'answer-first',
    expectedVertical: plannedPrimaryVertical,
    confidenceExpectation: 'medium',
  };
}

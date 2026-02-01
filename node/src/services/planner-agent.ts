// node/src/services/planner-agent.ts — deep mode: decide if extra research is needed
import { callMainLLMForPlanner } from './llm-main';
import { logger } from './logger';

export type PlannerDecisionType = 'single_pass' | 'extra_research';

export interface PlanDecision {
  type: PlannerDecisionType;
  newQuery?: string;
  confidence: number;
  reasoning?: string;
}

export interface PlannerParams {
  userQuery: string;
  rewrittenQuery: string;
  vertical: string;
  summaryDraft: string;
  mode: 'quick' | 'deep';
}

export async function planResearchStep(
  params: PlannerParams,
): Promise<PlanDecision> {
  const { userQuery, rewrittenQuery, vertical, summaryDraft, mode } = params;

  const prompt = `
You are a research planner for a grounded answer system.

User query: "${userQuery}"
Rewritten query: "${rewrittenQuery}"
Vertical: "${vertical}"
Current summary draft:
"""
${summaryDraft}
"""

Decide whether we should:
- "single_pass": answer is likely sufficient already, or
- "extra_research": we should run one more retrieval + synthesis pass.

Respond in JSON with:
{
  "type": "single_pass" | "extra_research",
  "newQuery": string | null,
  "confidence": number,
  "reasoning": string
}
`;

  const raw = await callMainLLMForPlanner(prompt, mode);

  let parsed: PlanDecision = {
    type: 'single_pass',
    confidence: 0.5,
    reasoning: 'fallback',
  };

  try {
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    const json = raw.slice(jsonStart, jsonEnd + 1);
    const obj = JSON.parse(json);

    parsed = {
      type:
        obj.type === 'extra_research' ? 'extra_research' : 'single_pass',
      newQuery: obj.newQuery ?? undefined,
      confidence: typeof obj.confidence === 'number' ? obj.confidence : 0.5,
      reasoning: obj.reasoning ?? undefined,
    };
  } catch (err) {
    logger.warn('planner:parse_error', {
      raw: raw.slice(0, 200),
      error: err instanceof Error ? err.message : String(err),
    });
  }

  logger.info('planner:decision', {
    type: parsed.type,
    confidence: parsed.confidence,
    hasNewQuery: !!parsed.newQuery,
  });

  return parsed;
}

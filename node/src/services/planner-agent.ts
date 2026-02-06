// src/services/planner-agent.ts — deep mode only: decide if extra research is needed
import { callSmallLLM } from './llm-small';

export type PlanDecision =
  | { type: 'single_pass'; action?: 'single_pass' }
  | { type: 'extra_research'; action?: 'extra_research'; newQuery: string; confidence?: number };

export async function planResearchStep(params: {
  userQuery: string;
  rewrittenQuery: string;
  vertical: string;
  summaryDraft: string;
  mode?: string;
}): Promise<PlanDecision> {
  const prompt = `
You are a planning assistant for a deep research system.
User query: "${params.userQuery}"
Vertical: ${params.vertical}
Rewritten query: "${params.rewrittenQuery}"
Draft answer (may be incomplete):
${params.summaryDraft}

Decide if we need one more research step.
Respond in strict JSON with:
- action: "single_pass" if the draft is already sufficient
- action: "extra_research" and newQuery if we should run one more retrieval with a refined query.
`;

  const raw = await callSmallLLM(prompt);
  try {
    const parsed = JSON.parse(raw);
    if ((parsed.action === 'extra_research' || parsed.type === 'extra_research') && typeof parsed.newQuery === 'string') {
      return { type: 'extra_research', action: 'extra_research', newQuery: parsed.newQuery, confidence: parsed.confidence };
    }
    return { type: 'single_pass', action: 'single_pass' };
  } catch {
    return { type: 'single_pass', action: 'single_pass' };
  }
}

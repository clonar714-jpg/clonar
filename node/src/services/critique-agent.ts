// node/src/services/critique-agent.ts — deep mode: RAG grounding and safety
import { callMainLLMForCritique } from './llm-main';
import { logger } from './logger';

export interface CritiqueResult {
  refinedSummary: string;
  needsReplan?: boolean;
  suggestedQuery?: string;
  /** When allowReplan is true, confidence that replan is needed (0–1). Used to gate replan. */
  confidence?: number;
}

interface CritiqueParams {
  userQuery: string;
  summary: string;
  citations: Array<{ id: string; snippet: string }>;
  /** When true, critic may flag wrong domain and suggest a new query. */
  allowReplan?: boolean;
}

export async function critiqueAndRefineSummary(
  params: CritiqueParams,
): Promise<CritiqueResult> {
  const { userQuery, summary, citations, allowReplan = false } = params;

  const replanBlock = allowReplan
    ? `

If the user's intent clearly fits a DIFFERENT domain (e.g. they asked for hotels but the answer is about flights, or products when they meant movies), set "needsReplan": true and "suggestedQuery" to a short clarifying query (one sentence) that would route correctly. Otherwise set "needsReplan": false and omit "suggestedQuery".
`
    : '';

  // Use 1-based citation numbers [1], [2] so refined answer keeps inline refs
  const prompt = `
You are a strict answer critic for a retrieval-augmented, citation-forward system.

Rules:
- The answer MUST be grounded in the provided citations.
- PRESERVE inline citations [1], [2], etc. in the refined answer; do not remove or renumber them.
- One clear intent per answer (definition, comparison, or how-to); include limits or examples; avoid vague claims.
- If the answer makes a claim that is not supported by citations, soften it or remove it.
- Do NOT add new facts that are not in the citations.
- Prefer concise, well-structured paragraphs and short bullet lists only when necessary.
- If information is missing, say so explicitly.
${replanBlock}

User query:
"${userQuery}"

Current answer:
"""
${summary}
"""

Citations (snippets; numbers [1], [2] must be preserved in your output):
${citations
  .map(
    (c, idx) =>
      `  [${idx + 1}] ${c.snippet.replace(/\s+/g, ' ').slice(0, 300)}`,
  )
  .join('\n')}

${allowReplan ? 'Return JSON: {"refinedSummary": string, "needsReplan": boolean, "suggestedQuery": string | null, "confidence": number}' : 'Return ONLY the improved answer text, no explanations.'}
`;

  const raw = await callMainLLMForCritique(prompt);

  if (allowReplan) {
    try {
      const jsonStart = raw.indexOf('{');
      const jsonEnd = raw.lastIndexOf('}');
      const json = raw.slice(jsonStart, jsonEnd + 1);
      const obj = JSON.parse(json);
      const refinedSummary =
        typeof obj.refinedSummary === 'string' ? obj.refinedSummary : raw.trim();
      const needsReplan = obj.needsReplan === true;
      const suggestedQuery =
        typeof obj.suggestedQuery === 'string' && obj.suggestedQuery.trim()
          ? obj.suggestedQuery.trim()
          : undefined;
      const confidence =
        typeof obj.confidence === 'number' ? obj.confidence : undefined;
      logger.info('critique:done', {
        lengthBefore: summary.length,
        lengthAfter: refinedSummary.length,
        needsReplan,
        confidence,
      });
      return {
        refinedSummary,
        needsReplan: needsReplan || undefined,
        suggestedQuery,
        confidence,
      };
    } catch {
      logger.warn('critique:parse_error, falling back to raw text');
      return { refinedSummary: raw.trim() };
    }
  }

  logger.info('critique:done', {
    lengthBefore: summary.length,
    lengthAfter: raw.length,
  });
  return { refinedSummary: raw.trim() };
}

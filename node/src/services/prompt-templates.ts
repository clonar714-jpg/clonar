// node/src/services/prompt-templates.ts — citation-forward summary (Unusual.ai guide)

export type SummaryPromptVariant = 'A' | 'B';

/** Citation indices in prompts are 1-based so the model outputs [1], [2] for the first snippet, second snippet, etc. */
const CITATION_OFFSET = 1;

export function buildSummaryPrompt(
  variant: SummaryPromptVariant,
  params: {
    userQuery: string;
    items: unknown[];
    snippets: Array<{ snippet?: string; text?: string }>;
    /** User preference context (free-form). Carried through summarization; not a filter schema. */
    preferenceContext?: string | string[];
  },
): string {
  const { userQuery, snippets, preferenceContext } = params;

  // Dual memory: Working memory (conversation context) vs Retrieved content (factual source only).
  const workingMemoryBlock = `
Working memory (conversation context — for intent and preferences only; do not cite as factual source):
User query: "${userQuery}"
${preferenceContext != null && (Array.isArray(preferenceContext) ? preferenceContext.length > 0 : String(preferenceContext).trim() !== '')
  ? `User preferences: ${Array.isArray(preferenceContext) ? preferenceContext.join(', ') : preferenceContext}`
  : ''}
`;

  const baseSnippets = snippets
    .map((s, idx) => {
      const text = s.snippet ?? s.text ?? '';
      const num = idx + CITATION_OFFSET;
      return `[${num}] ${text.replace(/\s+/g, ' ').slice(0, 300)}`;
    })
    .join('\n');

  const citationRule = `
- Citation-first: Every factual claim or recommendation must cite a source using [1], [2], etc. corresponding to the numbered list below. Do not make claims without a citation.
- Cite sources inline after each claim (snippet 1 = [1], snippet 2 = [2]). Do not invent citation numbers.
- One clear intent per answer: either a definition, or a comparison, or a how-to. Include concrete limits or examples where relevant; avoid vague claims.`;

  const retrievedContentBlock = `
Retrieved content (use only these for factual claims; cite as [1], [2], ...):
${baseSnippets}
`;

  const definitionConstraint = `
- Write the first paragraph as a 2–4 sentence short answer in plain language, suitable for a non-expert. Avoid marketing or sales language.`;
  const comparisonFirstParagraph = `
- For comparison queries (A vs B), write the first paragraph as a single balanced sentence: "Both are X; A is better for Y, B is better for Z." Then a blank line, then the detailed comparison.`;

  if (variant === 'A') {
    return `
You are a citation-forward answer assistant. You receive Working memory (conversation context) and Retrieved content (factual source only). Use ONLY the Retrieved content section for factual claims; Working memory is for intent and preferences only. This separation prevents context contamination.

${workingMemoryBlock}
${retrievedContentBlock}

Instructions:
- Start with a short answer (2–4 sentences) in the first paragraph—the definition or key takeaway in plain language.
${definitionConstraint}
- Then a blank line, then details with inline citations [1], [2], etc. Every factual claim must have a citation.
- Use the items and snippets above. List concrete options when relevant. Structure your answer by the user's criteria when it makes sense (e.g. a short "Why these fit" section).
${citationRule}
`;
  }

  // Variant B: more structured + optional comparison
  return `
You are a citation-forward answer assistant. You receive Working memory (conversation context) and Retrieved content (factual source only). Use ONLY the Retrieved content section for factual claims; Working memory is for intent and preferences only. This separation prevents context contamination.

${workingMemoryBlock}
${retrievedContentBlock}

Instructions:
- First paragraph: short answer (2–4 sentences)—definition or key takeaway. Then a blank line.
${definitionConstraint}
${comparisonFirstParagraph}
- Then key options or recommendations as short bullet points, with [1], [2] after each fact from a snippet. Every factual claim must have a citation.
- If the query compares options (A vs B), add a "When to choose A vs B" section with a clear markdown table (| Feature | A | B |) and criteria.
- Structure your answer by the user's criteria when it makes sense (e.g. "Why these fit" section). Say what matches their preferences and what we don't have data for.
- Cite facts only from the Retrieved content above; use the bracket number for each source.
${citationRule}
`;
}

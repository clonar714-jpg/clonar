// src/services/query-decomposition.ts
// Query Decomposition: generate multiple search sub-queries for parallel retrieval only.
// No verticals, intent, or planning. Input = single resolved query (after context binding + rewrite).
import { callSmallLLM } from './llm-small';
import { logger } from './logger';

const MAX_SUB_QUERIES = 8;
const SHORT_FOLLOW_UP_LENGTH = 40;

function parseSubQueriesJson(raw: string): string[] {
  let txt = raw.trim();
  if (txt.startsWith('```')) {
    const firstNewline = txt.indexOf('\n');
    const lastFence = txt.lastIndexOf('```');
    if (firstNewline !== -1 && lastFence > firstNewline) {
      txt = txt.slice(firstNewline + 1, lastFence).trim();
    } else {
      txt = txt.replace(/^```\w*\n?/, '').replace(/\n?```$/, '').trim();
    }
  }
  try {
    const parsed = JSON.parse(txt) as { subQueries?: unknown };
    const arr = Array.isArray(parsed?.subQueries) ? parsed.subQueries : [];
    return arr.filter((x): x is string => typeof x === 'string' && x.trim().length > 0);
  } catch {
    try {
      const parsed = JSON.parse(txt.replace(/'/g, '"')) as { subQueries?: unknown };
      const arr = Array.isArray(parsed?.subQueries) ? parsed.subQueries : [];
      return arr.filter((x): x is string => typeof x === 'string' && x.trim().length > 0);
    } catch {
      logger.warn('query-decomposition:parse_error', { raw: txt.slice(0, 200) });
      return [];
    }
  }
}

const DECOMPOSITION_SYSTEM = `You are a Query Decomposition module modeled after Perplexity's search pipeline.

Your ONLY responsibility is to generate multiple search sub-queries for parallel retrieval.

THIS IS NOT A PLANNING STEP.

--------------------------------
CORE PRINCIPLES
--------------------------------
- Decomposition exists ONLY to improve retrieval coverage.
- Do NOT infer or output verticals, domains, or intent.
- Do NOT plan execution steps.
- Do NOT reason about user goals.
- Do NOT decide where to search.
- Routing is handled entirely by the retriever.

--------------------------------
INPUT
--------------------------------
You receive:
- A single resolved query string (after context binding and rewrite).
- No chat history.
- No session state.
- No vertical information.

--------------------------------
OUTPUT
--------------------------------
Return JSON ONLY:
{"subQueries": string[]}

--------------------------------
RULES FOR SUB-QUERIES
--------------------------------
- Generate 3–8 sub-queries maximum.
- Each sub-query must be:
  - self-contained
  - explicit
  - unambiguous
- Include domain nouns directly in the wording
  (e.g., "hotel", "flight", "price", "reviews", "buy").
- Avoid vague phrases like:
  - "best options"
  - "good ones"
  - "top choices" (unless qualified)

--------------------------------
WHEN TO SKIP DECOMPOSITION
--------------------------------
If the query is a short follow-up AND context binding already resolved it:
- Return exactly one sub-query equal to the resolved query.
- Do NOT expand further.

--------------------------------
STRICT CONSTRAINTS
--------------------------------
- Do NOT output verticals or intent.
- Do NOT reference internal system behavior.
- Do NOT create execution plans.
- Do NOT ask clarifying questions.
- Do NOT rely on chat history.

Decomposition = search query expansion only.
- Each query must be a standalone search string.
- Remove all conversational filler (e.g., "I will search for...").
- Do NOT repeat the same query in different words.`;

const Example = `
Resolved query: "compare electric cars for families in Europe: safety, price, charging network"
Output:
{
  "subQueries": [
    "best family electric cars Europe safety ratings 2024",
    "electric car prices Europe family models comparison",
    "EV charging infrastructure across Europe for long trips",
    "spacious family electric vehicles Europe reviews"
  ]
}

Resolved query: "latest iPhone 15 features and price"
Output:
{
  "subQueries": [
    "iPhone 15 official features list",
    "iPhone 15 price comparison by model",
    "iPhone 15 camera and battery specifications"
  ]
}

/**
 * Generate 3–8 search sub-queries for parallel retrieval. No verticals, intent, or planning.
 * When isFollowUpResolved is true and the query is short, returns [resolvedQuery] only.
 */
export async function decomposeForRetrieval(
  resolvedQuery: string,
  options?: { isFollowUpResolved?: boolean },
): Promise<string[]> {
  const trimmed = resolvedQuery?.trim() ?? '';
  if (!trimmed) return [];

  const isShortFollowUp =
    options?.isFollowUpResolved === true && trimmed.length <= SHORT_FOLLOW_UP_LENGTH;
  if (isShortFollowUp) {
    return [trimmed];
  }

  const prompt = `${DECOMPOSITION_SYSTEM}

Resolved query: ${JSON.stringify(trimmed)}

Return ONLY valid JSON: {"subQueries": ["query1", "query2", ...]}. No markdown, no code fences. Use double quotes. 3–8 sub-queries.`;

  const raw = await callSmallLLM(prompt);
  const list = parseSubQueriesJson(raw);
  if (list.length === 0) return [trimmed.slice(0, 200)];

  return list.slice(0, MAX_SUB_QUERIES);
}


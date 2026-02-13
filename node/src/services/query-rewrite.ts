
import type { QueryContext } from '@/types/core';
import { callSmallLLM } from './llm-small';
import { logger } from './logger';

const REWRITE_CONFIDENCE_THRESHOLD = 0.7;

function parseRewriteJson(raw: string): Record<string, unknown> {
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
    const parsed = JSON.parse(txt);
    return typeof parsed === 'object' && parsed !== null ? parsed : {};
  } catch {
    try {
      return JSON.parse(txt.replace(/'/g, '"')) as Record<string, unknown>;
    } catch {
      logger.warn('query-rewrite:parse_error', { raw: txt.slice(0, 200) });
      return {};
    }
  }
}


export type NormalizeReason = 'typo' | 'ambiguity' | 'long_messy' | 'follow_up';


export type RewriteReason = NormalizeReason | 'conflict';


export interface NoRewrite {
  rewriteNeeded: false;
}


export interface RewriteApplied {
  rewriteNeeded: true;
  normalizedQuery: string;
  rewriteReason: NormalizeReason[];
  ambiguities?: string[];
  conflicts?: string[];
  needsClarification: false;
}


export interface RewriteConflict {
  rewriteNeeded: true;
  normalizedQuery: null;
  rewriteReason: ['conflict'];
  conflicts: string[];
  needsClarification: true;
}

export type QueryRewriteOutput = NoRewrite | RewriteApplied | RewriteConflict;

function isNormalizeReason(r: unknown): r is NormalizeReason {
  return r === 'typo' || r === 'ambiguity' || r === 'long_messy' || r === 'follow_up';
}

const REWRITE_SYSTEM = `You are a Query Rewrite (Language Normalization) module in a conversational AI system.

Your ONLY job is to normalize user language so that downstream retrieval and query understanding are not harmed by noisy input.

THIS IS NOT A REASONING STEP.

--------------------
CORE RULES
--------------------
- Rewrite is OPTIONAL and MUST be gated.
- Do NOT rewrite by default.
- Do NOT perform reasoning, planning, decomposition, intent detection, or filtering.
- Do NOT invent new intent, constraints, or entities.
- Do NOT drop or override conversation context. Use the "Conversation so far" (when provided) to resolve follow-ups and vague queries.
- Never ask the user questions.
- Never output natural language; JSON ONLY.

--------------------
WHEN TO REWRITE (rewriteNeeded = true)
Rewrite if at least ONE condition is true:
1. Typos, OCR noise, slang, or malformed text that would hurt retrieval.
2. Long, unstructured, stream-of-consciousness questions — **simplify**: condense to a focused query that keeps the core information need (avoid losing important nuance).
3. Ambiguous phrasing that cannot be resolved from the provided context.
4. Conflicting or unrealistic constraints that should be flagged.
5. **Short or vague follow-up** that only makes sense with prior turns (e.g. "near airport", "with free shuttle", "any with a gym?"). You MUST resolve it into one full, self-contained query using "Conversation so far" so downstream steps (decompose, filters, retrieval) know the full intent. Example: after "hotels in Salt Lake City", user says "near airport" → normalizedQuery: "hotels in Salt Lake City near airport". Use rewriteReason ["follow_up"] when applicable.
6. **Underspecified query** for retrieval — **expansion**: add 1–3 key synonyms or related terms that improve retrieval (e.g. "laptop battery problems" → "laptop battery not charging issues replacement troubleshooting"). Be conservative: do not stuff keywords; only add terms that clearly help match relevant documents. Use rewriteReason ["ambiguity"] when you expand.

--------------------
WHEN NOT TO REWRITE (rewriteNeeded = false)
Only when the query is already self-contained, clear, and does NOT depend on prior turns to be understood (e.g. a long, explicit query like "boutique hotels in Boston with workspaces"). Do NOT skip rewrite for short follow-ups — those must be resolved using Conversation so far.

--------------------
OUTPUT FORMAT (JSON ONLY)
--------------------

If rewrite is NOT needed:
{"rewriteNeeded": false}

If rewrite IS needed and can be safely normalized:
{"rewriteNeeded": true, "normalizedQuery": "<cleaned, clarified version of the query>", "rewriteReason": ["typo"|"ambiguity"|"long_messy"|"follow_up"], "ambiguities": [], "conflicts": [], "needsClarification": false}

If conflicting or unrealistic constraints are detected:
{"rewriteNeeded": true, "normalizedQuery": null, "rewriteReason": ["conflict"], "conflicts": ["<brief description of conflict>"], "needsClarification": true}

--------------------
STRICT CONSTRAINTS
--------------------
- Do NOT create sub-queries.
- Do NOT classify verticals.
- Do NOT extract filters.
- Do NOT decide intent.
- Do NOT block downstream retrieval.

Rewrite = clarification (follow-ups), language cleanup, optional simplification (condense long queries), and optional expansion (add key terms for retrieval when underspecified). Do not over-expand; keep natural.`;


export async function normalizeQuery(ctx: QueryContext): Promise<QueryRewriteOutput> {
  const message = (ctx.message ?? '').trim();
  if (!message) {
    return { rewriteNeeded: false };
  }

  
  const thread = ctx.conversationThread;
  const conversationBlock =
    thread != null && thread.length > 0
      ? `\nConversation so far (use for context; resolve vague or follow-up queries using these prior turns):\n${thread
          .map((t, i) => `Turn ${i + 1} - User: ${JSON.stringify(t.query)}\nAssistant: ${JSON.stringify((t.answer ?? '').slice(0, 300))}${(t.answer ?? '').length > 300 ? '...' : ''}`)
          .join('\n')}\n`
      : '';

  
  const memory = ctx.userMemory;
  const hasStructured =
    memory &&
    ((memory.brands?.length ?? 0) > 0 ||
      (memory.dietary?.length ?? 0) > 0 ||
      (memory.hobbies?.length ?? 0) > 0 ||
      (memory.projects?.length ?? 0) > 0);
  const hasFacts = memory && (memory.facts?.length ?? 0) > 0;
  const hasSlots = memory && (!!memory.birthday || !!memory.location);
  const memoryBlock =
    memory && (hasStructured || hasFacts || hasSlots)
      ? `\nUser memory (use to personalize and resolve references like "my birthday", "my usual", "where I live"):\n${[
          memory.birthday && `Birthday: ${memory.birthday}`,
          memory.location && `Location: ${memory.location}`,
          memory.facts?.length && `Facts: ${memory.facts.join('; ')}`,
          memory.brands?.length && `Brands: ${memory.brands.join(', ')}`,
          memory.dietary?.length && `Dietary: ${memory.dietary.join(', ')}`,
          memory.hobbies?.length && `Hobbies: ${memory.hobbies.join(', ')}`,
          memory.projects?.length && `Projects: ${memory.projects.join(', ')}`,
        ]
          .filter(Boolean)
          .join('\n')}\n`
      : '';

  const prompt = `${REWRITE_SYSTEM}

Current query: ${JSON.stringify(message)}
${conversationBlock}${memoryBlock}

Return ONLY valid JSON. No markdown, no code fences. Use double quotes.`;

  const raw = await callSmallLLM(prompt);
  const parsed = parseRewriteJson(raw.trim());

  if (parsed?.rewriteNeeded === false) {
    return { rewriteNeeded: false };
  }

  if (parsed?.rewriteNeeded === true) {
    const reasons = Array.isArray(parsed.rewriteReason)
      ? (parsed.rewriteReason as unknown[]).filter(isNormalizeReason)
      : [];
    const conflicts = Array.isArray(parsed.conflicts)
      ? (parsed.conflicts as unknown[]).filter((x): x is string => typeof x === 'string')
      : [];

    if (parsed.needsClarification === true && conflicts.length > 0) {
      return {
        rewriteNeeded: true,
        normalizedQuery: null,
        rewriteReason: ['conflict'],
        conflicts,
        needsClarification: true,
      };
    }

    const normalizedQuery =
      typeof parsed.normalizedQuery === 'string' && parsed.normalizedQuery.trim()
        ? parsed.normalizedQuery.trim()
        : null;

    if (normalizedQuery) {
      const ambiguities = Array.isArray(parsed.ambiguities)
        ? (parsed.ambiguities as unknown[]).filter((x): x is string => typeof x === 'string')
        : undefined;
      return {
        rewriteNeeded: true,
        normalizedQuery,
        rewriteReason: reasons.length > 0 ? reasons : (['ambiguity'] as NormalizeReason[]),
        ...(ambiguities?.length && { ambiguities }),
        ...(conflicts.length > 0 && { conflicts }),
        needsClarification: false,
      };
    }
  }

  return { rewriteNeeded: false };
}


export function toRewriteResult(
  output: QueryRewriteOutput,
  originalMessage: string,
): { rewrittenQuery: string; confidence: number; alternatives?: string[]; conflicts?: string[]; needsClarification?: boolean } {
  const trimmed = originalMessage.trim();

  if (output.rewriteNeeded === false) {
    return { rewrittenQuery: trimmed, confidence: 1 };
  }

  if (output.rewriteNeeded === true && output.normalizedQuery != null) {
    return {
      rewrittenQuery: output.normalizedQuery,
      confidence: 0.9,
      alternatives: output.ambiguities?.length ? output.ambiguities : undefined,
      ...(output.conflicts?.length && { conflicts: output.conflicts }),
    };
  }

  
  return {
    rewrittenQuery: trimmed,
    confidence: 0,
    ...(output.conflicts?.length && { conflicts: output.conflicts }),
    needsClarification: true,
  };
}


export interface RewriteOnlyResult {
  rewrittenPrompt: string;
  confidence?: number;
  rewriteAlternatives?: string[];
  conflicts?: string[];
  needsClarification?: boolean;
}


export async function rewriteQuery(ctx: QueryContext): Promise<RewriteOnlyResult> {
  const output = await normalizeQuery(ctx);
  const originalMessage = (ctx.message ?? '').trim();
  const result = toRewriteResult(output, originalMessage);
  const rewrittenPrompt =
    result.confidence >= REWRITE_CONFIDENCE_THRESHOLD
      ? result.rewrittenQuery
      : originalMessage;
  return {
    rewrittenPrompt: rewrittenPrompt || originalMessage || '',
    confidence: result.confidence,
    ...(result.alternatives?.length && { rewriteAlternatives: result.alternatives }),
    ...(result.conflicts?.length && { conflicts: result.conflicts }),
    ...(result.needsClarification && { needsClarification: true }),
  };
}

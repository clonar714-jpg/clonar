
import type { QueryContext } from '@/types/core';
import { callSmallLLM } from './llm-small';
import { safeParseJson } from './safe-parse-json';
import { logger } from '@/utils/logger';

export type GroundingMode = 'none' | 'hybrid' | 'full';

export interface GroundingDecision {
  grounding_mode: GroundingMode;
  reason: string;
}

const GROUNDING_USER_TEMPLATE = `You are a retrieval router. Your only job is to choose how much external retrieval this query needs. Output valid JSON only.

Decision rule (apply in order):

1. **full** — Use when ANY of the following is true:
   - User intent maps to a supported vertical: hotels (stay, book, accommodation), flights (travel, fly, book), products (buy, shop, recommend, best X under $Y, outfits, gifts, compare), movies (showtimes, theaters, tickets).
   - The message is a follow-up that refers to something already discussed in the conversation (e.g. "that hotel", "tell me more", "what about the second one?").
   - The user is asking for real-world, bookable or buyable options (names, prices, availability).
   When in doubt between full and hybrid, prefer **full** for vertical-like or transactional intent.

2. **hybrid** — Use ONLY when:
   - The query needs a short web overview or recent citations but does NOT fit any vertical (no booking, buying, or finding specific hotels/flights/products/showtimes). Examples: "What did the Fed say about interest rates recently?", "What are the pros and cons of remote work?", "What's the best time of year to visit Iceland?", "What is the current consensus on intermittent fasting?" — all benefit from web search but are not transactional.
   Do NOT use hybrid for: finding or booking hotels, flights, products, or movies; shopping; "best X under $Y"; gift or outfit recommendations; any intent that clearly belongs to a vertical.

3. **none** — Use when:
   - The question is conceptual, definitional, or general knowledge only, with no need for current data or citations (e.g. "what is inflation?", "how does photosynthesis work?").
   - The question is clearly standalone and does not refer to the conversation. If the user refers to something just discussed, use **full**.

<conversationBlock>

Current message:
<rewrittenQuery>

Output exactly this JSON (no markdown, no extra text):
{"grounding_mode":"none"|"hybrid"|"full","reason":"one short sentence explaining the choice"}`;

/**
 * Decides how much grounding the rewritten query needs (none | hybrid | full).
 * Called AFTER rewrite and BEFORE plan/execute retrieval.
 *
 * @returns grounding_mode + reason. On parse failure, defaults to 'full' (safe).
 */
const GROUNDING_TIMEOUT_MS = 8_000;

const VALID_MODES: GroundingMode[] = ['none', 'hybrid', 'full'];

function parseGroundingMode(v: unknown): GroundingMode {
  if (typeof v === 'string' && VALID_MODES.includes(v as GroundingMode)) {
    return v as GroundingMode;
  }
  return 'full';
}

function buildConversationBlock(ctx: QueryContext): string {
  const thread = ctx.conversationThread;
  if (thread && thread.length > 0) {
    const lastTurns = thread.slice(-3).map((t) => `User: ${t.query}\nAssistant: ${(t.answer ?? '').slice(0, 300)}${(t.answer?.length ?? 0) > 300 ? '...' : ''}`);
    return `Conversation so far (last ${lastTurns.length} turn(s)):\n${lastTurns.join('\n\n')}\n\n`;
  }
  const history = ctx.history?.filter((h) => h?.trim()).slice(-3) ?? [];
  if (history.length > 0) {
    return `Previous user messages in this conversation:\n${history.map((h) => `- ${h}`).join('\n')}\n\n`;
  }
  return '';
}

export async function shouldUseGroundedRetrieval(
  ctx: QueryContext,
  rewrittenPrompt: string,
): Promise<GroundingDecision> {
  const rewrittenQuery = rewrittenPrompt?.trim() || ctx.message.trim();
  const conversationBlock = buildConversationBlock(ctx);
  const userPrompt = GROUNDING_USER_TEMPLATE.replace(
    '<conversationBlock>',
    conversationBlock,
  ).replace('<rewrittenQuery>', rewrittenQuery);

  const run = async (): Promise<GroundingDecision> => {
    logger.info('flow:grounding_input', {
      step: 'grounding_input',
      messagePreview: rewrittenQuery.slice(0, 120),
      hasConversationThread: !!(conversationBlock && conversationBlock.trim().length > 0),
    });
    try {
      const raw = await callSmallLLM(userPrompt);
      const parsed = safeParseJson(raw, 'grounding-decision');

      const grounding_mode = parseGroundingMode(parsed?.grounding_mode);
      const reason =
        typeof parsed?.reason === 'string' && parsed.reason.trim()
          ? parsed.reason.trim()
          : grounding_mode === 'none'
            ? 'No external lookup required'
            : 'Default (parse or missing field)';

      if (typeof parsed?.grounding_mode !== 'string' || !VALID_MODES.includes(parsed.grounding_mode as GroundingMode)) {
        logger.warn('grounding-decision:parse_fallback', {
          raw: raw.slice(0, 200),
          defaultMode: grounding_mode,
        });
      }

      logger.info('grounding-decision:done', {
        grounding_mode,
        reason: reason.slice(0, 120),
      });

      return { grounding_mode, reason };
    } catch (err) {
      logger.warn('grounding-decision:error', {
        err: err instanceof Error ? err.message : String(err),
      });
      return { grounding_mode: 'full', reason: 'Error, defaulting to full retrieval' };
    }
  };

  const timeout = new Promise<GroundingDecision>((resolve) => {
    setTimeout(
      () => {
        logger.warn('grounding-decision:timeout', { ms: GROUNDING_TIMEOUT_MS });
        resolve({ grounding_mode: 'full', reason: 'Timeout, defaulting to full retrieval' });
      },
      GROUNDING_TIMEOUT_MS,
    );
  });

  return Promise.race([run(), timeout]);
}

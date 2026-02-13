/**
 * Shared JSON parse that strips markdown fences and normalizes quotes.
 * Used by orchestrator (follow-ups), grounding-decision, retrieval-plan.
 */
import { logger } from '@/services/logger';

export function safeParseJson(raw: string, context: string): Record<string, any> {
  let txt = raw.trim();

  if (txt.startsWith('```')) {
    const firstNewline = txt.indexOf('\n');
    const lastFence = txt.lastIndexOf('```');
    if (firstNewline !== -1 && lastFence !== -1 && lastFence > firstNewline) {
      txt = txt.slice(firstNewline + 1, lastFence).trim();
    } else {
      txt = txt.replace(/^```\w*\n?/, '').replace(/\n?```$/, '').trim();
    }
  }

  try {
    const parsed = JSON.parse(txt);
    if (typeof parsed === 'object' && parsed !== null) return parsed;
    logger.warn('safeParseJson:non_object', { context, raw: txt.slice(0, 300) });
    return {};
  } catch {
    try {
      const normalized = txt.replace(/'/g, '"');
      const parsed = JSON.parse(normalized);
      if (typeof parsed === 'object' && parsed !== null) return parsed;
    } catch {
      // ignore
    }
    logger.warn('safeParseJson:parse_error', {
      context,
      error: 'Invalid JSON after stripping fences',
      raw: txt.slice(0, 300),
    });
    return {};
  }
}

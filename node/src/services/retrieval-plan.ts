/**
 * Stage 4 of the 7-stage flow: Plan retrieval steps.
 * LLM takes rewritten query + extracted filters + user memory and outputs
 * an ordered list of steps (tool + args + optional context_from_step).
 * Single-hop = 1 step; multi-hop = 2–4 steps with context_from_step for conditioning.
 */
import type { QueryContext, Vertical } from '@/types/core';
import type { ExtractedFilters } from './filter-extraction';
import { callSmallLlmJson } from './llm-small';
import { logger } from './logger';
import { safeParseJson } from './safe-parse-json';

export const RETRIEVAL_TOOLS = [
  'weather_search',
  'hotel_search',
  'product_search',
  'flight_search',
  'movie_search',
  'web_search',
] as const;

export type RetrievalToolName = (typeof RETRIEVAL_TOOLS)[number];

export interface RetrievalStep {
  tool: RetrievalToolName;
  args: Record<string, unknown>;
  /** 1-based index of the step whose result should be injected into this step's args (e.g. preferenceContext). */
  context_from_step?: number;
}

export interface RetrievalPlan {
  steps: RetrievalStep[];
}

/** Planned primary vertical from first step (for UI layout). Observed = who returned most. */
export function getPlannedPrimaryVertical(steps: RetrievalStep[]): Vertical {
  const tool = steps[0]?.tool;
  if (tool === 'hotel_search') return 'hotel';
  if (tool === 'flight_search') return 'flight';
  if (tool === 'product_search') return 'product';
  if (tool === 'movie_search') return 'movie';
  return 'other';
}

const MAX_STEPS = 4;

function formatFiltersForPrompt(filters: ExtractedFilters): string {
  const parts: string[] = [];
  if (filters.hotel) parts.push(`hotel: ${JSON.stringify(filters.hotel)}`);
  if (filters.flight) parts.push(`flight: ${JSON.stringify(filters.flight)}`);
  if (filters.product) parts.push(`product: ${JSON.stringify(filters.product)}`);
  if (filters.movie) parts.push(`movie: ${JSON.stringify(filters.movie)}`);
  if (filters.preferenceDescription) parts.push(`preferenceDescription (use as preferenceContext in step args for hotel/product/flight/movie): ${filters.preferenceDescription}`);
  return parts.length ? parts.join('\n') : 'none';
}

/**
 * Plan retrieval steps. Always returns at least one step.
 * For simple queries: one step (e.g. hotel_search or web_search).
 * For condition-based: multiple steps with context_from_step (e.g. weather_search then product_search with context_from_step: 1).
 */
export async function planRetrievalSteps(
  ctx: QueryContext,
  rewrittenQuery: string,
  extractedFilters: ExtractedFilters,
): Promise<RetrievalPlan> {
  const historyBlock =
    (ctx.history ?? []).slice(-3).length > 0
      ? `\nRecent conversation:\n${(ctx.history ?? []).slice(-3).map((h, i) => `${i + 1}. ${h}`).join('\n')}\n`
      : '';
  const userMemoryBlock = ctx.userMemory
    ? `\nUser memory (use when relevant): ${JSON.stringify(ctx.userMemory)}\n`
    : '';
  const filtersBlock = formatFiltersForPrompt(extractedFilters);

  const systemPrompt = `You are an AI planner acting as a CONTROLLER, not a retriever.
Your job is to decide WHICH retrieval tools to call and IN WHAT ORDER.
You must NOT retrieve data, rank results, score items, or choose final answers.

ALLOWED TOOLS (choose only from these): ${RETRIEVAL_TOOLS.join(', ')}

Tool args (use these exact keys when applicable; use extracted filters when provided):
- weather_search: { "location": "<city/region>", "date": "YYYY-MM-DD" }
- hotel_search: { "rewrittenQuery": "<query>", "destination": "<city>", "checkIn"?: "YYYY-MM-DD", "checkOut"?: "YYYY-MM-DD", "guests"?: number, "preferenceContext"?: "<optional>" }
- product_search: { "query": "<search text>", "rewrittenQuery": "<query>", "budgetMin"?: number, "budgetMax"?: number, "category"?: string, "brands"?: string[], "preferenceContext": "<optional>" }
- flight_search: { "rewrittenQuery": "<query>", "origin": "<city>", "destination": "<city>", "departDate"?: "YYYY-MM-DD", "returnDate"?: "YYYY-MM-DD", "adults"?: number, "preferenceContext": "<optional>" }
- movie_search: { "rewrittenQuery": "<query>", "city": "<city>", "date"?: "YYYY-MM-DD", "tickets"?: number, "preferenceContext": "<optional>" }
- web_search: { "query": "<search text>" }

DATES AND GUESTS: Only include checkIn, checkOut, guests (hotel_search), departDate, returnDate, adults (flight_search), date, tickets (movie_search) when the user explicitly provided them or they are clearly implied (e.g. "next weekend"). Otherwise OMIT these keys; the executor will inject system defaults. Do not invent dates or guest counts.

When preferenceDescription is provided in Extracted filters, set args.preferenceContext to it for hotel_search, product_search, flight_search, movie_search so the system can rank results by these subjective criteria (e.g. good workspace, close to restaurants).

OUTPUT SCHEMA (STRICT) — return ONLY this JSON shape:
{"steps":[{"tool":"<allowed tool>","args":{...},"context_from_step":<optional 1-based index>}]}

RULES:
1. Always return at least ONE step; at most FOUR steps.
2. Prefer FEWER steps. Use a single step when the query clearly fits one tool. Do not add extra steps (e.g. weather, web) unless the query explicitly needs them.
3. Default to ONE step. Use multiple steps ONLY when the query cannot be answered without an earlier step's result.
4. Use context_from_step (1-based) when a step depends on a previous step (e.g. weather → clothing, entity → follow-up).
5. Do NOT invent tools. Do NOT include text outside the JSON.

FILTER HANDLING: Use extracted filters when they apply; do not hallucinate filters. Do not invent dates or guest counts—omit those keys when not user-provided or clearly implied.

FALLBACK: If the query is vague or does not map to a domain, return exactly one step: {"tool":"web_search","args":{"query":"<rewritten query>"}}.

EXAMPLES:
Single-hop: "hotels in Paris next week" → {"steps":[{"tool":"hotel_search","args":{"rewrittenQuery":"hotels in Paris next week","destination":"Paris","checkIn":"YYYY-MM-DD","checkOut":"YYYY-MM-DD"}}]}
Multi-hop: "what to wear for my birthday based on weather" → {"steps":[{"tool":"weather_search","args":{"location":"<user location>","date":"YYYY-MM-DD"}},{"tool":"product_search","args":{"query":"birthday outfit","rewrittenQuery":"what to wear for my birthday"},"context_from_step":1}]}`;

  const userPrompt = `INPUT:
Rewritten query: ${rewrittenQuery}
${historyBlock}${userMemoryBlock}
Extracted filters:
${filtersBlock}

Return ONLY valid JSON (no markdown, no explanation).`;

  const raw = await callSmallLlmJson({ system: systemPrompt, user: userPrompt });
  const parsed = safeParseJson(raw, 'planRetrievalSteps') as { steps?: unknown[] } | null;

  const steps: RetrievalStep[] = [];
  const rawSteps = Array.isArray(parsed?.steps) ? parsed.steps : [];

  for (let i = 0; i < Math.min(rawSteps.length, MAX_STEPS); i++) {
    const s = rawSteps[i];
    if (typeof s !== 'object' || s === null) continue;
    const obj = s as Record<string, unknown>;
    const tool = typeof obj.tool === 'string' ? obj.tool : '';
    if (!RETRIEVAL_TOOLS.includes(tool as RetrievalToolName)) continue;
    const args = typeof obj.args === 'object' && obj.args !== null ? (obj.args as Record<string, unknown>) : {};
    const context_from_step =
      typeof obj.context_from_step === 'number' && obj.context_from_step >= 1 && obj.context_from_step <= i /* 1-based index of a previous step */
        ? obj.context_from_step
        : undefined;
    steps.push({
      tool: tool as RetrievalToolName,
      args,
      ...(context_from_step !== undefined && { context_from_step }),
    });
  }

  // Ensure steps that need rewrittenQuery have it (executor expects it for verticals)
  const toolsNeedingQuery: RetrievalToolName[] = ['hotel_search', 'flight_search', 'product_search', 'movie_search'];
  for (const step of steps) {
    if (toolsNeedingQuery.includes(step.tool) && step.args && typeof step.args.rewrittenQuery !== 'string') {
      step.args = { ...step.args, rewrittenQuery: rewrittenQuery };
    }
  }

  // Merge extracted filters into step args so user constraints (e.g. "under 900$" → budgetMax) are never dropped
  for (const step of steps) {
    if (step.tool === 'product_search' && extractedFilters.product) {
      const p = extractedFilters.product;
      if (typeof p.query === 'string' && p.query.trim()) step.args = { ...step.args, query: p.query };
      if (typeof p.budgetMin === 'number' && p.budgetMin >= 0) step.args = { ...step.args, budgetMin: p.budgetMin };
      if (typeof p.budgetMax === 'number' && p.budgetMax > 0) step.args = { ...step.args, budgetMax: p.budgetMax };
      if (typeof p.category === 'string' && p.category.trim()) step.args = { ...step.args, category: p.category };
      if (Array.isArray(p.brands) && p.brands.length) step.args = { ...step.args, brands: p.brands };
    }
    if (step.tool === 'hotel_search' && extractedFilters.hotel) {
      const h = extractedFilters.hotel;
      if (typeof h.destination === 'string' && h.destination.trim()) step.args = { ...step.args, destination: h.destination };
      if (typeof h.checkIn === 'string') step.args = { ...step.args, checkIn: h.checkIn };
      if (typeof h.checkOut === 'string') step.args = { ...step.args, checkOut: h.checkOut };
      if (typeof h.guests === 'number') step.args = { ...step.args, guests: h.guests };
      if (typeof h.budgetMin === 'number' && h.budgetMin >= 0) step.args = { ...step.args, budgetMin: h.budgetMin };
      if (typeof h.budgetMax === 'number' && h.budgetMax > 0) step.args = { ...step.args, budgetMax: h.budgetMax };
      if (typeof h.area === 'string' && h.area.trim()) step.args = { ...step.args, area: h.area };
      if (Array.isArray(h.amenities) && h.amenities.length) step.args = { ...step.args, amenities: h.amenities };
    }
    if (step.tool === 'flight_search' && extractedFilters.flight) {
      const f = extractedFilters.flight;
      if (typeof f.origin === 'string' && f.origin.trim()) step.args = { ...step.args, origin: f.origin };
      if (typeof f.destination === 'string' && f.destination.trim()) step.args = { ...step.args, destination: f.destination };
      if (typeof f.departDate === 'string') step.args = { ...step.args, departDate: f.departDate };
      if (typeof f.returnDate === 'string') step.args = { ...step.args, returnDate: f.returnDate };
      if (typeof f.adults === 'number') step.args = { ...step.args, adults: f.adults };
      if (f.cabin != null) step.args = { ...step.args, cabin: f.cabin };
    }
    if (step.tool === 'movie_search' && extractedFilters.movie) {
      const m = extractedFilters.movie;
      if (typeof m.city === 'string' && m.city.trim()) step.args = { ...step.args, city: m.city };
      if (typeof m.date === 'string') step.args = { ...step.args, date: m.date };
      if (typeof m.movieTitle === 'string' && m.movieTitle.trim()) step.args = { ...step.args, movieTitle: m.movieTitle };
      if (typeof m.tickets === 'number') step.args = { ...step.args, tickets: m.tickets };
      if (typeof m.timeWindow === 'string') step.args = { ...step.args, timeWindow: m.timeWindow };
      if (typeof m.format === 'string') step.args = { ...step.args, format: m.format };
    }
  }

  if (steps.length === 0) {
    steps.push({
      tool: 'web_search',
      args: { query: rewrittenQuery },
    });
  }

  logger.info('flow:retrieval_plan', {
    step: 'retrieval_plan',
    stepCount: steps.length,
    steps: steps.map((s, i) => ({
      index: i + 1,
      tool: s.tool,
      argsKeys: Object.keys(s.args ?? {}),
      context_from_step: s.context_from_step ?? null,
      preferenceContext: (s.args?.preferenceContext as string)?.slice(0, 80) ?? null,
    })),
  });
  return { steps };
}

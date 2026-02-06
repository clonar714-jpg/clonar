/**
 * Layer 2: LLM-as-planner for multi-step, conditional execution.
 * Produces a StepPlan (steps with capability + input + optional runIf) when the query
 * benefits from dynamic sequencing (e.g. weather then hotels, or conditional steps).
 */
import type { QueryContext } from '@/types/core';
import type { StepPlan, Step } from '@/types/planning';
import { callSmallLLM } from './llm-small';
import { safeParseJson } from './query-understanding';

const CAPABILITIES = [
  'hotel_search',
  'flight_search',
  'product_search',
  'movie_search',
  'weather_search',
] as const;

/** Heuristic + optional LLM: should we use a step plan for this query? */
export async function shouldUseStepPlan(ctx: QueryContext): Promise<boolean> {
  const msg = (ctx.message ?? '').toLowerCase();
  const history = (ctx.history ?? []).slice(-3).join(' ').toLowerCase();

  // Heuristic: multi-step / conditional cues
  const hasWeather = /\bweather\b|\bforecast\b|\brain\b|\bsunny\b|\btemperature\b/.test(msg) || /\bweather\b/.test(history);
  const hasConditional = /\bif\b.*\b(then|get|find|book|show)\b|\bthen\b|depending on\b|in case\b/.test(msg);
  const hasMultiple = /\band\s+(then|also)\b|,\s*and\s+|\bplus\b.*\b(weather|hotel|flight)\b/.test(msg);
  const hasSequence = /\bfirst\b.*\bthen\b|\bafter\b.*\b(that|checking)\b/.test(msg);

  if (hasWeather && (hasConditional || hasMultiple || hasSequence)) return true;
  if (hasConditional && (hasMultiple || hasSequence)) return true;

  // Optional: ask LLM for borderline cases (e.g. "weekend in Boston" → weather + hotels)
  if (hasWeather || msg.includes('weekend') || msg.includes('trip')) {
    const prompt = `Does this query need MULTI-STEP or CONDITIONAL execution? Examples: "weather then hotels", "if rain then indoor activities", "flights and hotels and weather".
Query: "${ctx.message}"
Answer with JSON only: {"useStepPlan": true or false}. No explanation.`;
    try {
      const raw = await callSmallLLM(prompt);
      const parsed = safeParseJson(raw, 'shouldUseStepPlan');
      return parsed?.useStepPlan === true;
    } catch {
      return false;
    }
  }
  return false;
}

/** Produce a StepPlan from the user query. Returns null if we should fall back to VerticalPlan. */
export async function planSteps(ctx: QueryContext): Promise<StepPlan | null> {
  const historyBlock =
    (ctx.history ?? []).slice(-3).length > 0
      ? `\nRecent conversation:\n${(ctx.history ?? []).slice(-3).map((h, i) => `${i + 1}. ${h}`).join('\n')}\n`
      : '';

  const prompt = `You are a planning assistant. The user's query may require multiple steps or conditional execution (e.g. get weather first, then search hotels; or "if rain then indoor activities").

Available capabilities (tools): ${CAPABILITIES.join(', ')}.

For each step you output:
- id: unique short id (e.g. "step1", "weather")
- capability: one of ${CAPABILITIES.join(' | ')}
- input: object with the right args for that capability. Examples:
  - weather_search: { "location": "city or place", "date": "YYYY-MM-DD" }
  - hotel_search: { "rewrittenQuery": "...", "destination": "...", "checkIn": "YYYY-MM-DD", "checkOut": "YYYY-MM-DD", "guests": number }
  - flight_search: { "rewrittenQuery": "...", "origin": "...", "destination": "...", "departDate": "YYYY-MM-DD", "adults": number }
  - product_search: { "query": "...", "rewrittenQuery": "..." }
  - movie_search: { "rewrittenQuery": "...", "city": "...", "date": "YYYY-MM-DD", "tickets": number }
- runIf (optional): only if this step depends on a previous step. Simple condition in words, e.g. "precipitation probability is high" or "weather is good"
- conditionOnStepId (optional): id of the step whose output this condition refers to

User query: ${JSON.stringify(ctx.message)}
${historyBlock}

Return JSON only. No markdown, no code fences. Use this exact shape:
{
  "type": "step_plan",
  "goal": "one sentence describing what the user wants overall",
  "rewrittenPrompt": "cleaned/full version of the user request",
  "steps": [
    { "id": "step1", "capability": "weather_search", "input": { "location": "...", "date": "..." } },
    { "id": "step2", "capability": "hotel_search", "input": { ... }, "runIf": "weather is acceptable", "conditionOnStepId": "step1" }
  ]
}
If the query is a single simple request (one hotel search, one product search, etc.), return {"type":"step_plan","steps":[],"goal":"","rewrittenPrompt":""} so the caller can fall back to normal flow.`;

  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'planSteps');

  if (parsed?.type !== 'step_plan' || !Array.isArray(parsed.steps)) return null;
  const steps = parsed.steps as unknown[];
  const validSteps: Step[] = [];
  for (const s of steps) {
    if (typeof s !== 'object' || s === null) continue;
    const obj = s as Record<string, unknown>;
    const id = typeof obj.id === 'string' ? obj.id : `step${validSteps.length + 1}`;
    const cap = typeof obj.capability === 'string' ? obj.capability : '';
    if (!CAPABILITIES.includes(cap as (typeof CAPABILITIES)[number])) continue;
    const input = typeof obj.input === 'object' && obj.input !== null ? (obj.input as Record<string, unknown>) : {};
    validSteps.push({
      id,
      capability: cap,
      input,
      ...(typeof obj.runIf === 'string' && { runIf: obj.runIf }),
      ...(typeof obj.conditionOnStepId === 'string' && { conditionOnStepId: obj.conditionOnStepId }),
    });
  }

  if (validSteps.length === 0) return null;

  return {
    type: 'step_plan',
    goal: typeof parsed.goal === 'string' ? parsed.goal : parsed.rewrittenPrompt ?? ctx.message,
    rewrittenPrompt: typeof parsed.rewrittenPrompt === 'string' ? parsed.rewrittenPrompt : ctx.message,
    steps: validSteps,
  };
}

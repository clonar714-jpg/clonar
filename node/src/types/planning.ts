import { Vertical } from '@/types/core';

/** A step in a multi-step plan. The planner outputs this, the orchestrator executes it. */
export interface Step {
  id: string;
  /** The capability (tool) to call, e.g. 'hotel_search', 'weather_search'. */
  capability: string;
  /** Structured input arguments for the tool. */
  input: Record<string, unknown>;
  /** Optional condition: run this step only if `true`. Refers to previous step's output. */
  runIf?: string;
  /** Optional ID of the step whose output this condition depends on. */
  conditionOnStepId?: string;
}

/** A multi-step execution plan produced by the planner. */
export interface StepPlan {
  type: 'step_plan';
  steps: Step[];
  /** A final goal or instruction for the whole plan, for synthesis. */
  goal: string;
  /** Overall rewritten query for synthesis. */
  rewrittenPrompt: string;
}

/** Re-export from tool-contract for plan/executor use. */
export type { WeatherResult, WeatherSearchToolInput, WeatherSearchToolResult } from '@/mcp/tool-contract';

export type StepOutput =
  | Record<string, unknown>
  | import('@/mcp/tool-contract').WeatherResult
  | unknown;

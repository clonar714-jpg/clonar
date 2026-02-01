// src/services/orchestrator-stream.ts — SSE wrapper around runPipeline
import { runPipeline, type Citation, type OrchestratorDeps, type PipelineResult } from './orchestrator';
import { QueryContext } from '@/types/core';

export type StreamHandlers = {
  onToken: (chunk: { text: string }) => void;
  onCitations: (citations: Citation[]) => void;
  onDone: (payload: PipelineResult) => void;
};

const CHUNK_CHAR_LIMIT = 30;
const CHUNK_DELAY_MS = 10;

export async function runPipelineStream(
  ctx: QueryContext,
  deps: OrchestratorDeps,
  handlers: StreamHandlers,
): Promise<void> {
  let result: PipelineResult;
  try {
    result = await runPipeline(ctx, deps);
  } catch {
    // HTTP layer (query.ts) already handles errors and emits an SSE error event.
    return;
  }

  const summary = result.summary ?? '';
  const words = summary.split(' ');
  let buffer = '';

  for (const word of words) {
    buffer += (buffer ? ' ' : '') + word;
    if (buffer.length >= CHUNK_CHAR_LIMIT) {
      handlers.onToken({ text: buffer });
      buffer = '';
      await new Promise((r) => setTimeout(r, CHUNK_DELAY_MS));
    }
  }
  if (buffer) {
    handlers.onToken({ text: buffer });
  }

  const citations = result.citations ?? [];
  handlers.onCitations(citations);

  handlers.onDone(result);
}

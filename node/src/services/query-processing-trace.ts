// src/services/query-processing-trace.ts
// Structured tracing for query processing (rewrite, decompose, filter, route, retrieve).
import crypto from 'crypto';

export interface Span {
  name: string;
  startTime: number;
  endTime: number;
  durationMs: number;
  input?: unknown;
  output?: unknown;
  metadata?: Record<string, unknown>;
  error?: string;
}

export interface QueryProcessingTrace {
  traceId: string;
  startTime: number;
  endTime?: number;
  spans: Span[];
  originalQuery?: string;
  rewrittenQuery?: string;
  variant?: string;
}

function generateTraceId(): string {
  return 'qp_' + crypto.randomBytes(8).toString('hex');
}

export function createTrace(options?: { originalQuery?: string; variant?: string }): QueryProcessingTrace {
  const startTime = Date.now();
  return {
    traceId: generateTraceId(),
    startTime,
    spans: [],
    originalQuery: options?.originalQuery,
    variant: options?.variant,
  };
}

export function addSpan(
  trace: QueryProcessingTrace,
  name: string,
  startTime: number,
  options?: { output?: unknown; input?: unknown; metadata?: Record<string, unknown>; error?: string },
): void {
  const endTime = Date.now();
  trace.spans.push({
    name,
    startTime,
    endTime,
    durationMs: endTime - startTime,
    input: options?.input,
    output: options?.output,
    metadata: options?.metadata,
    error: options?.error,
  });
}

export function finishTrace(trace: QueryProcessingTrace): void {
  trace.endTime = Date.now();
}

// MOVED VERBATIM — NO LOGIC CHANGES
import { Request, Response } from "express";
import { handleAgentRequestSimple as handleAgentRequest } from "./agent.handler.simple";

// ✅ FIX: Request queue to prevent overwhelming the system with concurrent requests
interface QueuedRequest {
  req: Request;
  res: Response;
  resolve: () => void;
}

export let requestQueue: QueuedRequest[] = [];
let processingCount = 0;
export const MAX_CONCURRENT_REQUESTS = 5; // Maximum concurrent requests
export const MAX_QUEUE_SIZE = 20; // Maximum queue size

/**
 * ✅ FIX: Get current processing count
 */
export function getProcessingCount(): number {
  return processingCount;
}

/**
 * ✅ FIX: Increment processing count
 */
export function incrementProcessingCount(): void {
  processingCount++;
}

/**
 * ✅ FIX: Decrement processing count
 */
export function decrementProcessingCount(): void {
  processingCount--;
}

/**
 * ✅ FIX: Process queued requests
 */
export async function processQueue(): Promise<void> {
  if (processingCount >= MAX_CONCURRENT_REQUESTS || requestQueue.length === 0) {
    return;
  }

  const next = requestQueue.shift();
  if (!next) return;

  incrementProcessingCount();
  next.resolve(); // Release the request to be processed

  // Process the request
  try {
    await handleAgentRequest(next.req, next.res);
  } catch (err: any) {
    console.error("❌ Request processing error:", err);
    if (!next.res.headersSent) {
      next.res.status(500).json({ error: "Request processing failed", detail: err.message });
    }
  } finally {
    decrementProcessingCount();
    // Process next in queue
    processQueue();
  }
}


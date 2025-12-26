// src/utils/sse.ts
import { Response } from "express";

export class SSE {
  private res: Response;
  private initialized = false;

  constructor(res: Response) {
    this.res = res;
  }

  /**
   * Initialize the SSE stream with headers.
   */
  init(): void {
    if (this.initialized) return;
    
    // ✅ FIX: Check if headers already sent (prevents ERR_HTTP_HEADERS_SENT)
    if (this.res.headersSent) {
      console.warn("⚠️ SSE headers already sent, skipping init");
      this.initialized = true; // Mark as initialized to prevent further attempts
      return;
    }

    this.res.setHeader("Content-Type", "text/event-stream");
    this.res.setHeader("Cache-Control", "no-cache, no-transform");
    this.res.setHeader("Connection", "keep-alive");
    this.res.setHeader("Access-Control-Allow-Origin", "*");
    this.res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    
    // Flush headers immediately
    if (typeof this.res.flushHeaders === 'function') {
      this.res.flushHeaders();
    }

    this.initialized = true;
  }

  /**
   * Send an SSE event in the format Flutter expects:
   * 
   * data: { "type": "message", "data": "token" }
   * data: { "type": "sources", "data": [...] }
   * 
   * If data is an object, it will be spread into the payload.
   * If data is a string or primitive, it will be set as the "data" field.
   */
  send(type: string, data: any): void {
    if (!this.initialized) this.init();

    // Handle different data types
    let payload: any;
    if (typeof data === 'string' || typeof data === 'number' || typeof data === 'boolean') {
      // Primitive types go directly into "data" field
      payload = { type, data };
    } else if (data && typeof data === 'object') {
      // Objects are spread into payload, but ensure "type" is set
      payload = { type, ...data };
    } else {
      // Fallback for null/undefined
      payload = { type, data: null };
    }

    this.res.write(`data: ${JSON.stringify(payload)}\n\n`);
    
    // Force flush if available (Express Response doesn't have flush, but some implementations do)
    if (typeof (this.res as any).flush === 'function') {
      (this.res as any).flush();
    }
  }

  /**
   * Close the SSE stream connection.
   */
  close(): void {
    try {
      this.res.write("data: [DONE]\n\n");
      this.res.end();
    } catch (err: any) {
      console.error("❌ Error closing SSE stream:", err);
    }
  }
}

// src/refinement/refineQuery.ts
import { buildRefinedQuery } from "./buildQuery";
import { llmRewrite } from "./llmRewrite";

/**
 * 🧠 C11.3 — FINAL QUERY REFINER
 * This is what the backend actually uses before card search
 * Combines memory-aware building + LLM rewriting
 */
export async function refineQuery(query: string, sessionId: string): Promise<string> {
  // 1. Build memory-enhanced query
  const memoryQ = await buildRefinedQuery(query, sessionId);

  // 2. LLM rewrite for clarity/completeness
  try {
    const rewritten = await llmRewrite(memoryQ);
    return rewritten || memoryQ;
  } catch (err: any) {
    console.error("❌ Query refinement error:", err.message);
    return memoryQ; // Fallback to memory-enhanced query
  }
}


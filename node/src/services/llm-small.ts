// src/services/llm-small.ts — classification via model router
import { SimpleModelRouter } from './model-router';
import { ProviderLlmClient } from './llm-client';

const router = new SimpleModelRouter(new ProviderLlmClient());

export async function callSmallLLM(prompt: string): Promise<string> {
  return router.classify(prompt);
}

/** Same as classify but accepts system + user for JSON-oriented calls (e.g. reranker). */
export async function callSmallLlmJson(input: {
  system: string;
  user: string;
}): Promise<string> {
  const prompt = `${input.system}\n\n${input.user}`;
  return router.classify(prompt);
}

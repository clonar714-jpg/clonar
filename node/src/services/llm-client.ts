// node/src/services/llm-client.ts — low-level client implementing LlmClient for the router

import OpenAI from 'openai';
import type { LlmClient, ModelName, LlmCallOptions } from './model-router';

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error(
        'Missing OPENAI_API_KEY. Set it in .env or pass it when starting the server.',
      );
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}

const DEFAULT_SYSTEM: Record<LlmCallOptions['task'], string> = {
  classification: 'You are a JSON-only classifier/extractor.',
  planner: 'You are a research planner. Respond in JSON.',
  summary: 'You are a helpful ecommerce & travel assistant.',
  critique: 'You are a strict answer critic. Return only the improved answer text.',
};

export class ProviderLlmClient implements LlmClient {
  async call(
    model: ModelName,
    prompt: string,
    options?: LlmCallOptions,
  ): Promise<string> {
    const modelId = model === 'small' ? 'gpt-4o-mini' : 'gpt-4.1-mini';
    const system =
      options?.task ? DEFAULT_SYSTEM[options.task] : DEFAULT_SYSTEM.summary;
    const maxTokens =
      typeof options?.maxTokens === 'number' ? options.maxTokens : 512;

    const res = await getClient().chat.completions.create({
      model: modelId,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: prompt },
      ],
      temperature: options?.task === 'classification' ? 0 : 0.5,
      max_tokens: maxTokens,
    });
    return res.choices[0]?.message?.content ?? '';
  }
}

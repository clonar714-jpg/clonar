// src/services/llm-main.ts — summaries (direct) + router-based planner/critique
import OpenAI from 'openai';
import { SimpleModelRouter } from './model-router';
import { ProviderLlmClient } from './llm-client';

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

/** Used by vertical agents: system + user, fixed model. */
export async function callMainLLM(prompt: string): Promise<string>;
export async function callMainLLM(
  systemContent: string,
  userContent: string,
): Promise<string>;
export async function callMainLLM(
  promptOrSystem: string,
  userContent?: string,
): Promise<string> {
  const messages: Array<{ role: 'system' | 'user'; content: string }> =
    userContent !== undefined
      ? [
          { role: 'system', content: promptOrSystem },
          { role: 'user', content: userContent },
        ]
      : [
          {
            role: 'system',
            content: 'You are a helpful ecommerce & travel assistant.',
          },
          { role: 'user', content: promptOrSystem },
        ];
  const res = await getClient().chat.completions.create({
    model: 'gpt-4.1-mini',
    messages,
    temperature: 0.5,
    max_tokens: 512,
  });
  return res.choices[0].message.content ?? '';
}

const router = new SimpleModelRouter(new ProviderLlmClient());

export async function callMainLLMForSummary(
  prompt: string,
  mode: 'quick' | 'deep',
): Promise<string> {
  return router.summarize(prompt, mode);
}

export async function callMainLLMForPlanner(
  prompt: string,
  mode: 'quick' | 'deep',
): Promise<string> {
  return router.plan(prompt, mode);
}

export async function callMainLLMForCritique(prompt: string): Promise<string> {
  return router.critique(prompt);
}

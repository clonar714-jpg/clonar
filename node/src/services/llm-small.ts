
import OpenAI from 'openai';

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error('Missing OPENAI_API_KEY. Set it in node/.env or your environment.');
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}

export async function callSmallLLM(prompt: string): Promise<string> {
  const res = await getClient().chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: 'You are a JSON-only classifier/extractor.' },
      { role: 'user', content: prompt },
    ],
    temperature: 0,
  });
  return res.choices[0].message.content ?? '{}';
}

export interface CallSmallLlmJsonInput {
  system: string;
  user: string;
}

export async function callSmallLlmJson(input: CallSmallLlmJsonInput): Promise<string> {
  const res = await getClient().chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: input.system },
      { role: 'user', content: input.user },
    ],
    temperature: 0,
  });
  return res.choices[0].message.content ?? '{}';
}

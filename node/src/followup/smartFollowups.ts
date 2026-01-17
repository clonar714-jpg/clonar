

import OpenAI from 'openai';

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error('Missing OPENAI_API_KEY environment variable');
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}

export interface SmartFollowUpParams {
  query: string;
  answer: string;
  intent: string;
  brand?: string | null;
  category?: string | null;
  price?: string | null;
  city?: string | null;
  lastFollowUp?: string | null;
  parentQuery?: string | null;
  cards?: any[];
}


export async function generateSmartFollowUps(params: SmartFollowUpParams): Promise<string[]> {
  try {
    const { query, answer, intent, brand, category, price, city } = params;
    
    const contextParts: string[] = [];
    if (brand) contextParts.push(`Brand: ${brand}`);
    if (category) contextParts.push(`Category: ${category}`);
    if (price) contextParts.push(`Price range: ${price}`);
    if (city) contextParts.push(`City: ${city}`);
    
    const context = contextParts.length > 0 ? `\nContext: ${contextParts.join(', ')}` : '';
    
    const prompt = `Given the user's query and answer, generate 3-4 relevant follow-up questions.

User Query: ${query}
Intent: ${intent}${context}

Answer: ${answer.substring(0, 500)}${answer.length > 500 ? '...' : ''}

Return ONLY a JSON array of 3-4 follow-up questions:
["Question 1", "Question 2", "Question 3", "Question 4"]`;

    const response = await getClient().chat.completions.create({
      model: 'gpt-4o-mini',
      temperature: 0.7,
      max_tokens: 200,
      messages: [
        {
          role: 'system',
          content: 'You are a helpful assistant that generates relevant follow-up questions. Always return a valid JSON array.',
        },
        { role: 'user', content: prompt },
      ],
    });

    const content = response.choices[0]?.message?.content?.trim() || '[]';
    
    
    let jsonStr = content;
    const jsonMatch = content.match(/```(?:json)?\s*(\[[\s\S]*?\])\s*```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1];
    } else if (content.includes('[') && content.includes(']')) {
      const arrayMatch = content.match(/\[[\s\S]*?\]/);
      if (arrayMatch) {
        jsonStr = arrayMatch[0];
      }
    }

    try {
      const parsed = JSON.parse(jsonStr);
      if (Array.isArray(parsed)) {
        return parsed
          .filter((q: any) => typeof q === 'string' && q.trim().length > 0)
          .slice(0, 4)
          .map((q: string) => q.trim());
      }
    } catch (e) {
      console.warn('⚠️ Failed to parse smart follow-ups JSON:', e);
    }
  } catch (error: any) {
    console.warn('⚠️ Smart follow-ups generation failed:', error.message);
  }

  
  return [
    'Tell me more',
    'What else should I know?',
    'Any related information?',
  ];
}


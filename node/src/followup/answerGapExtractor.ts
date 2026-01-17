

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

export interface AnswerGaps {
  potentialFollowUps: string[];
}


export async function extractAnswerGaps(
  query: string,
  answer: string,
  cards: any[]
): Promise<AnswerGaps> {
  try {
    const prompt = `Given the user's query and the answer provided, identify 2-3 potential follow-up questions that would help the user explore aspects NOT fully covered in the answer.

User Query: ${query}

Answer: ${answer.substring(0, 1000)}${answer.length > 1000 ? '...' : ''}

Return ONLY a JSON array of 2-3 follow-up questions that explore gaps or missing information:
["Question 1", "Question 2", "Question 3"]`;

    const response = await getClient().chat.completions.create({
      model: 'gpt-4o-mini',
      temperature: 0.7,
      max_tokens: 150,
      messages: [
        {
          role: 'system',
          content: 'You are a helpful assistant that identifies information gaps in answers. Always return a valid JSON array with 2-3 questions.',
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
        const followUps = parsed
          .filter((q: any) => typeof q === 'string' && q.trim().length > 0)
          .slice(0, 3)
          .map((q: string) => q.trim());
        
        return {
          potentialFollowUps: followUps,
        };
      }
    } catch (e) {
      console.warn('⚠️ Failed to parse answer gaps JSON:', e);
    }
  } catch (error: any) {
    console.warn('⚠️ Answer gap extraction failed:', error.message);
  }

  return {
    potentialFollowUps: [],
  };
}


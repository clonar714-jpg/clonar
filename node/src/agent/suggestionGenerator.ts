/**
 * ✅ Structured Suggestion Generator using Zod schema
 * Matches the provided pattern with structured output
 */

import formatChatHistoryAsString from '../utils/formatHistory';
import { suggestionGeneratorPrompt } from './prompts/suggestions';
import { ChatTurnMessage } from './types';
import z from 'zod';

type SuggestionGeneratorInput = {
  chatHistory: ChatTurnMessage[];
};

const schema = z.object({
  suggestions: z
    .array(z.string())
    .describe('List of suggested questions or prompts'),
});

import BaseLLM from '../models/base/llm';

const generateSuggestions = async (
  input: SuggestionGeneratorInput,
  llm: BaseLLM<any>,
) => {
  const res = await llm.generateObject<typeof schema>({
    messages: [
      {
        role: 'system',
        content: suggestionGeneratorPrompt,
      },
      {
        role: 'user',
        content: `<chat_history>\n${formatChatHistoryAsString(input.chatHistory)}\n</chat_history>`,
      },
    ],
    schema,
  });

  // OpenAILLM.generateObject returns { object: T, additionalInfo?: ... }
  return res.object.suggestions;
};

export default generateSuggestions;


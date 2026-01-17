

import z from 'zod';


export type Model = {
  name: string;
  key: string;
};


export type ModelList = {
  embedding: Model[];
  chat: Model[];
};


export type ProviderMetadata = {
  name: string;
  key: string;
};


export type MinimalProvider = {
  id: string;
  name: string;
  chatModels: Model[];
  embeddingModels: Model[];
};


export type ModelWithProvider = {
  key: string;
  providerId: string;
};


export type Message = {
  role: 'user' | 'assistant' | 'system';
  content: string;
};


export type GenerateOptions = {
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  stopSequences?: string[];
  frequencyPenalty?: number;
  presencePenalty?: number;
};


export type Tool = {
  name: string;
  description: string;
  schema: z.ZodObject<any>;
};


export type ToolCall = {
  id: string;
  name: string;
  arguments: Record<string, any>;
};


export type GenerateTextInput = {
  messages: Message[];
  tools?: Tool[];
  options?: GenerateOptions;
};


export type GenerateTextOutput = {
  content: string;
  toolCalls: ToolCall[];
  additionalInfo?: Record<string, any>;
};


export type StreamTextOutput = {
  contentChunk: string;
  toolCallChunk: ToolCall[];
  additionalInfo?: Record<string, any>;
  done?: boolean;
};


export type GenerateObjectInput<T extends z.ZodTypeAny = z.ZodTypeAny> = {
  schema: T;
  messages: Message[];
  options?: GenerateOptions;
};


export type GenerateObjectOutput<T> = {
  object: T;
  additionalInfo?: Record<string, any>;
};


export type StreamObjectOutput<T> = {
  objectChunk: Partial<T>;
  additionalInfo?: Record<string, any>;
  done?: boolean;
};


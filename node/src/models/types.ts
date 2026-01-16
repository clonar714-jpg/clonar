/**
 * ✅ LLM Types: Types for BaseLLM interface
 * Matches the provided pattern
 */

import z from 'zod';

/**
 * Model information
 */
export type Model = {
  name: string;
  key: string;
};

/**
 * List of models (chat and embedding)
 * Note: Providers return this format, but MinimalProvider uses chatModels/embeddingModels
 */
export type ModelList = {
  embedding: Model[];
  chat: Model[];
};

/**
 * Provider metadata
 */
export type ProviderMetadata = {
  name: string;
  key: string;
};

/**
 * Minimal provider information for API responses
 */
export type MinimalProvider = {
  id: string;
  name: string;
  chatModels: Model[];
  embeddingModels: Model[];
};

/**
 * Model with provider reference
 */
export type ModelWithProvider = {
  key: string;
  providerId: string;
};

/**
 * Message format for LLM conversations
 */
export type Message = {
  role: 'user' | 'assistant' | 'system';
  content: string;
};

/**
 * Options for text generation
 */
export type GenerateOptions = {
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  stopSequences?: string[];
  frequencyPenalty?: number;
  presencePenalty?: number;
};

/**
 * Tool definition for function calling
 */
export type Tool = {
  name: string;
  description: string;
  schema: z.ZodObject<any>;
};

/**
 * Tool call from LLM
 */
export type ToolCall = {
  id: string;
  name: string;
  arguments: Record<string, any>;
};

/**
 * Input for text generation
 */
export type GenerateTextInput = {
  messages: Message[];
  tools?: Tool[];
  options?: GenerateOptions;
};

/**
 * Output from text generation
 */
export type GenerateTextOutput = {
  content: string;
  toolCalls: ToolCall[];
  additionalInfo?: Record<string, any>;
};

/**
 * Stream output chunk for text generation
 */
export type StreamTextOutput = {
  contentChunk: string;
  toolCallChunk: ToolCall[];
  additionalInfo?: Record<string, any>;
  done?: boolean;
};

/**
 * Input for structured object generation
 */
export type GenerateObjectInput<T extends z.ZodTypeAny = z.ZodTypeAny> = {
  schema: T;
  messages: Message[];
  options?: GenerateOptions;
};

/**
 * Output from structured object generation
 */
export type GenerateObjectOutput<T> = {
  object: T;
  additionalInfo?: Record<string, any>;
};

/**
 * Stream output chunk for structured object generation
 */
export type StreamObjectOutput<T> = {
  objectChunk: Partial<T>;
  additionalInfo?: Record<string, any>;
  done?: boolean;
};


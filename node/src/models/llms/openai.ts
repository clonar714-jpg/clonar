/**
 * ✅ OpenAILLM: OpenAI implementation of BaseLLM
 * Wraps OpenAI SDK for consistency with BaseLLM interface
 */

import z from 'zod';
import OpenAI from 'openai';
import { zodToJsonSchema } from 'zod-to-json-schema';
import BaseLLM from '../base/llm';
import {
  GenerateTextInput,
  GenerateTextOutput,
  StreamTextOutput,
  GenerateObjectInput,
  GenerateObjectOutput,
  StreamObjectOutput,
  ToolCall,
} from '../types';

/**
 * Configuration for OpenAI LLM
 */
export interface OpenAILLMConfig {
  model?: string; // e.g., 'gpt-4o-mini', 'gpt-4', 'gpt-3.5-turbo'
  apiKey?: string; // Optional, falls back to OPENAI_API_KEY env var
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
}

/**
 * OpenAI LLM implementation
 */
class OpenAILLM extends BaseLLM<OpenAILLMConfig> {
  private client: OpenAI;

  constructor(config: OpenAILLMConfig = {}) {
    super({
      model: config.model || 'gpt-4o-mini',
      apiKey: config.apiKey,
      temperature: config.temperature ?? 0.3,
      maxTokens: config.maxTokens ?? 800,
      topP: config.topP,
      frequencyPenalty: config.frequencyPenalty,
      presencePenalty: config.presencePenalty,
    });

    const apiKey = config.apiKey || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error('❌ Missing OpenAI API key. Provide apiKey in config or set OPENAI_API_KEY env var');
    }

    this.client = new OpenAI({ apiKey });
  }

  /**
   * Generate text from messages
   */
  async generateText(input: GenerateTextInput): Promise<GenerateTextOutput> {
    // Convert tools to OpenAI format if provided
    const tools = input.tools?.map((tool) => {
      // ✅ FIX: Convert Zod schema to JSON Schema format
      // ✅ FIX: Add type assertion to bypass TypeScript's deep type inference limit
      const jsonSchema = zodToJsonSchema(tool.schema, {
        target: 'openApi3',
        $refStrategy: 'none',
      }) as any;
      
      return {
        type: 'function' as const,
        function: {
          name: tool.name,
          description: tool.description,
          parameters: jsonSchema, // OpenAI expects JSON Schema format
        },
      };
    });

    const response = await this.client.chat.completions.create({
      model: this.config.model!,
      messages: input.messages.map((msg: any) => {
        // ✅ FIX: Include tool_calls for assistant messages and tool_call_id for tool messages
        const baseMessage: any = {
          role: msg.role,
          content: msg.content || null, // OpenAI requires null for empty content
        };
        
        // ✅ Include tool_calls if present (for assistant messages)
        if (msg.tool_calls) {
          baseMessage.tool_calls = msg.tool_calls.map((tc: any) => {
            // ✅ Handle both formats:
            // 1. Already in OpenAI format (from previous iteration): { id, type, function: { name, arguments: string } }
            // 2. Our custom format (from current iteration): { id, name, arguments: object }
            if (tc.function && tc.function.name) {
              // Already in OpenAI format - pass through as-is
              return {
                id: tc.id,
                type: tc.type || 'function',
                function: {
                  name: tc.function.name,
                  arguments: tc.function.arguments, // Already a string
                },
              };
            } else {
              // Our custom format - convert to OpenAI format
              return {
                id: tc.id,
                type: 'function',
                function: {
                  name: tc.name,
                  arguments: typeof tc.arguments === 'string' ? tc.arguments : JSON.stringify(tc.arguments),
                },
              };
            }
          });
        }
        
        // ✅ Include tool_call_id if present (for tool messages)
        if (msg.tool_call_id) {
          baseMessage.tool_call_id = msg.tool_call_id;
        }
        
        return baseMessage;
      }),
      tools: tools,
      temperature: input.options?.temperature ?? this.config.temperature,
      max_tokens: input.options?.maxTokens ?? this.config.maxTokens,
      top_p: input.options?.topP ?? this.config.topP,
      frequency_penalty: input.options?.frequencyPenalty ?? this.config.frequencyPenalty,
      presence_penalty: input.options?.presencePenalty ?? this.config.presencePenalty,
      stop: input.options?.stopSequences,
    });

    const choice = response.choices[0];
    const message = choice?.message;
    
    // Extract tool calls
    const toolCalls: ToolCall[] = (message?.tool_calls || [])
      .map((tc): ToolCall => {
        // ✅ FIX: Explicitly type as Record<string, any> to match ToolCall.arguments type
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(tc.function.arguments || '{}') as Record<string, any>;
        } catch {
          args = {};
        }

        return {
          id: tc.id,
          name: tc.function.name,
          arguments: args,
        };
      })
      .filter((tc: ToolCall) => {
        // HARD GUARANTEE: web_search must have queries
        if (tc.name === 'web_search') {
          return Array.isArray(tc.arguments?.queries) && tc.arguments.queries.length > 0;
        }
        return true;
      });

    return {
      content: message?.content || '',
      toolCalls,
      additionalInfo: {
        finishReason: choice?.finish_reason,
        usage: response.usage
          ? {
              promptTokens: response.usage.prompt_tokens,
              completionTokens: response.usage.completion_tokens,
              totalTokens: response.usage.total_tokens,
            }
          : undefined,
      },
    };
  }

  /**
   * Stream text generation from messages
   */
  async *streamText(
    input: GenerateTextInput,
  ): AsyncGenerator<StreamTextOutput> {
    // Convert tools to OpenAI format if provided
    const tools = input.tools?.map((tool) => {
      // ✅ FIX: Convert Zod schema to JSON Schema format
      const jsonSchema = zodToJsonSchema(tool.schema, {
        target: 'openApi3',
        $refStrategy: 'none',
      });
      
      return {
        type: 'function' as const,
        function: {
          name: tool.name,
          description: tool.description,
          parameters: jsonSchema as any, // OpenAI expects JSON Schema format
        },
      };
    });

    const stream = await this.client.chat.completions.create({
      model: this.config.model!,
      messages: input.messages.map((msg: any) => {
        // ✅ FIX: Include tool_calls for assistant messages and tool_call_id for tool messages
        const baseMessage: any = {
          role: msg.role,
          content: msg.content || null, // OpenAI requires null for empty content
        };
        
        // ✅ Include tool_calls if present (for assistant messages)
        if (msg.tool_calls) {
          baseMessage.tool_calls = msg.tool_calls.map((tc: any) => {
            // ✅ Handle both formats:
            // 1. Already in OpenAI format (from previous iteration): { id, type, function: { name, arguments: string } }
            // 2. Our custom format (from current iteration): { id, name, arguments: object }
            if (tc.function && tc.function.name) {
              // Already in OpenAI format - pass through as-is
              return {
                id: tc.id,
                type: tc.type || 'function',
                function: {
                  name: tc.function.name,
                  arguments: tc.function.arguments, // Already a string
                },
              };
            } else {
              // Our custom format - convert to OpenAI format
              return {
                id: tc.id,
                type: 'function',
                function: {
                  name: tc.name,
                  arguments: typeof tc.arguments === 'string' ? tc.arguments : JSON.stringify(tc.arguments),
                },
              };
            }
          });
        }
        
        // ✅ Include tool_call_id if present (for tool messages)
        if (msg.tool_call_id) {
          baseMessage.tool_call_id = msg.tool_call_id;
        }
        
        return baseMessage;
      }),
      tools: tools,
      stream: true,
      temperature: input.options?.temperature ?? this.config.temperature,
      max_tokens: input.options?.maxTokens ?? this.config.maxTokens,
      top_p: input.options?.topP ?? this.config.topP,
      frequency_penalty: input.options?.frequencyPenalty ?? this.config.frequencyPenalty,
      presence_penalty: input.options?.presencePenalty ?? this.config.presencePenalty,
      stop: input.options?.stopSequences,
    });

    let accumulatedToolCalls: Map<string, ToolCall> = new Map();

    for await (const chunk of stream) {
      const delta = chunk.choices[0]?.delta;
      const content = delta?.content || '';
      
      // Handle tool calls
      const toolCallChunk: ToolCall[] = [];
      if (delta?.tool_calls) {
        for (const tc of delta.tool_calls) {
          if (tc.id) {
            if (!accumulatedToolCalls.has(tc.id)) {
              accumulatedToolCalls.set(tc.id, {
                id: tc.id,
                name: tc.function?.name || '',
                arguments: {},
              });
            }
            
            const toolCall = accumulatedToolCalls.get(tc.id)!;
            if (tc.function?.name) {
              toolCall.name = tc.function.name;
            }
            if (tc.function?.arguments) {
              try {
                const args = JSON.parse(tc.function.arguments);
                toolCall.arguments = { ...toolCall.arguments, ...args };
              } catch {
                // Partial JSON, continue accumulating
              }
            }
            
            toolCallChunk.push({ ...toolCall });
          }
        }
      }

      if (content || toolCallChunk.length > 0) {
        yield {
          contentChunk: content,
          toolCallChunk,
        };
      }

      // Check if done
      if (chunk.choices[0]?.finish_reason) {
        yield {
          contentChunk: '',
          toolCallChunk: [],
          done: true,
          additionalInfo: {
            finishReason: chunk.choices[0].finish_reason,
          },
        };
        break;
      }
    }
  }

  /**
   * Generate a structured object from messages using a Zod schema
   */
  async generateObject<T extends z.ZodTypeAny>(
    input: GenerateObjectInput<T>,
  ): Promise<GenerateObjectOutput<z.infer<T>>> {
    const response = await this.client.chat.completions.create({
      model: this.config.model!,
      messages: input.messages.map((msg) => ({
        role: msg.role,
        content: msg.content,
      })),
      response_format: { type: 'json_object' },
      temperature: input.options?.temperature ?? this.config.temperature,
      max_tokens: input.options?.maxTokens ?? this.config.maxTokens,
      top_p: input.options?.topP ?? this.config.topP,
      frequency_penalty: input.options?.frequencyPenalty ?? this.config.frequencyPenalty,
      presence_penalty: input.options?.presencePenalty ?? this.config.presencePenalty,
      stop: input.options?.stopSequences,
    });

    const content = response.choices[0]?.message?.content || '{}';
    let parsed: any;

    try {
      parsed = JSON.parse(content);
    } catch (error) {
      console.warn('Failed to parse JSON from OpenAI response:', error);
      parsed = {};
    }

    // Validate against schema
    const result = input.schema.safeParse(parsed);
    if (!result.success) {
      console.warn('OpenAI response did not match schema:', result.error);
      // Return a default object that matches the schema
      parsed = input.schema.parse({});
    } else {
      parsed = result.data;
    }

    return {
      object: parsed as z.infer<T>,
      additionalInfo: {
        finishReason: response.choices[0]?.finish_reason,
        usage: response.usage
          ? {
              promptTokens: response.usage.prompt_tokens,
              completionTokens: response.usage.completion_tokens,
              totalTokens: response.usage.total_tokens,
            }
          : undefined,
      },
    };
  }

  /**
   * Stream structured object generation
   * Note: OpenAI doesn't natively support streaming JSON objects,
   * so this accumulates chunks and yields partial objects
   */
  async *streamObject<T extends z.ZodTypeAny>(
    input: GenerateObjectInput<T>,
  ): AsyncGenerator<StreamObjectOutput<z.infer<T>>> {
    const stream = await this.client.chat.completions.create({
      model: this.config.model!,
      messages: input.messages.map((msg) => ({
        role: msg.role,
        content: msg.content,
      })),
      response_format: { type: 'json_object' },
      stream: true,
      temperature: input.options?.temperature ?? this.config.temperature,
      max_tokens: input.options?.maxTokens ?? this.config.maxTokens,
      top_p: input.options?.topP ?? this.config.topP,
      frequency_penalty: input.options?.frequencyPenalty ?? this.config.frequencyPenalty,
      presence_penalty: input.options?.presencePenalty ?? this.config.presencePenalty,
      stop: input.options?.stopSequences,
    });

    let buffer = '';

    for await (const chunk of stream) {
      const content = chunk.choices[0]?.delta?.content || '';
      if (content) {
        buffer += content;

        // Try to parse partial JSON
        try {
          const parsed = JSON.parse(buffer);
          yield {
            objectChunk: parsed as Partial<z.infer<T>>,
          };
        } catch {
          // JSON is incomplete, continue accumulating
        }
      }

      // Check if done
      if (chunk.choices[0]?.finish_reason) {
        // Final parse of complete JSON
        try {
          const parsed = JSON.parse(buffer);
          yield {
            objectChunk: parsed as Partial<z.infer<T>>,
            done: true,
            additionalInfo: {
              finishReason: chunk.choices[0].finish_reason,
            },
          };
        } catch (error) {
          console.warn('Failed to parse final JSON from stream:', error);
          yield {
            objectChunk: {} as Partial<z.infer<T>>,
            done: true,
          };
        }
        break;
      }
    }
  }
}

export default OpenAILLM;


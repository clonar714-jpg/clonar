

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


export interface OpenAILLMConfig {
  model?: string; 
  apiKey?: string; 
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
}


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

  async generateText(input: GenerateTextInput): Promise<GenerateTextOutput> {
    
    const tools = input.tools?.map((tool) => {
      
      const jsonSchema = zodToJsonSchema(tool.schema, {
        target: 'openApi3',
        $refStrategy: 'none',
      }) as any;
      
      return {
        type: 'function' as const,
        function: {
          name: tool.name,
          description: tool.description,
          parameters: jsonSchema, 
        },
      };
    });

    const response = await this.client.chat.completions.create({
      model: this.config.model!,
      messages: input.messages.map((msg: any) => {
       
        const baseMessage: any = {
          role: msg.role,
          content: msg.content || null, 
        };
        
        
        if (msg.tool_calls) {
          baseMessage.tool_calls = msg.tool_calls.map((tc: any) => {
            
            if (tc.function && tc.function.name) {
              
              return {
                id: tc.id,
                type: tc.type || 'function',
                function: {
                  name: tc.function.name,
                  arguments: tc.function.arguments, 
                },
              };
            } else {
              
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
    
    
    const toolCalls: ToolCall[] = (message?.tool_calls || [])
      .map((tc): ToolCall => {
        
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
          parameters: jsonSchema as any, 
        },
      };
    });

    const stream = await this.client.chat.completions.create({
      model: this.config.model!,
      messages: input.messages.map((msg: any) => {
        
        const baseMessage: any = {
          role: msg.role,
          content: msg.content || null, 
        };
        
        
        if (msg.tool_calls) {
          baseMessage.tool_calls = msg.tool_calls.map((tc: any) => {
            
            if (tc.function && tc.function.name) {
              
              return {
                id: tc.id,
                type: tc.type || 'function',
                function: {
                  name: tc.function.name,
                  arguments: tc.function.arguments, 
                },
              };
            } else {
              
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

    
    const result = input.schema.safeParse(parsed);
    if (!result.success) {
      console.warn('OpenAI response did not match schema:', result.error);
      // Re-parse with partial response so schema defaults fill missing fields
      const fallback = input.schema.safeParse(parsed ?? {});
      parsed = fallback.success ? fallback.data : input.schema.parse({});
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

        
        try {
          const parsed = JSON.parse(buffer);
          yield {
            objectChunk: parsed as Partial<z.infer<T>>,
          };
        } catch {
          
        }
      }

      
      if (chunk.choices[0]?.finish_reason) {
        
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




import z from 'zod';
import {
  GenerateObjectInput,
  GenerateObjectOutput,
  GenerateOptions,
  GenerateTextInput,
  GenerateTextOutput,
  StreamObjectOutput,
  StreamTextOutput,
} from '../types';


abstract class BaseLLM<CONFIG = any> {
  constructor(protected config: CONFIG) {}

  /**
   * Generate text from messages
   * @param input Text generation input with messages, tools, and options
   * @returns Promise resolving to generated text output
   */
  abstract generateText(input: GenerateTextInput): Promise<GenerateTextOutput>;

  /**
   * Stream text generation from messages
   * @param input Text generation input with messages, tools, and options
   * @returns Async generator yielding stream text output chunks
   */
  abstract streamText(
    input: GenerateTextInput,
  ): AsyncGenerator<StreamTextOutput>;

  /**
   * Generate a structured object from messages using a Zod schema
   * @param input Object generation input with schema, messages, and options
   * @returns Promise resolving to object output with the inferred type
   */
  abstract generateObject<T extends z.ZodTypeAny>(
    input: GenerateObjectInput<T>,
  ): Promise<GenerateObjectOutput<z.infer<T>>>;

  /**
   * Stream structured object generation from messages using a Zod schema
   * @param input Object generation input with schema, messages, and options
   * @returns Async generator yielding stream object output chunks
   */
  abstract streamObject<T extends z.ZodTypeAny>(
    input: GenerateObjectInput<T>,
  ): AsyncGenerator<StreamObjectOutput<z.infer<T>>>;
}

export default BaseLLM;


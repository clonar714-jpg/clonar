/**
 * ✅ Provider Registry: Maps provider types to provider constructors
 * Central registry for all available model providers
 */

import { ProviderConstructor } from '../base/provider';
import OpenAIProvider from './openai';

/**
 * Registry of available provider types
 * Maps provider type string to provider constructor
 */
export const providers: Record<string, ProviderConstructor<any>> = {
  openai: OpenAIProvider,
  // Add more providers here as they are implemented
  // anthropic: AnthropicProvider,
  // google: GoogleProvider,
};


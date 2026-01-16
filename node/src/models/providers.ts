/**
 * ✅ Model Providers UI Config
 * Returns UI configuration sections for model providers
 */

import { ModelProviderUISection } from '../config/types';

/**
 * Get UI config sections for model providers
 * This can be extended to support multiple provider types
 */
export function getModelProvidersUIConfigSection(): ModelProviderUISection[] {
  // Example: OpenAI provider config
  const openAIConfig: ModelProviderUISection = {
    name: 'OpenAI',
    key: 'openai',
    fields: [
      {
        name: 'OpenAI API Key',
        key: 'apiKey',
        type: 'password',
        required: true,
        description: 'Your OpenAI API key',
        placeholder: 'sk-...',
        scope: 'server',
        env: 'OPENAI_API_KEY',
      },
    ],
  };

  // Add more providers as needed
  // Example: Anthropic, Google, etc.

  return [openAIConfig];
}


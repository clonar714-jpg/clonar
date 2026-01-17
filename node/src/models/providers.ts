

import { ModelProviderUISection } from '../config/types';


export function getModelProvidersUIConfigSection(): ModelProviderUISection[] {
  
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


  return [openAIConfig];
}


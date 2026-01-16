/**
 * ✅ OpenAIProvider: OpenAI implementation of BaseModelProvider
 * Provides OpenAI LLM and embedding models
 */

import BaseModelProvider from '../base/provider';
import { ModelList, ProviderMetadata } from '../types';
import { UIConfigField } from '../../config/types';
import OpenAILLM from '../llms/openai';
import OpenAIEmbedding from '../embeddings/openai';
import z from 'zod';

/**
 * OpenAI provider configuration
 */
export interface OpenAIProviderConfig {
  apiKey: string;
}

/**
 * OpenAI provider implementation
 */
class OpenAIProvider extends BaseModelProvider<OpenAIProviderConfig> {
  /**
   * Get default models
   */
  async getDefaultModels(): Promise<ModelList> {
    return {
      chat: [
        {
          key: 'gpt-4o-mini',
          name: 'GPT-4o Mini',
        },
        {
          key: 'gpt-4o',
          name: 'GPT-4o',
        },
      ],
      embedding: [
        {
          key: 'text-embedding-3-small',
          name: 'Text Embedding 3 Small',
        },
        {
          key: 'text-embedding-3-large',
          name: 'Text Embedding 3 Large',
        },
      ],
    };
  }

  /**
   * Get full model list (same as defaults for OpenAI)
   */
  async getModelList(): Promise<ModelList> {
    return this.getDefaultModels();
  }

  /**
   * Load a chat model
   */
  async loadChatModel(modelName: string): Promise<OpenAILLM> {
    return new OpenAILLM({
      model: modelName,
      apiKey: this.config.apiKey,
    });
  }

  /**
   * Load an embedding model
   */
  async loadEmbeddingModel(modelName: string): Promise<OpenAIEmbedding> {
    return new OpenAIEmbedding({
      model: modelName,
      apiKey: this.config.apiKey,
    });
  }

  /**
   * Get UI configuration fields
   */
  static getProviderConfigFields(): UIConfigField[] {
    return [
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
    ];
  }

  /**
   * Get provider metadata
   */
  static getProviderMetadata(): ProviderMetadata {
    return {
      key: 'openai',
      name: 'OpenAI',
    };
  }

  /**
   * Parse and validate configuration
   */
  static parseAndValidate(raw: any): OpenAIProviderConfig {
    const schema = z.object({
      apiKey: z.string().min(1, 'API key is required'),
    });

    const result = schema.safeParse(raw);
    if (!result.success) {
      throw new Error(`Invalid OpenAI configuration: ${result.error.message}`);
    }

    return result.data;
  }
}

export default OpenAIProvider;


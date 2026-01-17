

import { ModelList, ProviderMetadata } from '../types';
import { UIConfigField } from '../../config/types';
import BaseLLM from './llm';
import BaseEmbedding from './embedding';


abstract class BaseModelProvider<CONFIG = any> {
  constructor(
    protected id: string,
    protected name: string,
    protected config: CONFIG,
  ) {}

  /**
   * Get default models for this provider
   * @returns Promise resolving to list of default models
   */
  abstract getDefaultModels(): Promise<ModelList>;

  /**
   * Get full list of available models for this provider
   * @returns Promise resolving to list of all available models
   */
  abstract getModelList(): Promise<ModelList>;

  /**
   * Load a chat model by name
   * @param modelName Name/key of the model to load
   * @returns Promise resolving to BaseLLM instance
   */
  abstract loadChatModel(modelName: string): Promise<BaseLLM<any>>;

  /**
   * Load an embedding model by name
   * @param modelName Name/key of the model to load
   * @returns Promise resolving to BaseEmbedding instance
   */
  abstract loadEmbeddingModel(modelName: string): Promise<BaseEmbedding<any>>;

 
  static getProviderConfigFields(): UIConfigField[] {
    throw new Error('Method not implemented.');
  }

 
  static getProviderMetadata(): ProviderMetadata {
    throw new Error('Method not Implemented.');
  }

 
  static parseAndValidate(raw: any): any {
    throw new Error('Method not Implemented.');
  }
}


export type ProviderConstructor<CONFIG = any> = {
  new (id: string, name: string, config: CONFIG): BaseModelProvider<CONFIG>;
  parseAndValidate(raw: any): CONFIG;
  getProviderConfigFields: () => UIConfigField[];
  getProviderMetadata: () => ProviderMetadata;
};

/**
 * Create a provider instance with validation
 * @param Provider Provider class constructor
 * @param id Provider instance ID
 * @param name Provider instance name
 * @param rawConfig Raw configuration to parse and validate
 * @returns Instance of the provider
 */
export const createProviderInstance = <P extends ProviderConstructor<any>>(
  Provider: P,
  id: string,
  name: string,
  rawConfig: unknown,
): InstanceType<P> => {
  const cfg = Provider.parseAndValidate(rawConfig);
  return new Provider(id, name, cfg) as InstanceType<P>;
};

export default BaseModelProvider;


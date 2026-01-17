

import BaseEmbedding from '../base/embedding';
import { Chunk } from '../../agent/types';
import { getEmbeddings } from '../../embeddings/embeddingClient';


export interface OpenAIEmbeddingConfig {
  model?: string; 
  apiKey?: string; 
}


class OpenAIEmbedding extends BaseEmbedding<OpenAIEmbeddingConfig> {
  constructor(config: OpenAIEmbeddingConfig = {}) {
    super({
      model: config.model || 'text-embedding-3-small',
      apiKey: config.apiKey,
    });
  }

  
  async embedText(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) {
      return [];
    }

    
    return await getEmbeddings(texts);
  }

 
  async embedChunks(chunks: Chunk[]): Promise<number[][]> {
    if (chunks.length === 0) {
      return [];
    }

    
    const texts = chunks.map((chunk) => chunk.content || '');

    
    return await this.embedText(texts);
  }
}

export default OpenAIEmbedding;


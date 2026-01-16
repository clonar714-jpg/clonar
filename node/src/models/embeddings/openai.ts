/**
 * ✅ OpenAIEmbedding: OpenAI implementation of BaseEmbedding
 * Wraps the existing embeddingClient for consistency
 */

import BaseEmbedding from '../base/embedding';
import { Chunk } from '../../agent/types';
import { getEmbeddings } from '../../embeddings/embeddingClient';

/**
 * Configuration for OpenAI embedding model
 */
export interface OpenAIEmbeddingConfig {
  model?: string; // e.g., 'text-embedding-3-small', 'text-embedding-3-large'
  apiKey?: string; // Optional, falls back to OPENAI_API_KEY env var
}

/**
 * OpenAI embedding implementation
 */
class OpenAIEmbedding extends BaseEmbedding<OpenAIEmbeddingConfig> {
  constructor(config: OpenAIEmbeddingConfig = {}) {
    super({
      model: config.model || 'text-embedding-3-small',
      apiKey: config.apiKey,
    });
  }

  /**
   * Embed an array of text strings using OpenAI
   */
  async embedText(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) {
      return [];
    }

    // Use existing embeddingClient which handles caching and batching
    return await getEmbeddings(texts);
  }

  /**
   * Embed an array of Chunk objects
   * Extracts content from each chunk and embeds it
   */
  async embedChunks(chunks: Chunk[]): Promise<number[][]> {
    if (chunks.length === 0) {
      return [];
    }

    // Extract content from chunks
    const texts = chunks.map((chunk) => chunk.content || '');

    // Use embedText to handle the actual embedding
    return await this.embedText(texts);
  }
}

export default OpenAIEmbedding;


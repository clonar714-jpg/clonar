/**
 * ✅ BaseEmbedding: Abstract base class for embedding models
 * Matches the provided pattern for extensibility
 */

import { Chunk } from '../../agent/types';

/**
 * Abstract base class for embedding models
 * Provides a consistent interface for different embedding providers
 */
abstract class BaseEmbedding<CONFIG = any> {
  constructor(protected config: CONFIG) {}

  /**
   * Embed an array of text strings
   * @param texts Array of text strings to embed
   * @returns Promise resolving to array of embedding vectors
   */
  abstract embedText(texts: string[]): Promise<number[][]>;

  /**
   * Embed an array of Chunk objects
   * Extracts content from chunks and embeds them
   * @param chunks Array of Chunk objects to embed
   * @returns Promise resolving to array of embedding vectors
   */
  abstract embedChunks(chunks: Chunk[]): Promise<number[][]>;
}

export default BaseEmbedding;


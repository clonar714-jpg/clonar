// node/src/services/providers/web/simple-embedder.ts
// Stub: deterministic pseudo-embedding. Replace with real API (e.g. OpenAI embeddings) in production.

import type { Embedder, Embedding } from '../retrieval-vector-utils';

export class SimpleEmbedder implements Embedder {
  private dim: number;

  constructor(dim = 64) {
    this.dim = dim;
  }

  async embed(text: string): Promise<Embedding> {
    const tokens = text.toLowerCase().split(/\s+/g).filter(Boolean);
    const vec = new Array(this.dim).fill(0);

    for (const token of tokens) {
      let hash = 0;
      for (let i = 0; i < token.length; i++) {
        hash = (hash * 31 + token.charCodeAt(i)) >>> 0;
      }
      const idx = hash % this.dim;
      vec[idx] += 1;
    }

    const norm = Math.sqrt(vec.reduce((s, x) => s + x * x, 0));
    if (norm === 0) return vec;
    return vec.map((x) => x / norm);
  }
}

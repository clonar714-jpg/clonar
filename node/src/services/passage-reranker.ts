
import type { Embedder } from './providers/retrieval-vector-utils';
import { cosineSimilarity } from './providers/retrieval-vector-utils';
import type { RetrievedChunk, PassageReranker } from './retrieval-router';

export class SemanticPassageReranker implements PassageReranker {
  constructor(private readonly embedder: Embedder) {}

  async rerank(query: string, chunks: RetrievedChunk[]): Promise<RetrievedChunk[]> {
    if (chunks.length === 0) return [];
    const q = query.trim() || ' ';
    const queryEmb = await this.embedder.embed(q);
    const texts = chunks.map((c) => ((c.title ? c.title + ' ' : '') + c.text).trim() || c.id);
    const embeddings = await Promise.all(texts.map((t) => this.embedder.embed(t)));
    const scored = chunks.map((chunk, i) => ({
      chunk,
      score: cosineSimilarity(queryEmb, embeddings[i]),
    }));
    scored.sort((a, b) => b.score - a.score);
    return scored.map((s) => ({ ...s.chunk, score: s.score }));
  }
}

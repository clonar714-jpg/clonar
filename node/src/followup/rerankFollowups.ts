

import { getEmbedding, cosine } from '../embeddings/embeddingClient';

export interface RankedFollowUp {
  candidate: string;
  score: number;
}


export async function rerankFollowUps(
  query: string,
  candidates: string[],
  topK: number,
  answerSummary: string,
  recentFollowups: string[]
): Promise<RankedFollowUp[]> {
  if (candidates.length === 0) {
    return [];
  }

  try {
    
    const context = `${query} ${answerSummary}`;
    const contextEmbedding = await getEmbedding(context);

    
    const scored: RankedFollowUp[] = [];
    
    for (const candidate of candidates) {
      try {
        const candidateEmbedding = await getEmbedding(candidate);
        const similarity = cosine(contextEmbedding, candidateEmbedding);
        
        
        let noveltyPenalty = 0;
        for (const recent of recentFollowups.slice(-3)) {
          const recentEmbedding = await getEmbedding(recent);
          const recentSimilarity = cosine(candidateEmbedding, recentEmbedding);
          if (recentSimilarity > 0.85) {
            noveltyPenalty += 0.2;
          }
        }
        
        const finalScore = Math.max(0, similarity - noveltyPenalty);
        scored.push({
          candidate,
          score: finalScore,
        });
      } catch (error) {
        
        scored.push({
          candidate,
          score: 0.5,
        });
      }
    }

    
    return scored
      .sort((a, b) => b.score - a.score)
      .slice(0, topK);
  } catch (error) {
    console.warn('⚠️ Reranking failed, using default scores:', error);
    
    return candidates.map((candidate) => ({
      candidate,
      score: 0.5,
    }));
  }
}


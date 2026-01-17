

export interface ScoringFactors {
  embeddingScore: number;
  behaviorScore: number;
  stageMatch: number;
  noveltyScore: number;
  gapMatch: number;
}


export function scoreFollowup(factors: ScoringFactors): number {
  const {
    embeddingScore,
    behaviorScore,
    stageMatch,
    noveltyScore,
    gapMatch,
  } = factors;

  
  const weights = {
    embedding: 0.35,    
    behavior: 0.20,     
    stage: 0.15,        
    novelty: 0.15,      
    gap: 0.15,          
  };

  return (
    embeddingScore * weights.embedding +
    behaviorScore * weights.behavior +
    stageMatch * weights.stage +
    noveltyScore * weights.novelty +
    gapMatch * weights.gap
  );
}


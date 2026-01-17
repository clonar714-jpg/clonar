

export interface AnswerCoverage {
  comparison: boolean;
  price: boolean;
  durability: boolean;
  useCase: boolean;
}


export function detectAnswerCoverage(answer: string): AnswerCoverage {
  const lower = answer.toLowerCase();
  
  return {
    comparison: /compare|versus|vs|alternative|difference|better|worse/i.test(lower),
    price: /\$|price|cost|budget|cheap|expensive|affordable|under|over/i.test(lower),
    durability: /durable|long-term|quality|last|endurance|reliable|sturdy/i.test(lower),
    useCase: /for running|for travel|for work|use case|purpose|suitable for|ideal for/i.test(lower),
  };
}


/**
 * ✅ Attribute Extractor: Extract purpose, style, attributes from answer
 */

export interface ExtractedAttributes {
  purpose?: string;
  attribute?: string;
  style?: 'budget' | 'premium';
}

/**
 * Extract attributes from answer text
 */
export function extractAttributes(answer: string): ExtractedAttributes {
  const lower = answer.toLowerCase();
  const attrs: ExtractedAttributes = {};

  // Extract purpose/use case
  const purposePatterns = [
    /(?:for|suitable for|ideal for|best for)\s+([a-z\s]+?)(?:\.|,|$)/i,
    /(?:running|travel|work|gaming|photography|video editing)/i,
  ];
  
  for (const pattern of purposePatterns) {
    const match = answer.match(pattern);
    if (match) {
      attrs.purpose = match[1]?.trim() || match[0];
      break;
    }
  }

  // Extract style (budget/premium)
  if (/budget|cheap|affordable|economy|low-cost/i.test(lower)) {
    attrs.style = 'budget';
  } else if (/premium|luxury|high-end|expensive|top-tier/i.test(lower)) {
    attrs.style = 'premium';
  }

  // Extract attribute (lightweight, durable, etc.)
  const attributePatterns = [
    /(lightweight|durable|waterproof|wireless|bluetooth|4k|hd)/i,
  ];
  
  for (const pattern of attributePatterns) {
    const match = answer.match(pattern);
    if (match) {
      attrs.attribute = match[1];
      break;
    }
  }

  return attrs;
}


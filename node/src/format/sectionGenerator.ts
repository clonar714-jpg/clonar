// ✅ PHASE 8: Section Generator
// Generates structured sections for responses

interface Section {
  title: string;
  content: string | string[];
  type: "overview" | "keyPoints" | "tips" | "prosCons" | "whenToVisit" | "summary";
}

/**
 * Generate sections from answer text and context
 * @param answerText - The LLM-generated answer
 * @param intent - The detected intent
 * @param cards - The cards/results for context
 * @returns Array of sections
 */
export function generateSections(
  answerText: string,
  intent: string,
  cards?: any[]
): Section[] {
  const sections: Section[] = [];
  const lowerAnswer = answerText.toLowerCase();

  // ✅ Overview section (always first)
  if (answerText.length > 100) {
    const overview = extractOverview(answerText);
    if (overview) {
      sections.push({
        title: "Overview",
        content: overview,
        type: "overview",
      });
    }
  }

  // ✅ Key Points section
  const keyPoints = extractKeyPoints(answerText);
  if (keyPoints.length > 0) {
    sections.push({
      title: "Key Points",
      content: keyPoints,
      type: "keyPoints",
    });
  }

  // ✅ Tips section (for places, hotels, restaurants)
  if (["places", "hotels", "restaurants"].includes(intent)) {
    const tips = extractTips(answerText);
    if (tips.length > 0) {
      sections.push({
        title: "Tips",
        content: tips,
        type: "tips",
      });
    }
  }

  // ✅ Pros/Cons section (for shopping, hotels)
  if (["shopping", "hotels"].includes(intent)) {
    const prosCons = extractProsCons(answerText);
    if (prosCons.pros.length > 0 || prosCons.cons.length > 0) {
      sections.push({
        title: "Pros & Cons",
        content: `Pros: ${prosCons.pros.join("; ")}\nCons: ${prosCons.cons.join("; ")}`,
        type: "prosCons",
      });
    }
  }

  // ✅ When to Visit section (for places, hotels)
  if (["places", "hotels"].includes(intent)) {
    const whenToVisit = extractWhenToVisit(answerText);
    if (whenToVisit) {
      sections.push({
        title: "When to Visit",
        content: whenToVisit,
        type: "whenToVisit",
      });
    }
  }

  // ✅ Summary Bullets section
  const summaryBullets = extractSummaryBullets(answerText);
  if (summaryBullets.length > 0) {
    sections.push({
      title: "Summary",
      content: summaryBullets,
      type: "summary",
    });
  }

  return sections;
}

/**
 * Extract overview (first paragraph or first 200 chars)
 */
function extractOverview(text: string): string | null {
  const paragraphs = text.split(/\n\n+/).filter(p => p.trim().length > 0);
  if (paragraphs.length > 0) {
    const first = paragraphs[0].trim();
    if (first.length > 50) {
      return first.substring(0, 300);
    }
  }
  return text.substring(0, 200);
}

/**
 * Extract key points (numbered lists, bullet points, or "key" mentions)
 */
function extractKeyPoints(text: string): string[] {
  const points: string[] = [];

  // Extract numbered lists
  const numberedMatches = text.matchAll(/\d+\.\s*([^\n]+)/g);
  for (const match of numberedMatches) {
    if (match[1].trim().length > 10) {
      points.push(match[1].trim());
    }
  }

  // Extract bullet points
  const bulletMatches = text.matchAll(/[-•*]\s*([^\n]+)/g);
  for (const match of bulletMatches) {
    if (match[1].trim().length > 10 && points.length < 5) {
      points.push(match[1].trim());
    }
  }

  // Extract sentences with "key" or "important"
  if (points.length === 0) {
    const sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 20);
    for (const sentence of sentences) {
      if ((sentence.toLowerCase().includes("key") ||
           sentence.toLowerCase().includes("important") ||
           sentence.toLowerCase().includes("notable")) &&
          points.length < 5) {
        points.push(sentence.trim());
      }
    }
  }

  return points.slice(0, 5); // Max 5 key points
}

/**
 * Extract tips (sentences with "tip", "recommend", "suggest")
 */
function extractTips(text: string): string[] {
  const tips: string[] = [];
  const sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 20);

  for (const sentence of sentences) {
    const lower = sentence.toLowerCase();
    if ((lower.includes("tip") ||
         lower.includes("recommend") ||
         lower.includes("suggest") ||
         lower.includes("should") ||
         lower.includes("best to")) &&
        tips.length < 5) {
      tips.push(sentence.trim());
    }
  }

  return tips;
}

/**
 * Extract pros and cons
 */
function extractProsCons(text: string): { pros: string[]; cons: string[] } {
  const pros: string[] = [];
  const cons: string[] = [];
  const lower = text.toLowerCase();

  // Extract pros (positive words)
  const proPatterns = [
    /\b(advantage|benefit|pro|positive|good|great|excellent|amazing|wonderful)\b[^.!?]*[.!?]/gi,
  ];

  // Extract cons (negative words)
  const conPatterns = [
    /\b(disadvantage|drawback|con|negative|bad|poor|limited|issue|problem)\b[^.!?]*[.!?]/gi,
  ];

  for (const pattern of proPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[0].trim().length > 20 && pros.length < 3) {
        pros.push(match[0].trim());
      }
    }
  }

  for (const pattern of conPatterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      if (match[0].trim().length > 20 && cons.length < 3) {
        cons.push(match[0].trim());
      }
    }
  }

  return { pros, cons };
}

/**
 * Extract "when to visit" information
 */
function extractWhenToVisit(text: string): string | null {
  const lower = text.toLowerCase();
  
  // Look for time-related phrases
  const timePatterns = [
    /\b(best time|when to visit|peak season|off season|weather|climate)\b[^.!?]*[.!?]/i,
    /\b(spring|summer|fall|winter|autumn|dry season|wet season|monsoon)\b[^.!?]*[.!?]/i,
  ];

  for (const pattern of timePatterns) {
    const match = text.match(pattern);
    if (match) {
      // Extract the full sentence
      const sentences = text.split(/[.!?]+/);
      for (const sentence of sentences) {
        if (pattern.test(sentence)) {
          return sentence.trim();
        }
      }
    }
  }

  return null;
}

/**
 * Extract summary bullets (final summary sentences)
 */
function extractSummaryBullets(text: string): string[] {
  const bullets: string[] = [];
  
  // Take last 3-5 sentences as summary
  const sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 20);
  const summarySentences = sentences.slice(-5);
  
  for (const sentence of summarySentences) {
    if (sentence.trim().length > 30 && bullets.length < 5) {
      bullets.push(sentence.trim());
    }
  }

  return bullets;
}


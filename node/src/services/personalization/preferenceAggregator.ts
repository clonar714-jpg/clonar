

import { getRecentSignals, updateUserPreferences, getUserPreferences } from "./preferenceStorage";
import { UserPreferences } from "./preferenceStorage";

interface StyleConfidence {
  style: string;
  confidence: number;
}


export async function aggregateUserPreferences(userId: string): Promise<UserPreferences | null> {
  try {
    
    const signals = await getRecentSignals(userId, 50);
    
    if (signals.length < 3) {
      
      console.log(`ℹ️ Not enough signals for user ${userId} (${signals.length} < 3)`);
      return null;
    }

   
    const styleCounts: Record<string, number> = {};
    const priceRanges: Array<{ min?: number; max?: number }> = [];
    const brandCounts: Record<string, number> = {};
    const categoryStyleCounts: Record<string, Record<string, number>> = {};
    const categoryRatingCounts: Record<string, number[]> = {};

    signals.forEach(signal => {
      
      signal.style_keywords?.forEach(style => {
        styleCounts[style] = (styleCounts[style] || 0) + 1;
        
       
        if (signal.intent) {
          if (!categoryStyleCounts[signal.intent]) {
            categoryStyleCounts[signal.intent] = {};
          }
          categoryStyleCounts[signal.intent][style] = 
            (categoryStyleCounts[signal.intent][style] || 0) + 1;
        }
      });

      
      signal.price_mentions?.forEach(mention => {
        const range = parsePriceMention(mention);
        if (range) priceRanges.push(range);
      });

      
      signal.brand_mentions?.forEach(brand => {
        brandCounts[brand] = (brandCounts[brand] || 0) + 1;
      });

      
      if (signal.intent && signal.rating_mentions) {
        signal.rating_mentions.forEach(rating => {
          const ratingNum = parseRating(rating);
          if (ratingNum) {
            if (!categoryRatingCounts[signal.intent]) {
              categoryRatingCounts[signal.intent] = [];
            }
            categoryRatingCounts[signal.intent].push(ratingNum);
          }
        });
      }
    });

   
    const totalSignals = signals.length;
    const threshold = totalSignals * 0.3;

    const styleConfidences: StyleConfidence[] = Object.entries(styleCounts)
      .filter(([_, count]) => count >= threshold)
      .map(([style, count]) => ({
        style,
        confidence: count / totalSignals,
      }))
      .sort((a, b) => b.confidence - a.confidence); 

    const styleKeywords = styleConfidences.map(s => s.style);

    
    const priceRange = calculatePriceRange(priceRanges);

    
    const brandThreshold = totalSignals * 0.2;
    const topBrands = Object.entries(brandCounts)
      .filter(([_, count]) => count >= brandThreshold)
      .sort(([_, a], [__, b]) => b - a)
      .map(([brand]) => brand)
      .slice(0, 10); // Top 10

    
    const categoryPreferences: Record<string, any> = {};
    
    for (const [category, styleCounts] of Object.entries(categoryStyleCounts)) {
      const categoryStyles = Object.entries(styleCounts)
        .filter(([_, count]) => count >= threshold)
        .sort(([_, a], [__, b]) => b - a)
        .map(([style]) => style);

      const categoryRatings = categoryRatingCounts[category];
      const ratingMin = categoryRatings && categoryRatings.length > 0
        ? Math.min(...categoryRatings)
        : undefined;

      if (categoryStyles.length > 0 || ratingMin) {
        categoryPreferences[category] = {
          ...(categoryStyles.length > 0 && { style: categoryStyles[0] }), // Top style
          ...(ratingMin && { rating_min: ratingMin }),
        };
      }
    }

    
    const overallConfidence = Math.min(totalSignals / 20, 1.0);

    
    const preferences: Partial<UserPreferences> = {
      style_keywords: styleKeywords,
      price_range_min: priceRange?.min,
      price_range_max: priceRange?.max,
      brand_preferences: topBrands,
      category_preferences: Object.keys(categoryPreferences).length > 0 ? categoryPreferences : undefined,
      confidence_score: overallConfidence,
      conversations_analyzed: totalSignals,
    };

    const updated = await updateUserPreferences(userId, preferences);

    console.log(`✅ Aggregated preferences for user ${userId}:`, {
      styles: styleKeywords,
      priceRange: priceRange,
      brands: topBrands.length,
      confidence: overallConfidence,
    });

    return updated;
  } catch (err: any) {
    console.error(`❌ Error aggregating preferences for user ${userId}:`, err.message);
    return null;
  }
}


function parsePriceMention(mention: string): { min?: number; max?: number } | null {
 
  const rangeMatch = mention.match(/\$?(\d+)\s*-\s*\$?(\d+)/);
  if (rangeMatch) {
    return {
      min: parseInt(rangeMatch[1]),
      max: parseInt(rangeMatch[2]),
    };
  }

  
  const underMatch = mention.match(/under\s*\$?(\d+)/i);
  if (underMatch) {
    return { max: parseInt(underMatch[1]) };
  }

 
  const aboveMatch = mention.match(/above\s*\$?(\d+)/i);
  if (aboveMatch) {
    return { min: parseInt(aboveMatch[1]) };
  }

  return null;
}


function parseRating(rating: string): number | null {
  const match = rating.match(/(\d+)/);
  return match ? parseFloat(match[1]) : null;
}


function calculatePriceRange(
  ranges: Array<{ min?: number; max?: number }>
): { min?: number; max?: number } | null {
  if (ranges.length === 0) return null;

  const mins = ranges.map(r => r.min).filter((m): m is number => m !== undefined && m > 0);
  const maxs = ranges.map(r => r.max).filter((m): m is number => m !== undefined && m < Infinity);

  if (mins.length === 0 && maxs.length === 0) return null;

  return {
    min: mins.length > 0 ? Math.min(...mins) : undefined,
    max: maxs.length > 0 ? Math.max(...maxs) : undefined,
  };
}


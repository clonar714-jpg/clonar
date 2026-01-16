/**
 * 🎯 Unified Widget System
 * 
 * Replaces the sequential card extraction with a parallel widget system.
 * Widgets can run independently or in parallel with research.
 * 
 * ✅ IMPROVEMENT: Now uses registry pattern with WidgetExecutor
 */

// ✅ Widgets are self-contained - no need for shared card types
// Each widget returns its own data structure in WidgetResult.data

// Import WidgetExecutor (widgets are auto-registered when this module is imported)
import { WidgetExecutor } from "./widgets";

// Ensure widgets are registered by importing the registration module
import "./widgets/index";

// Widget types
export type WidgetType = 
  | 'product' 
  | 'hotel' 
  | 'place' 
  | 'movie'
  | 'weather'
  | 'stock'
  | 'calculator';

export interface Widget {
  type: WidgetType;
  params: Record<string, any>;
  canAnswerFully?: boolean; // If true, widget can answer without research
}

export interface WidgetResult {
  type: WidgetType;
  data: any; // ProductCard[] | HotelCard[] | PlaceCard[] | MovieCard[] | WeatherData | StockData | CalculationResult
  success: boolean;
  error?: string;
  llmContext?: string; // ✅ OPTIONAL: Formatted context for LLM (used in executeAll pattern)
}

/**
 * Detect which widgets are needed for a query
 */
export function detectWidgets(
  query: string,
  understanding: {
    intent: string;
    entities: any;
    detectedDomains: string[];
  }
): Widget[] {
  const widgets: Widget[] = [];

  // Product widget
  if (understanding.detectedDomains.includes('product') || 
      understanding.intent === 'product' ||
      /buy|purchase|shop|product|price of|cost of/i.test(query)) {
    widgets.push({
      type: 'product',
      params: {
        query: understanding.entities.brand || understanding.entities.category || query,
        location: understanding.entities.location,
      },
      canAnswerFully: false, // Products usually need research for context
    });
  }

  // Hotel widget
  if (understanding.detectedDomains.includes('hotel') || 
      understanding.intent === 'hotel' ||
      /hotel|accommodation|stay|book room|reservation/i.test(query)) {
    widgets.push({
      type: 'hotel',
      params: {
        location: understanding.entities.location,
        price: understanding.entities.price,
        amenities: understanding.entities.amenities || [],
      },
      canAnswerFully: false, // Hotels need research for reviews/context
    });
  }

  // Place widget
  if (understanding.detectedDomains.includes('place') || 
      understanding.intent === 'place' ||
      /restaurant|cafe|store|shop|near me|nearby/i.test(query)) {
    widgets.push({
      type: 'place',
      params: {
        query: query,
        location: understanding.entities.location,
      },
      canAnswerFully: false, // Places need research for details
    });
  }

  // Movie widget
  if (understanding.detectedDomains.includes('movie') || 
      understanding.intent === 'movie' ||
      /movie|film|watch|cinema|theater/i.test(query)) {
    widgets.push({
      type: 'movie',
      params: {
        query: query,
      },
      canAnswerFully: true, // Movies can be answered from TMDB alone
    });
  }

  // Weather widget (simple queries can be answered fully)
  if (/weather|temperature|forecast|rain|snow|sunny|cloudy/i.test(query)) {
    const isSimpleWeather = /^(what'?s? the weather|temperature|forecast)/i.test(query.trim());
    widgets.push({
      type: 'weather',
      params: {
        location: understanding.entities.location || extractLocation(query),
        date: understanding.entities.time || 'today',
      },
      canAnswerFully: isSimpleWeather, // Simple weather queries don't need research
    });
  }

  // Stock widget (simple queries can be answered fully)
  if (/stock|share price|ticker|AAPL|TSLA|MSFT|NASDAQ|S&P/i.test(query)) {
    const ticker = extractTicker(query);
    if (ticker) {
      const isSimpleStock = /^(what'?s?|show me) (the )?(stock|share) price/i.test(query.trim());
      widgets.push({
        type: 'stock',
        params: {
          symbol: ticker,
        },
        canAnswerFully: isSimpleStock, // Simple stock price queries don't need research
      });
    }
  }

  // Calculator widget (always answers fully)
  if (/calculate|what is \d+|solve|math|equation|convert/i.test(query)) {
    const expression = extractMathExpression(query);
    if (expression) {
      widgets.push({
        type: 'calculator',
        params: {
          expression: expression,
        },
        canAnswerFully: true, // Calculations never need research
      });
    }
  }

  return widgets;
}

/**
 * ✅ IMPROVEMENT: Execute widgets using WidgetExecutor (registry pattern)
 * 
 * Widgets are now self-contained and registered via widgets/index.ts
 */
export async function executeWidgets(
  widgets: Widget[],
  rawResponse?: any, // SerpAPI raw response for product/hotel/place widgets
  classification?: any, // Classification data for widget shouldExecute checks
  llm?: any // ✅ NEW: LLM instance for agent-style widgets
): Promise<WidgetResult[]> {
  // Use WidgetExecutor to execute widgets in parallel
  return WidgetExecutor.executeWidgets(widgets, classification, rawResponse, llm); // ✅ NEW: Pass LLM
}

/**
 * Determine if research is needed based on widgets
 */
export function shouldDoResearch(
  query: string,
  widgets: Widget[]
): boolean {
  // If no widgets, always do research
  if (widgets.length === 0) {
    return true;
  }

  // If any widget can answer fully, check if query is simple
  const canAnswerFully = widgets.some(w => w.canAnswerFully);
  if (canAnswerFully) {
    // Simple queries don't need research if widget can answer
    const isSimpleQuery = /^(what'?s?|show me|tell me|give me)/i.test(query.trim()) && 
                          query.split(/\s+/).length < 10;
    return !isSimpleQuery; // Don't research if simple query
  }

  // Complex queries or widgets that can't answer fully need research
  return true;
}

// ✅ REMOVED: extractCardsFromWidgets() - not used anywhere
// Widgets are self-contained and return data directly in WidgetResult.data
// No need for card type extraction since widgets handle their own data structures

// Helper functions
function extractLocation(query: string): string | undefined {
  // Simple location extraction (can be enhanced)
  const locationMatch = query.match(/(?:in|at|near|around)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/);
  return locationMatch ? locationMatch[1] : undefined;
}

function extractTicker(query: string): string | undefined {
  // Extract stock ticker (uppercase letters, 1-5 chars)
  const tickerMatch = query.match(/\b([A-Z]{1,5})\b/);
  return tickerMatch ? tickerMatch[1] : undefined;
}

function extractMathExpression(query: string): string | undefined {
  // Extract math expression (simplified)
  const mathMatch = query.match(/(\d+(?:\s*[+\-*/]\s*\d+)+)/);
  return mathMatch ? mathMatch[1] : undefined;
}

function evaluateMathExpression(expression: string): number {
  // Placeholder - implement proper math evaluation
  // In production, use a safe math parser library
  try {
    // Very basic evaluation (not safe for production)
    return eval(expression.replace(/\s+/g, ''));
  } catch {
    throw new Error('Invalid math expression');
  }
}


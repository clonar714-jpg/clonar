
import { WidgetExecutor } from "./widgets";


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
  canAnswerFully?: boolean; 
}

export interface WidgetResult {
  type: WidgetType;
  data: any; 
  success: boolean;
  error?: string;
  llmContext?: string; 
}


export function detectWidgets(
  query: string,
  understanding: {
    intent: string;
    entities: any;
    detectedDomains: string[];
  }
): Widget[] {
  const widgets: Widget[] = [];

 
  if (understanding.detectedDomains.includes('product') || 
      understanding.intent === 'product' ||
      /buy|purchase|shop|product|price of|cost of/i.test(query)) {
    widgets.push({
      type: 'product',
      params: {
        query: understanding.entities.brand || understanding.entities.category || query,
        location: understanding.entities.location,
      },
      canAnswerFully: false, 
    });
  }

 
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
      canAnswerFully: false, 
    });
  }

  
  if (understanding.detectedDomains.includes('place') || 
      understanding.intent === 'place' ||
      /restaurant|cafe|store|shop|near me|nearby/i.test(query)) {
    widgets.push({
      type: 'place',
      params: {
        query: query,
        location: understanding.entities.location,
      },
      canAnswerFully: false, 
    });
  }

  
  if (understanding.detectedDomains.includes('movie') || 
      understanding.intent === 'movie' ||
      /movie|film|watch|cinema|theater/i.test(query)) {
    widgets.push({
      type: 'movie',
      params: {
        query: query,
      },
      canAnswerFully: true, 
    });
  }

 
  if (/weather|temperature|forecast|rain|snow|sunny|cloudy/i.test(query)) {
    const isSimpleWeather = /^(what'?s? the weather|temperature|forecast)/i.test(query.trim());
    widgets.push({
      type: 'weather',
      params: {
        location: understanding.entities.location || extractLocation(query),
        date: understanding.entities.time || 'today',
      },
      canAnswerFully: isSimpleWeather, 
    });
  }

  
  if (/stock|share price|ticker|AAPL|TSLA|MSFT|NASDAQ|S&P/i.test(query)) {
    const ticker = extractTicker(query);
    if (ticker) {
      const isSimpleStock = /^(what'?s?|show me) (the )?(stock|share) price/i.test(query.trim());
      widgets.push({
        type: 'stock',
        params: {
          symbol: ticker,
        },
        canAnswerFully: isSimpleStock, 
      });
    }
  }

  
  if (/calculate|what is \d+|solve|math|equation|convert/i.test(query)) {
    const expression = extractMathExpression(query);
    if (expression) {
      widgets.push({
        type: 'calculator',
        params: {
          expression: expression,
        },
        canAnswerFully: true, 
      });
    }
  }

  return widgets;
}


export async function executeWidgets(
  widgets: Widget[],
  rawResponse?: any, 
  classification?: any, 
  llm?: any 
): Promise<WidgetResult[]> {
  
  return WidgetExecutor.executeWidgets(widgets, classification, rawResponse, llm); // ✅ NEW: Pass LLM
}


export function shouldDoResearch(
  query: string,
  widgets: Widget[]
): boolean {
  
  if (widgets.length === 0) {
    return true;
  }

 
  const canAnswerFully = widgets.some(w => w.canAnswerFully);
  if (canAnswerFully) {
    
    const isSimpleQuery = /^(what'?s?|show me|tell me|give me)/i.test(query.trim()) && 
                          query.split(/\s+/).length < 10;
    return !isSimpleQuery; 
  }

  
  return true;
}


function extractLocation(query: string): string | undefined {
  
  const locationMatch = query.match(/(?:in|at|near|around)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/);
  return locationMatch ? locationMatch[1] : undefined;
}

function extractTicker(query: string): string | undefined {
  
  const tickerMatch = query.match(/\b([A-Z]{1,5})\b/);
  return tickerMatch ? tickerMatch[1] : undefined;
}

function extractMathExpression(query: string): string | undefined {
 
  const mathMatch = query.match(/(\d+(?:\s*[+\-*/]\s*\d+)+)/);
  return mathMatch ? mathMatch[1] : undefined;
}

function evaluateMathExpression(expression: string): number {
  
  try {
    
    return eval(expression.replace(/\s+/g, ''));
  } catch {
    throw new Error('Invalid math expression');
  }
}


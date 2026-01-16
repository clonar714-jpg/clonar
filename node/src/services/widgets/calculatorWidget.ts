/**
 * Calculator Widget
 * Handles math calculation queries
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';

/**
 * Extract math expression from query
 */
function extractMathExpression(query: string): string | undefined {
  // Extract math expression (simplified)
  const mathMatch = query.match(/(\d+(?:\s*[+\-*/]\s*\d+)+)/);
  return mathMatch ? mathMatch[1] : undefined;
}

/**
 * Evaluate math expression (basic - use safe parser in production)
 */
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

const calculatorWidget: WidgetInterface = {
  type: 'calculator',

  shouldExecute(classification?: any): boolean {
    // ✅ NEW: Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showCalculationWidget) {
      return true;
    }
    
    // Check if calculator widget should execute based on classification
    if (classification?.widgetTypes?.includes('calculator')) {
      return true;
    }
    
    // Fallback: check intent
    if (classification?.intent === 'calculator') {
      return true;
    }
    
    // Fallback: check query for math keywords
    const query = classification?.queryRefinement || classification?.query || '';
    if (/calculate|what is \d+|solve|math|equation|convert/i.test(query)) {
      const expression = extractMathExpression(query);
      return !!expression;
    }
    return false;
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget } = input;
    
    try {
      const expression = widget.params.expression;
      if (!expression) {
        return {
          type: 'calculator',
          data: {},
          success: false,
          error: 'No expression provided',
        };
      }

      const result = evaluateMathExpression(expression);
      return {
        type: 'calculator',
        data: {
          expression: expression,
          result: result,
        },
        success: true,
      };
    } catch (error: any) {
      return {
        type: 'calculator',
        data: {},
        success: false,
        error: error.message,
      };
    }
  },
};

export default calculatorWidget;


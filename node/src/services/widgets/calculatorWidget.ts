

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';


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

const calculatorWidget: WidgetInterface = {
  type: 'calculator',

  shouldExecute(classification?: any): boolean {
    
    if (classification?.classification?.showCalculationWidget) {
      return true;
    }
    
    
    if (classification?.widgetTypes?.includes('calculator')) {
      return true;
    }
    
    
    if (classification?.intent === 'calculator') {
      return true;
    }
    
    
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


/**
 * Stock Widget
 * Handles stock price queries
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';

const stockWidget: WidgetInterface = {
  type: 'stock',

  shouldExecute(classification?: any): boolean {
    // ✅ NEW: Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showStockWidget) {
      return true;
    }
    
    // Check if stock widget should execute based on classification
    if (classification?.widgetTypes?.includes('stock')) {
      return true;
    }
    
    // Fallback: check intent
    if (classification?.intent === 'stock') {
      return true;
    }
    
    // Fallback: check query for stock keywords
    const query = classification?.queryRefinement || classification?.query || '';
    return /stock|share price|ticker|AAPL|TSLA|MSFT|NASDAQ|S&P/i.test(query);
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget } = input;
    
    // TODO: Integrate stock API (Alpha Vantage, Yahoo Finance, etc.)
    // For now, return placeholder - widget will be handled by research
    return {
      type: 'stock',
      data: [],
      success: false,
      error: 'Stock widget not yet implemented',
    };
  },
};

export default stockWidget;


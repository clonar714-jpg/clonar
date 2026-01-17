

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';

const stockWidget: WidgetInterface = {
  type: 'stock',

  shouldExecute(classification?: any): boolean {
    
    if (classification?.classification?.showStockWidget) {
      return true;
    }
    
    
    if (classification?.widgetTypes?.includes('stock')) {
      return true;
    }
    
    
    if (classification?.intent === 'stock') {
      return true;
    }
    
    
    const query = classification?.queryRefinement || classification?.query || '';
    return /stock|share price|ticker|AAPL|TSLA|MSFT|NASDAQ|S&P/i.test(query);
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget } = input;
    

    return {
      type: 'stock',
      data: [],
      success: false,
      error: 'Stock widget not yet implemented',
    };
  },
};

export default stockWidget;


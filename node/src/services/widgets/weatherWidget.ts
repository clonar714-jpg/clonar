

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';

const weatherWidget: WidgetInterface = {
  type: 'weather',

  shouldExecute(classification?: any): boolean {
    
    if (classification?.classification?.showWeatherWidget) {
      return true;
    }
    
    
    if (classification?.widgetTypes?.includes('weather')) {
      return true;
    }
    
   
    if (classification?.intent === 'weather') {
      return true;
    }
    
    
    const query = classification?.queryRefinement || classification?.query || '';
    return /weather|temperature|forecast|rain|snow|sunny|cloudy/i.test(query);
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget } = input;
    
    
    return {
      type: 'weather',
      data: [],
      success: false,
      error: 'Weather widget not yet implemented',
    };
  },
};

export default weatherWidget;


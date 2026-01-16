/**
 * Weather Widget
 * Handles weather-related queries
 */

import { Widget, WidgetResult } from '../widgetSystem';
import { WidgetInput, WidgetInterface } from './executor';

const weatherWidget: WidgetInterface = {
  type: 'weather',

  shouldExecute(classification?: any): boolean {
    // ✅ NEW: Check structured classification flags (from Zod classifier)
    if (classification?.classification?.showWeatherWidget) {
      return true;
    }
    
    // Check if weather widget should execute based on classification
    if (classification?.widgetTypes?.includes('weather')) {
      return true;
    }
    
    // Fallback: check intent or detectedDomains
    if (classification?.intent === 'weather') {
      return true;
    }
    
    // Fallback: check query for weather keywords (if query is available)
    const query = classification?.queryRefinement || classification?.query || '';
    return /weather|temperature|forecast|rain|snow|sunny|cloudy/i.test(query);
  },

  async execute(input: WidgetInput): Promise<WidgetResult | null> {
    const { widget } = input;
    
    // TODO: Integrate weather API (OpenWeatherMap, WeatherAPI, etc.)
    // For now, return placeholder - widget will be handled by research
    return {
      type: 'weather',
      data: [],
      success: false,
      error: 'Weather widget not yet implemented',
    };
  },
};

export default weatherWidget;


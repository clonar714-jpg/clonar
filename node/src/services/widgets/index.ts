/**
 * Widget Registration
 * Registers all widgets with the WidgetExecutor
 */

import WidgetExecutor from './executor';
import weatherWidget from './weatherWidget';
import stockWidget from './stockWidget';
import calculatorWidget from './calculatorWidget';
import productWidget from './productWidget';
import hotelWidget from './hotelWidget';
import placeWidget from './placeWidget';
import movieWidget from './movieWidget';

// Register all widgets
WidgetExecutor.register(weatherWidget);
WidgetExecutor.register(stockWidget);
WidgetExecutor.register(calculatorWidget);
WidgetExecutor.register(productWidget);
WidgetExecutor.register(hotelWidget);
WidgetExecutor.register(placeWidget);
WidgetExecutor.register(movieWidget);

export { WidgetExecutor };
export default WidgetExecutor;


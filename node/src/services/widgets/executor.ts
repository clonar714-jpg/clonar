

import { Widget, WidgetResult } from '../widgetSystem';

export interface WidgetInput {
  widget?: Widget; 
  classification?: any; 
  rawResponse?: any; 
  chatHistory?: any[]; 
  followUp?: string; 
  llm?: any; 
}


function generateLLMContext(result: WidgetResult): string {
  if (!result.success || !result.data) {
    return '';
  }

  switch (result.type) {
    case 'weather':
      if (result.data && typeof result.data === 'object') {
        const weather = result.data;
        const parts: string[] = [];
        if (weather.temperature) parts.push(`Temperature: ${weather.temperature}`);
        if (weather.condition) parts.push(`Condition: ${weather.condition}`);
        if (weather.location) parts.push(`Location: ${weather.location}`);
        return parts.join(', ');
      }
      break;
    
    case 'stock':
      if (result.data && typeof result.data === 'object') {
        const stock = result.data;
        const parts: string[] = [];
        if (stock.symbol) parts.push(`Symbol: ${stock.symbol}`);
        if (stock.price) parts.push(`Price: ${stock.price}`);
        if (stock.change) parts.push(`Change: ${stock.change}`);
        return parts.join(', ');
      }
      break;
    
    case 'calculator':
      if (result.data && result.data.result !== undefined) {
        return `${result.data.expression} = ${result.data.result}`;
      }
      break;
    
    case 'product':
    case 'hotel':
    case 'place':
    case 'movie':
      if (Array.isArray(result.data) && result.data.length > 0) {
        return result.data.slice(0, 5).map((item: any) => {
          if (result.type === 'product') {
            return `${item.title || 'Product'}: ${item.price || 'N/A'}${item.rating ? ` (${item.rating})` : ''}`;
          } else if (result.type === 'hotel') {
            return `${item.name || 'Hotel'}: ${item.price || 'N/A'}${item.rating ? ` (${item.rating})` : ''}`;
          } else if (result.type === 'place') {
            return `${item.name || 'Place'}: ${item.rating || 'N/A'}${item.address ? ` - ${item.address}` : ''}`;
          } else if (result.type === 'movie') {
            return `${item.title || 'Movie'}: ${item.rating || 'N/A'}${item.releaseDate ? ` (${item.releaseDate})` : ''}`;
          }
          return '';
        }).filter(Boolean).join('; ');
      }
      break;
  }

  return '';
}

export interface WidgetInterface {
  type: string;
  shouldExecute(classification?: any): boolean;
  execute(input: WidgetInput): Promise<WidgetResult | null>;
}

class WidgetExecutor {
  private static widgets = new Map<string, WidgetInterface>();

  static register(widget: WidgetInterface) {
    this.widgets.set(widget.type, widget);
  }

  static getWidget(type: string): WidgetInterface | undefined {
    return this.widgets.get(type);
  }

 
  static async executeAll(input: {
    classification?: any;
    chatHistory?: any[];
    followUp?: string;
    llm?: any;
    rawResponse?: any;
    abortSignal?: AbortSignal; 
  }): Promise<WidgetResult[]> {
    const results: WidgetResult[] = [];

    
    if (input.abortSignal?.aborted) {
      return results;
    }

    await Promise.all(
      Array.from(this.widgets.values()).map(async (widget) => {
        try {
          
          if (input.abortSignal?.aborted) {
            return;
          }
          
          
          if (widget.shouldExecute(input.classification)) {
            
            const widgetObj: Widget = {
              type: widget.type as any,
              params: input.classification?.entities || {},
              canAnswerFully: false,
            };

            const output = await widget.execute({
              widget: widgetObj,
              classification: input.classification,
              rawResponse: input.rawResponse,
              chatHistory: input.chatHistory,
              followUp: input.followUp,
              llm: input.llm,
            });
            
            if (output) {
              
              if (!output.llmContext) {
                output.llmContext = generateLLMContext(output);
              }
              results.push(output);
            }
          }
        } catch (e: any) {
          console.warn(`⚠️ Error executing widget ${widget.type}:`, e.message || e);
        }
      }),
    );

    return results;
  }

  
  static async executeWidget(
    widget: Widget,
    classification?: any,
    rawResponse?: any,
    llm?: any 
  ): Promise<WidgetResult> {
    const widgetImpl = this.widgets.get(widget.type);
    
    if (!widgetImpl) {
      return {
        type: widget.type,
        data: [],
        success: false,
        error: `Unknown widget type: ${widget.type}`,
      };
    }

    try {
      const result = await widgetImpl.execute({
        widget,
        classification,
        rawResponse,
        llm, 
      } as WidgetInput);
      
      return result || {
        type: widget.type,
        data: [],
        success: false,
        error: 'Widget returned no result',
      };
    } catch (error: any) {
      console.warn(`⚠️ Widget ${widget.type} execution failed:`, error.message);
      return {
        type: widget.type,
        data: [],
        success: false,
        error: error.message,
      };
    }
  }

  
  static async executeWidgets(
    widgets: Widget[],
    classification?: any,
    rawResponse?: any,
    llm?: any 
  ): Promise<WidgetResult[]> {
    if (widgets.length === 0) {
      return [];
    }

    const widgetPromises = widgets.map(widget =>
      this.executeWidget(widget, classification, rawResponse, llm) 
    );

    return Promise.all(widgetPromises);
  }
}

export default WidgetExecutor;


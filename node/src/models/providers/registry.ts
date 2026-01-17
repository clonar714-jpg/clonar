

import { ProviderConstructor } from '../base/provider';
import OpenAIProvider from './openai';


export const providers: Record<string, ProviderConstructor<any>> = {
  openai: OpenAIProvider,
  
};


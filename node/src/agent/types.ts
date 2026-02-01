
import z from 'zod';
import BaseEmbedding from '../models/base/embedding';
import BaseLLM from '../models/base/llm';

export type ChatTurnMessage = {
  role: 'user' | 'assistant';
  content: string;
};

export type Chunk = {
  content: string;
  metadata: {
    title: string;
    url?: string;
    [key: string]: any;
  };
};


export type SearchSources = 'web';


export type UICandidate =
  | 'hotel_list'
  | 'flight_list'
  | 'map'
  | 'product_grid'
  | 'place_cards'
  | 'movie_cards';   


export type WidgetType =
  | 'product'
  | 'hotel'
  | 'place'
  | 'movie'
  | 'flight'
  | 'calculator';


export interface DomainEntityTypes {
  location?: string;
  city?: string;
  place?: string;
  date?: string;
  rating?: number;

  checkIn?: string;
  checkOut?: string;
  guests?: number;
  hotelPriceRange?: { min?: number; max?: number };
  hotelType?: string;
  amenities?: string[];

  origin?: string;
  destination?: string;
  departureDate?: string;
  returnDate?: string;
  passengers?: number;
  flightClass?: string;

  placeName?: string;
  placeCategory?: string;
  placeType?: string;
  placePriceRange?: '$' | '$$' | '$$$' | '$$$$';

  title?: string;
  movie?: string;
  year?: number;
  genre?: string;
  actor?: string;
  director?: string;
  streaming?: boolean;

  productName?: string;
  product?: string;
  brand?: string;
  productCategory?: string;
}

export interface QueryUnderstanding {
  intent: string;                 // what user is trying to do
  intentConfidence: number;        // confidence in interpretation (0.0-1.0)

  domain: 
    | 'general'
    | 'travel-hotel'
    | 'travel-flights'
    | 'travel-places'
    | 'movies'
    | 'shopping'
    | null;

 
  entities: Record<string, any> & Partial<DomainEntityTypes>;
  constraints?: Record<string, any>;


  retrievalModes: Array<'web'>;

 
  uiCandidates: UICandidate[];

  uiConfidence: number;            // safety to render domain UI (0.0-1.0)
  requiresStructuredEvidence: boolean;

  uiDecision: 'enable' | 'disable' | 'defer';

  reasoningTrace?: {
    signals: string[];
    confidenceBreakdown: Record<string, number>;
  };
}


export interface RetrievalResult {
  content: string;
  metadata: {
    title: string;
    url?: string;
    sourceType: string;
    timestamp?: string;
    location?: any;
  };
}

/**
 * ClassifierInput - Input for query interpretation
 */
export type ClassifierInput = {
  llm: BaseLLM<any>; 
  enabledSources: SearchSources[];
  query: string;
  chatHistory: ChatTurnMessage[];
};

export type SearchAgentConfig = {
  sources: SearchSources[];
  fileIds: string[];
  llm: BaseLLM<any>; 
  embedding: BaseEmbedding<any> | null; 
  mode: 'speed' | 'balanced' | 'quality';
  systemInstructions: string;
};

export type SearchAgentInput = {
  chatHistory: ChatTurnMessage[];
  followUp: string;
  config: SearchAgentConfig;
  chatId: string;
  messageId: string;
  abortSignal?: AbortSignal; 
};

export type AdditionalConfig = {
  llm: BaseLLM<any>; 
  embedding: BaseEmbedding<any> | null; 
  session: any; 
  abortSignal?: AbortSignal; 
};

export type ResearcherInput = {
  chatHistory: ChatTurnMessage[];
  followUp: string;
  understanding: QueryUnderstanding;
  config: SearchAgentConfig;
};

export type ResearcherOutput = {
  findings: ActionOutput[];
  searchFindings: Chunk[];
};

export type SearchActionOutput = {
  type: 'search_results';
  results: Chunk[];
};

export type DoneActionOutput = {
  type: 'done';
};

export type ReasoningResearchAction = {
  type: 'reasoning';
  reasoning: string;
};

export type ActionOutput =
  | SearchActionOutput
  | DoneActionOutput
  | ReasoningResearchAction;

export interface ResearchAction<
  TSchema extends z.ZodObject<any> = z.ZodObject<any>,
> {
  name: string;
  schema: z.ZodObject<any>;
  getToolDescription: (config: { mode: SearchAgentConfig['mode'] }) => string;
  getDescription: (config: { mode: SearchAgentConfig['mode'] }) => string;
  enabled: (config: {
    understanding: QueryUnderstanding;
    fileIds: string[];
    mode: SearchAgentConfig['mode'];
    sources: SearchSources[];
  }) => boolean;
  execute: (
    params: z.infer<TSchema>,
    additionalConfig: AdditionalConfig & {
      researchBlockId: string;
      fileIds: string[];
    },
  ) => Promise<ActionOutput>;
}

export interface TextBlock {
  id: string;
  type: 'text';
  data: string;
}

export interface WidgetBlock {
  id: string;
  type: 'widget';
  data: {
  
    widgetType: WidgetType;
    params: any;
  };
}

export interface SourceBlock {
  id: string;
  type: 'source';
  data: Array<{
    title: string;
    url?: string;
    [key: string]: any;
  }>;
}

export interface SuggestionBlock {
  id: string;
  type: 'suggestion';
  data: string[];
}

export type Block = TextBlock | WidgetBlock | SourceBlock | SuggestionBlock;

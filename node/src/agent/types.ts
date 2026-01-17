

import z from 'zod';


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


export type SearchSources = 'web' | 'discussions' | 'academic';


import BaseEmbedding from '../models/base/embedding';
import BaseLLM from '../models/base/llm';


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


export type WidgetInput = {
  chatHistory: ChatTurnMessage[];
  followUp: string;
  classification: ClassifierOutput;
  llm: BaseLLM<any>; 
};

export type Widget = {
  type: string;
  shouldExecute: (classification: ClassifierOutput) => boolean;
  execute: (input: WidgetInput) => Promise<WidgetOutput | void>;
};

export type WidgetOutput = {
  type: string;
  llmContext: string;
  data: any;
};


export type ClassifierInput = {
  llm: BaseLLM<any>; 
  enabledSources: SearchSources[];
  query: string;
  chatHistory: ChatTurnMessage[];
};

export type ClassifierOutput = {
  classification: {
    skipSearch: boolean;
    personalSearch: boolean;
    academicSearch: boolean;
    discussionSearch: boolean;
    showWeatherWidget: boolean;
    showStockWidget: boolean;
    showCalculationWidget: boolean;
    showProductWidget: boolean;
    showHotelWidget: boolean;
    showPlaceWidget: boolean;
    showMovieWidget: boolean;
  };
  standaloneFollowUp: string;
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
  classification: ClassifierOutput;
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
    classification: ClassifierOutput;
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
    widgetType: string;
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

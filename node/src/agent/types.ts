/**
 * ✅ Types for APISearchAgent
 * Matches the provided pattern with structured types
 */

import z from 'zod';

// Type aliases for compatibility (adjust based on your actual types)
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

// Search sources
export type SearchSources = 'web' | 'discussions' | 'academic';

// Import base classes for proper typing
import BaseEmbedding from '../models/base/embedding';
import BaseLLM from '../models/base/llm';

// Search agent configuration
export type SearchAgentConfig = {
  sources: SearchSources[];
  fileIds: string[];
  llm: BaseLLM<any>; // BaseLLM instance
  embedding: BaseEmbedding<any> | null; // BaseEmbedding instance or null if not needed
  mode: 'speed' | 'balanced' | 'quality';
  systemInstructions: string;
};

// Search agent input
export type SearchAgentInput = {
  chatHistory: ChatTurnMessage[];
  followUp: string;
  config: SearchAgentConfig;
  chatId: string;
  messageId: string;
  abortSignal?: AbortSignal; // ✅ CRITICAL: For cancellation support
};

// Widget types
export type WidgetInput = {
  chatHistory: ChatTurnMessage[];
  followUp: string;
  classification: ClassifierOutput;
  llm: BaseLLM<any>; // BaseLLM instance
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

// Classifier types
export type ClassifierInput = {
  llm: BaseLLM<any>; // BaseLLM instance
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

// Additional config for research actions
export type AdditionalConfig = {
  llm: BaseLLM<any>; // BaseLLM instance
  embedding: BaseEmbedding<any> | null; // BaseEmbedding instance or null
  session: any; // SessionManager
  abortSignal?: AbortSignal; // ✅ CRITICAL: For cancellation support
};

// Researcher types
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

// Action output types
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

// Research action interface
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

// Block types for session management
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

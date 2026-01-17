

import { randomUUID } from 'crypto';
import { classify } from './classifier';
import { WidgetExecutor } from '../services/widgets';
import { WidgetResult } from '../services/widgetSystem';
import { search, type SearchResult } from '../services/searchService';
import {
  ResearcherOutput,
  SearchAgentInput,
  TextBlock,
  Block,
  ClassifierOutput,
  Chunk,
  ActionOutput,
  SourceBlock,
  SearchActionOutput,
  SearchSources,
} from './types';
import { getWriterPrompt } from './prompts/writer';
import { sessionStore } from './sessionStore';
import { getFollowUpSuggestions } from '../followup';
import type { Message, ToolCall } from '../models/types';

let rfc6902Module: any = null;
const loadRfc6902 = async () => {
  if (rfc6902Module === null) {
    try {
      rfc6902Module = await import('rfc6902');
    } catch (e) {
      rfc6902Module = false; 
      console.warn('⚠️ rfc6902 not installed. For better patch support, install with: npm install rfc6902');
    }
  }
  return rfc6902Module;
};


export class SessionManager {
  private listeners: Map<string, Array<(data?: any) => void>> = new Map();
  private blocks: Map<string, Block> = new Map();
 
  private events: Array<{ event: string; data?: any }> = [];
  
  private sections: Array<{ id: string; title: string; content: string; kind?: string }> = [];
  public id: string;
  
  private TTL_MS = 30 * 60 * 1000; // 30 minutes
  private ttlTimeout: NodeJS.Timeout | null = null;

  constructor() {
    this.id = crypto.randomUUID();
    
    
    this.ttlTimeout = setTimeout(() => {
      
      if (sessionStore.has(this.id)) {
        sessionStore.delete(this.id);
      }
      
      this.removeAllListeners();
      console.log(`🧹 Session ${this.id} expired and cleaned up (TTL: 30 minutes)`);
    }, this.TTL_MS);
  }

  static createSession(): SessionManager {
    return new SessionManager();
  }

  subscribe(callback: (event: string, data?: any) => void): () => void {
    const wrapper = (event: string, data?: any) => callback(event, data);
    
    if (!this.listeners.has('*')) {
      this.listeners.set('*', []);
    }
    
    this.listeners.get('*')!.push(wrapper as (data?: any) => void);

    
    const currentEventsLength = this.events.length;
    for (let i = 0; i < currentEventsLength; i++) {
      const { event, data } = this.events[i];
      try {
        callback(event, data);
      } catch (error) {
        console.error(`Error replaying event to subscriber:`, error);
      }
    }

    
    if (this.sections.length > 0) {
      this.sections.forEach((section) => {
        try {
          callback('data', {
            type: 'section',
            section: section,
            eventId: randomUUID(),
            sessionId: this.id,
          });
        } catch (error) {
          console.error(`Error replaying section to subscriber:`, error);
        }
      });
      console.log(`📋 Replayed ${this.sections.length} sections to new subscriber`);
    }

    
    return () => {
      const listeners = this.listeners.get('*');
      if (listeners) {
        const index = listeners.indexOf(wrapper);
        if (index > -1) {
          listeners.splice(index, 1);
        }
      }
    };
  }

  emit(event: string, data?: any): void {
    
    this.events.push({ event, data });
    
    const listeners = this.listeners.get('*') || [];
    listeners.forEach(listener => {
      try {
        
        (listener as (event: string, data?: any) => void)(event, data);
      } catch (error) {
        console.error(`Error in session listener:`, error);
      }
    });
  }

  emitBlock(block: Block): void {
    this.blocks.set(block.id, block);
    
    this.emit('data', {
      type: 'block',
      block: block,
      eventId: randomUUID(),
      sessionId: this.id,
    });
  }

  async updateBlock(blockId: string, patch: Array<{ op: string; path: string; value: any }>): Promise<void> {
    const block = this.blocks.get(blockId);
    if (!block) return;

    
    try {
      const rfc6902 = await loadRfc6902();
      if (rfc6902 && rfc6902.applyPatch) {
        
        rfc6902.applyPatch(block, patch);
      } else {
        
        for (const p of patch) {
          if (p.op === 'replace' && p.path === '/data' && block.type === 'text') {
            (block as TextBlock).data = p.value;
          }
        }
      }
    } catch (error) {
      console.error(`Error applying patch to block ${blockId}:`, error);
     
      for (const p of patch) {
        if (p.op === 'replace' && p.path === '/data' && block.type === 'text') {
          (block as TextBlock).data = p.value;
        }
      }
    }

    this.blocks.set(blockId, block);
    
    this.emit('data', {
      type: 'updateBlock',
      blockId: blockId,
      patch: patch,
      eventId: randomUUID(),
      sessionId: this.id,
    });
  }

  getBlock(blockId: string): Block | null {
    return this.blocks.get(blockId) || null;
  }

  getAllBlocks(): Block[] {
    return Array.from(this.blocks.values());
  }

  
  addSection(section: { id: string; title: string; content: string; kind?: string }): void {
    
    const exists = this.sections.some(
      (s) => s.id === section.id || s.title === section.title,
    );
    
    if (!exists) {
      this.sections.push(section);
      console.log(`📋 Section added to session: "${section.title}" (id: ${section.id})`);
      
      
      this.emit('data', {
        type: 'section',
        section: section,
        eventId: randomUUID(),
        sessionId: this.id,
      });
      
      
      this.events.push({
        event: 'data',
        data: {
          type: 'section',
          section: section,
          eventId: randomUUID(),
          sessionId: this.id,
        },
      });
    } else {
      console.log(`⚠️ Section already exists, skipping: "${section.title}"`);
    }
  }

  
  getSections(): Array<{ id: string; title: string; content: string; kind?: string }> {
    return [...this.sections]; 
  }

  removeAllListeners(): void {
    this.listeners.clear();
    
    if (this.ttlTimeout) {
      clearTimeout(this.ttlTimeout);
      this.ttlTimeout = null;
    }
  }
}


class Researcher {
  async research(
    session: SessionManager,
    input: {
      chatHistory: any[];
      followUp: string;
      classification: ClassifierOutput;
      config: {
        llm: any;
        embedding?: any;
        sources?: string[];
        mode?: 'speed' | 'balanced' | 'quality';
        fileIds?: string[];
        systemInstructions?: string;
      };
      abortSignal?: AbortSignal; 
      reasoningTracker?: { value: string | null }; 
    }
  ): Promise<ResearcherOutput> {
    
    if (input.abortSignal?.aborted) {
      throw new Error('Research aborted');
    }

    const { ActionRegistry } = await import('./actions');
    const { getResearcherPrompt } = await import('./prompts/researcher');
    const formatChatHistoryAsString = (await import('../utils/formatHistory')).default;

    let actionOutput: ActionOutput[] = [];
    let maxIteration =
      input.config.mode === 'speed'
        ? 2
        : input.config.mode === 'balanced'
          ? 6
          : 25;

    const availableTools = ActionRegistry.getAvailableActionTools({
      classification: input.classification,
      fileIds: input.config.fileIds || [],
      mode: input.config.mode || 'balanced',
      sources: (input.config.sources || ['web']) as SearchSources[],
    });

    const availableActionsDescription =
      ActionRegistry.getAvailableActionsDescriptions({
        classification: input.classification,
        fileIds: input.config.fileIds || [],
        mode: input.config.mode || 'balanced',
        sources: (input.config.sources || ['web']) as SearchSources[],
      });

    
    const researchBlockId = randomUUID();

    
    const agentMessageHistory: Message[] = [
      {
        role: 'user',
        content: `
          <conversation>
          ${formatChatHistoryAsString(input.chatHistory.slice(-10))}
           User: ${input.followUp} (Standalone question: ${input.classification.standaloneFollowUp})
           </conversation>
        `,
      },
    ];

    for (let i = 0; i < maxIteration; i++) {
      
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      
      session.emit('data', {
        type: 'researchProgress',
        eventId: randomUUID(),
        sessionId: session.id,
        researchStep: i + 1,
        maxResearchSteps: maxIteration,
        currentAction: 'Starting research iteration...',
      });

      const researcherPrompt = await getResearcherPrompt(
        availableActionsDescription,
        input.config.mode || 'balanced',
        i,
        maxIteration,
        input.config.fileIds || [],
      );

      
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      const actionStream = input.config.llm.streamText({
        messages: [
          {
            role: 'system',
            content: researcherPrompt,
          },
          ...agentMessageHistory,
        ],
        tools: availableTools,
      });

      let finalToolCalls: ToolCall[] = [];

      
      for await (const partialRes of actionStream) {
        
        if (input.abortSignal?.aborted) {
          throw new Error('Research aborted');
        }

        if (partialRes.toolCallChunk && partialRes.toolCallChunk.length > 0) {
          partialRes.toolCallChunk.forEach((tc: ToolCall) => {
            
            const existingIndex = finalToolCalls.findIndex(
              (ftc) => ftc.id === tc.id,
            );

            if (existingIndex !== -1) {
              
              finalToolCalls[existingIndex].arguments = {
                ...finalToolCalls[existingIndex].arguments,
                ...tc.arguments,
              };
            } else {
              finalToolCalls.push(tc);
            }
          });
        }
      }

      
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      
      if (finalToolCalls.length === 0) {
        break;
      }

      
      if (finalToolCalls[finalToolCalls.length - 1].name === 'done') {
        break;
      }

      
      const actionNames = finalToolCalls
        .filter(tc => tc.name !== '__reasoning_preamble' && tc.name !== 'done')
        .map(tc => tc.name)
        .join(', ') || 'Processing...';
      
      session.emit('data', {
        type: 'researchProgress',
        eventId: randomUUID(),
        sessionId: session.id,
        researchStep: i + 1,
        maxResearchSteps: maxIteration,
        currentAction: actionNames || 'Executing actions...',
      });

      
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      
      const validToolCalls = finalToolCalls.filter((tc) => {
        if (tc.name === 'web_search') {
          return Array.isArray(tc.arguments?.queries) && tc.arguments.queries.length > 0;
        }
        return true;
      });

      
      if (validToolCalls.length === 0) {
        continue; 
      }

      
      agentMessageHistory.push({
        role: 'assistant',
        content: '',
        tool_calls: validToolCalls.map((tc) => ({
          id: tc.id,
          type: 'function' as const,
          function: {
            name: tc.name,
            arguments: JSON.stringify(tc.arguments),
          },
        })),
      } as any); 

      const safeToolCalls = validToolCalls;

      
      const actionResults = await ActionRegistry.executeAll(safeToolCalls, {
        llm: input.config.llm,
        embedding: input.config.embedding || null,
        session: session,
        researchBlockId: researchBlockId,
        fileIds: input.config.fileIds || [],
        abortSignal: input.abortSignal, 
      });

      
      if (input.reasoningTracker && !input.reasoningTracker.value) {
        for (const action of actionResults) {
          if (action.type === 'reasoning' && 'reasoning' in action) {
            const reasoningAction = action as { type: 'reasoning'; reasoning: string };
            if (typeof reasoningAction.reasoning === 'string' && reasoningAction.reasoning.trim().length > 0) {
              input.reasoningTracker.value = reasoningAction.reasoning;
              console.log(`💭💭💭 Captured reasoning from action result: "${reasoningAction.reasoning.substring(0, 100)}..."`);
              break; 
            }
          }
        }
      }

      actionOutput.push(...actionResults);

      
      actionResults.forEach((action, i) => {
        
        if (i >= safeToolCalls.length) {
          console.warn(`⚠️ Action result index ${i} exceeds tool calls length ${safeToolCalls.length}`);
          return;
        }
        
        const toolCall = safeToolCalls[i];
        
        
        agentMessageHistory.push({
          role: 'tool' as any,
          content: JSON.stringify(action),
          tool_call_id: toolCall.id, 
        } as any);
      });
    }

    
    const searchResults = actionOutput
      .filter((a) => a.type === 'search_results')
      .flatMap((a) => {
        const searchAction = a as SearchActionOutput;
        return searchAction.results || [];
      });

    const seenUrls = new Map<string, number>();

    const filteredSearchResults = searchResults
      .map((result, index) => {
        if (result.metadata.url && !seenUrls.has(result.metadata.url)) {
          seenUrls.set(result.metadata.url, index);
          return result;
        } else if (result.metadata.url && seenUrls.has(result.metadata.url)) {
          const existingIndex = seenUrls.get(result.metadata.url)!;
          const existingResult = searchResults[existingIndex];
          existingResult.content += `\n\n${result.content}`;
          return undefined;
        }
        return result;
      })
      .filter((r) => r !== undefined) as Chunk[];

    
    if (filteredSearchResults.length > 0) {
      session.emitBlock({
        id: randomUUID(),
        type: 'source',
        data: filteredSearchResults.map((chunk) => ({
          title: chunk.metadata.title,
          url: chunk.metadata.url,
          
          ...Object.fromEntries(
            Object.entries(chunk.metadata).filter(([key]) => key !== 'title' && key !== 'url')
          ),
        })),
      });
    }

    return {
      findings: actionOutput,
      searchFindings: filteredSearchResults,
    };
  }
}



function getWidgetTypesFromClassification(classificationResult: { classification: { showWeatherWidget: boolean; showStockWidget: boolean; showCalculationWidget: boolean; showProductWidget: boolean; showHotelWidget: boolean; showPlaceWidget: boolean; showMovieWidget: boolean } }): string[] {
  const widgetTypes: string[] = [];
  if (classificationResult.classification.showWeatherWidget) widgetTypes.push('weather');
  if (classificationResult.classification.showStockWidget) widgetTypes.push('stock');
  if (classificationResult.classification.showCalculationWidget) widgetTypes.push('calculator');
  if (classificationResult.classification.showProductWidget) widgetTypes.push('product');
  if (classificationResult.classification.showHotelWidget) widgetTypes.push('hotel');
  if (classificationResult.classification.showPlaceWidget) widgetTypes.push('place');
  if (classificationResult.classification.showMovieWidget) widgetTypes.push('movie');
  return widgetTypes;
}

class APISearchAgent {
  async searchAsync(session: SessionManager, input: SearchAgentInput) {
    
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before starting');
      return;
    }
    
    
    const reasoningTracker = { value: null as string | null };
    
    
    sessionStore.set(session.id, session);
    
    
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before classification');
      return;
    }
    
    console.log('🔍 Starting classification...');
    const classificationResult = await classify({
      chatHistory: input.chatHistory,
      enabledSources: input.config.sources || [],
      query: input.followUp,
      llm: input.config.llm,
    });
    
    
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted after classification');
      return;
    }
    
    console.log('✅ Classification complete:', classificationResult.classification);
    
    
    const classification = classificationResult.classification || classificationResult;

    
    const widgetClassification = {
      classification: classificationResult.classification, // ✅ Use classificationResult.classification directly
      widgetTypes: getWidgetTypesFromClassification(classificationResult), // ✅ Pass full classificationResult
      queryRefinement: classificationResult.standaloneFollowUp,
      query: input.followUp,
    };

    
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before widgets/search');
      return;
    }
    
    const widgetPromise = WidgetExecutor.executeAll({
      classification: widgetClassification,
      chatHistory: input.chatHistory,
      followUp: input.followUp,
      llm: input.config.llm,
      abortSignal: input.abortSignal, // 
    }).then((widgetOutputs) => {
      
      widgetOutputs.forEach((o) => {
        session.emitBlock({
          id: crypto.randomUUID(),
          type: 'widget',
          data: {
            widgetType: o.type,
            params: o.data,
          },
        });
      });
      return widgetOutputs;
    });

    let searchPromise: Promise<ResearcherOutput> | null = null;

    
    if (!classification.skipSearch) {
      const researcher = new Researcher();
      searchPromise = researcher.research(session, {
        chatHistory: input.chatHistory,
        followUp: input.followUp,
        classification: classificationResult, 
        config: input.config,
        abortSignal: input.abortSignal, 
        reasoningTracker: reasoningTracker, 
      });
    } else {
      console.log('⏭️ Skipping search (skipSearch=true)');
    }

    
    console.log('⏳ Waiting for widgets and search to complete...');
    const promises: Array<Promise<WidgetResult[] | ResearcherOutput>> = [widgetPromise];
    if (searchPromise) {
      promises.push(searchPromise);
    }
    
    
    const abortPromise = new Promise((_, reject) => {
      if (input.abortSignal) {
        input.abortSignal.addEventListener('abort', () => {
          reject(new Error('Aborted'));
        });
      }
    });
    
    try {
      await Promise.race([Promise.all(promises), abortPromise]);
    } catch (error: any) {
      if (error.message === 'Aborted' || input.abortSignal?.aborted) {
        console.log('⚠️ Agent search aborted during widgets/search');
        return;
      }
      throw error;
    }
    
    
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted after widgets/search');
      return;
    }
    
    const results = await Promise.all(promises);
    const widgetOutputs = results[0] as WidgetResult[];
    const searchResults = searchPromise ? (results[1] as ResearcherOutput) : null;
    console.log('✅ Widgets and search complete');

    
    if (!classification.skipSearch) {
      const explanationText =
        reasoningTracker.value && typeof reasoningTracker.value === 'string'
          ? reasoningTracker.value
          : `I searched across multiple sources, analyzed the results, and combined the most relevant information to answer your question.`;

      const explanationSection = {
        id: randomUUID(),
        title: 'How I approached this',
        content: explanationText,
        kind: 'explanation',
      };
      console.log(`📋 Adding explanation section to session: "${explanationText.substring(0, 100)}..."`);
      session.addSection(explanationSection);
      console.log(`✅ Explanation section added to session (id: ${explanationSection.id}), total sections: ${session.getSections().length}`);
    }

   
    session.emit('data', {
      type: 'researchComplete',
      eventId: randomUUID(),
      sessionId: session.id,
    });

   
    const finalContext =
      searchResults?.searchFindings
        .map(
          (f: Chunk, index: number) =>
            `<result index=${index + 1} title="${f.metadata.title}">${f.content}</result>`,
        )
        .join('\n') || '';

    const widgetContext = widgetOutputs
      .map((o) => {
        return `<result>${o.llmContext || ''}</result>`;
      })
      .join('\n-------------\n');

    const finalContextWithWidgets = `<search_results note="These are the search results and assistant can cite these">\n${finalContext}\n</search_results>\n<widgets_result noteForAssistant="Its output is already showed to the user, assistant can use this information to answer the query but do not CITE this as a souce">\n${widgetContext}\n</widgets_result>`;

    
    const writerPrompt = getWriterPrompt(
      finalContextWithWidgets,
      input.config.systemInstructions || '',
      input.config.mode || 'balanced',
    );

    
    const llm = input.config.llm;
    
    
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before answer generation');
      return;
    }
    
   
    const streamOptions: any = {
      temperature: 0.3,
      maxTokens: 800,
    };
    
    
    if (input.abortSignal && typeof llm.streamText === 'function') {
      try {
        
        streamOptions.signal = input.abortSignal;
      } catch (e) {
        
      }
    }
    
    const answerStream = llm.streamText({
      messages: [
        {
          role: 'system',
          content: writerPrompt,
        },
        ...input.chatHistory,
        {
          role: 'user',
          content: input.followUp,
        },
      ],
      options: streamOptions,
    });

    
    console.log('📝 Starting answer generation...');
    let responseBlockId = '';
    let chunkCount = 0;
    let followUpGenerationStarted = false;
    let followUpGenerationPromise: Promise<string[]> | null = null;

    try {
      for await (const chunk of answerStream) {
        
        if (input.abortSignal?.aborted) {
          console.log('⚠️ Agent search aborted during answer streaming - breaking loop');
          break; 
        }
        
        
        const content = chunk.contentChunk || '';
        
        if (content) {
          
          if (input.abortSignal?.aborted) {
            console.log('⚠️ Agent search aborted before processing chunk');
            break;
          }
          
          chunkCount++;
          if (chunkCount === 1) {
            console.log('📤 Streaming first chunk to client...');
          }
          
          if (!responseBlockId) {
            
            if (input.abortSignal?.aborted) {
              console.log('⚠️ Agent search aborted before emitting new block');
              break;
            }
            
            
            const block: TextBlock = {
              id: crypto.randomUUID(),
              type: 'text',
              data: content,
            };

            session.emitBlock(block);
            responseBlockId = block.id;
          } else {
            
            if (input.abortSignal?.aborted) {
              console.log('⚠️ Agent search aborted before updating block');
              break;
            }
            
            
            const block = session.getBlock(responseBlockId) as TextBlock | null;

            if (!block) {
              continue;
            }

            block.data += content;

            
            await session.updateBlock(block.id, [
              {
                op: 'replace',
                path: '/data',
                value: block.data,
              },
            ]);

            
            if (!followUpGenerationStarted && (block.data.length > 1000 || chunkCount > 50)) {
              followUpGenerationStarted = true;
              console.log('💡 Starting early follow-up generation (answer length: ' + block.data.length + ' chars)...');
              
              
              followUpGenerationPromise = (async () => {
                try {
                  const cards = widgetOutputs
                    .filter((o) => o.type === 'product' || o.type === 'hotel' || o.type === 'place' || o.type === 'movie')
                    .map((o) => (Array.isArray(o.data) ? o.data : [o.data]))
                    .flat();
                  
                  let intent = 'answer';
                  if (classification.academicSearch) {
                    intent = 'answer';
                  } else if (classification.personalSearch) {
                    intent = 'answer';
                  }
                  
                  const followUpResult = await getFollowUpSuggestions({
                    query: input.followUp,
                    answer: block.data, 
                    intent,
                    cards,
                    sessionId: session.id,
                  });
                  
                  return followUpResult.suggestions;
                } catch (error: any) {
                  console.warn('⚠️ Early follow-up generation failed:', error.message);
                  return [];
                }
              })();
            }
          }
        }
      }
      
      
      if (input.abortSignal?.aborted) {
        console.log('⚠️ Agent search was aborted - skipping final processing');
        return;
      }

      console.log(`✅ Answer generation complete (${chunkCount} chunks)`);
    } catch (error: any) {
      console.error('❌ Error during answer generation:', error);
      session.emit('error', { data: error.message || 'Error generating answer' });
      return;
    }

    
    let followUpSuggestions: string[] = [];
    
    
    if (followUpGenerationPromise) {
      try {
        console.log('⏳ Waiting for early follow-up generation to complete...');
        followUpSuggestions = await followUpGenerationPromise;
        console.log(`✅ Early follow-up generation complete: ${followUpSuggestions.length} suggestions`);
      } catch (error: any) {
        console.warn('⚠️ Early follow-up generation failed, falling back to full answer:', error.message);
        followUpGenerationPromise = null; 
      }
    }
    
    
    if (!followUpGenerationPromise || followUpSuggestions.length === 0) {
      try {
        const responseBlock = session.getBlock(responseBlockId) as TextBlock | null;
        const answerText = responseBlock?.data || '';
        
        if (answerText && !input.abortSignal?.aborted) {
          console.log('💡 Generating follow-up suggestions using Perplexity-style system...');
          
          
          let intent = 'answer';
          if (classification.academicSearch) {
            intent = 'answer';
          } else if (classification.personalSearch) {
            intent = 'answer';
          }
          
          const cards = widgetOutputs
            .filter((o) => o.type === 'product' || o.type === 'hotel' || o.type === 'place' || o.type === 'movie')
            .map((o) => (Array.isArray(o.data) ? o.data : [o.data]))
            .flat();
          
          
          const followUpResult = await getFollowUpSuggestions({
            query: input.followUp,
            answer: answerText,
            intent,
            cards,
            sessionId: session.id,
          });
          
          followUpSuggestions = followUpResult.suggestions;
          
          console.log(`✅ Generated ${followUpSuggestions.length} follow-up suggestions (Perplexity-style)`);
        }
      } catch (error: any) {
        console.warn('⚠️ Failed to generate follow-up suggestions:', error.message);
        
      }
    }

    
    const hotelWidgets = widgetOutputs.filter((o) => o.type === 'hotel' && o.success);
    const productWidgets = widgetOutputs.filter((o) => o.type === 'product' && o.success);
    const placeWidgets = widgetOutputs.filter((o) => o.type === 'place' && o.success);
    
    let scenario = 'general_answer';
    if (hotelWidgets.length > 0) {
      const hotelCards = hotelWidgets.flatMap((w) => (Array.isArray(w.data) ? w.data : [w.data]));
     
      scenario = hotelCards.length === 1 ? 'hotel_lookup_single' : 'hotel_browse';
    } else if (productWidgets.length > 0) {
      scenario = 'product_browse';
    } else if (placeWidgets.length > 0) {
      scenario = 'place_browse';
    }
    
    
    const uiDecision = {
      showMap: scenario === 'hotel_browse' || scenario === 'place_browse',
      showCards: scenario !== 'hotel_lookup_single' && (hotelWidgets.length > 0 || productWidgets.length > 0 || placeWidgets.length > 0),
      showImages: scenario !== 'hotel_browse', 
      showComparison: false, 
    };
    
    
    const searchFindings = searchResults?.searchFindings || [];
    const finalSources: Array<{
      title: string;
      url: string | undefined;
      content: string;
      author?: any;
      thumbnail?: any;
      images?: any;
    }> = searchFindings.map((chunk: Chunk) => ({
      title: chunk.metadata.title,
      url: chunk.metadata.url,
      content: chunk.content,
      author: chunk.metadata.author,
      thumbnail: chunk.metadata.thumbnail,
      images: chunk.metadata.images, 
    }));
    
    
    widgetOutputs.forEach((widget) => {
      if (widget.success && Array.isArray(widget.data)) {
        widget.data.forEach((card: any) => {
          
          if (card.link && !finalSources.find((s) => s.url === card.link)) {
            finalSources.push({
              title: card.name || card.title || 'Hotel',
              url: card.link,
              content: card.description || '',
              author: undefined, 
              thumbnail: card.thumbnail,
              images: card.photos || card.images || [],
            });
          }
        });
      }
    });

    
    const allImages: string[] = [];
    const seenImageUrls = new Set<string>();
    
    
    searchFindings.forEach((chunk: Chunk) => {
      
      if (chunk.metadata.thumbnail && !seenImageUrls.has(chunk.metadata.thumbnail)) {
        allImages.push(chunk.metadata.thumbnail);
        seenImageUrls.add(chunk.metadata.thumbnail);
      }
      
      
      if (chunk.metadata.images && Array.isArray(chunk.metadata.images)) {
        chunk.metadata.images.forEach((img: string) => {
          if (img && !seenImageUrls.has(img)) {
            allImages.push(img);
            seenImageUrls.add(img);
          }
        });
      }
    });
    
  
    widgetOutputs.forEach((widget) => {
      if (widget.success && Array.isArray(widget.data)) {
        widget.data.forEach((card: any) => {
          
          if (card.thumbnail && !seenImageUrls.has(card.thumbnail)) {
            allImages.push(card.thumbnail);
            seenImageUrls.add(card.thumbnail);
          }
          
          
          if (card.photos && Array.isArray(card.photos)) {
            card.photos.forEach((img: string) => {
              if (img && !seenImageUrls.has(img)) {
                allImages.push(img);
                seenImageUrls.add(img);
              }
            });
          } else if (card.images && Array.isArray(card.images)) {
            card.images.forEach((img: string) => {
              if (img && !seenImageUrls.has(img)) {
                allImages.push(img);
                seenImageUrls.add(img);
              }
            });
          }
        });
      }
    });
    
    
    const allVideos: Array<{ url: string; thumbnail?: string; title?: string }> = [];
    
    
    
    const sections = session.getSections();
    console.log(`📋 Sending ${sections.length} sections in end event`);
    
    session.emit('end', {
      followUpSuggestions: followUpSuggestions,
      scenario: scenario,
      uiDecision: uiDecision,
      sections: sections.length > 0 ? sections : undefined, 
      sources: finalSources, 
      destination_images: allImages, 
      videos: allVideos.length > 0 ? allVideos : undefined, 
    });
    

  }
}

export default APISearchAgent;


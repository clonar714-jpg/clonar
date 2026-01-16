/**
 * ✅ APISearchAgent: Clean agent pattern matching provided code
 * 
 * Benefits:
 * - Parallel execution: Widgets and search run simultaneously
 * - Self-selecting widgets: Widgets decide if they should execute
 * - Clean separation: Classification → Execute → Generate
 * - Event-driven: Uses session for streaming
 * - Block-based: Manages response blocks for incremental updates
 */

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
// Note: Database imports need to be adjusted based on your actual database setup
// import db from '../db';
// import { messages } from '../db/schema';
// import { and, eq, gt } from 'drizzle-orm';

// ✅ IMPROVEMENT 2: Lazy-load rfc6902 module (only import if needed)
let rfc6902Module: any = null;
const loadRfc6902 = async () => {
  if (rfc6902Module === null) {
    try {
      rfc6902Module = await import('rfc6902');
    } catch (e) {
      rfc6902Module = false; // Mark as unavailable
      console.warn('⚠️ rfc6902 not installed. For better patch support, install with: npm install rfc6902');
    }
  }
  return rfc6902Module;
};

// SessionManager with block management
export class SessionManager {
  private listeners: Map<string, Array<(data?: any) => void>> = new Map();
  private blocks: Map<string, Block> = new Map();
  // ✅ IMPROVEMENT 1: Store all events for replay on reconnection
  private events: Array<{ event: string; data?: any }> = [];
  // ✅ PERPLEXITY-STYLE: Store sections in session state
  private sections: Array<{ id: string; title: string; content: string; kind?: string }> = [];
  public id: string;
  // ✅ IMPROVEMENT 3: TTL for automatic cleanup (30 minutes)
  private TTL_MS = 30 * 60 * 1000; // 30 minutes
  private ttlTimeout: NodeJS.Timeout | null = null;

  constructor() {
    this.id = crypto.randomUUID();
    
    // ✅ IMPROVEMENT 3: Set up TTL cleanup
    this.ttlTimeout = setTimeout(() => {
      // Remove from sessionStore if it exists
      if (sessionStore.has(this.id)) {
        sessionStore.delete(this.id);
      }
      // Clear all listeners
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
    // Store wrapper with correct signature
    this.listeners.get('*')!.push(wrapper as (data?: any) => void);

    // ✅ IMPROVEMENT 1: Replay all past events to new subscriber (for reconnection)
    const currentEventsLength = this.events.length;
    for (let i = 0; i < currentEventsLength; i++) {
      const { event, data } = this.events[i];
      try {
        callback(event, data);
      } catch (error) {
        console.error(`Error replaying event to subscriber:`, error);
      }
    }

    // ✅ PERPLEXITY-STYLE: Replay all sections to new subscriber (for reconnection)
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

    // Return unsubscribe function
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
    // ✅ IMPROVEMENT 1: Store event for replay on reconnection
    this.events.push({ event, data });
    
    const listeners = this.listeners.get('*') || [];
    listeners.forEach(listener => {
      try {
        // Call listener with event and data (listener is actually wrapper that takes both)
        (listener as (event: string, data?: any) => void)(event, data);
      } catch (error) {
        console.error(`Error in session listener:`, error);
      }
    });
  }

  emitBlock(block: Block): void {
    this.blocks.set(block.id, block);
    // ✅ CRITICAL: Add eventId and sessionId for idempotency
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

    // ✅ IMPROVEMENT 2: Use proper JSON Patch library (rfc6902) for robust patch application
    try {
      const rfc6902 = await loadRfc6902();
      if (rfc6902 && rfc6902.applyPatch) {
        // Use proper JSON Patch application (handles all RFC 6902 operations: add, remove, replace, move, copy, test)
        rfc6902.applyPatch(block, patch);
      } else {
        // Fallback to manual patch application if rfc6902 not installed
        for (const p of patch) {
          if (p.op === 'replace' && p.path === '/data' && block.type === 'text') {
            (block as TextBlock).data = p.value;
          }
        }
      }
    } catch (error) {
      console.error(`Error applying patch to block ${blockId}:`, error);
      // Fallback to manual patch on error
      for (const p of patch) {
        if (p.op === 'replace' && p.path === '/data' && block.type === 'text') {
          (block as TextBlock).data = p.value;
        }
      }
    }

    this.blocks.set(blockId, block);
    // ✅ CRITICAL: Add eventId and sessionId for idempotency
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

  // ✅ PERPLEXITY-STYLE: Add section to session state
  addSection(section: { id: string; title: string; content: string; kind?: string }): void {
    // Check if section already exists (by id or title) to avoid duplicates
    const exists = this.sections.some(
      (s) => s.id === section.id || s.title === section.title,
    );
    
    if (!exists) {
      this.sections.push(section);
      console.log(`📋 Section added to session: "${section.title}" (id: ${section.id})`);
      
      // ✅ CRITICAL: Emit section event for real-time frontend updates
      this.emit('data', {
        type: 'section',
        section: section,
        eventId: randomUUID(),
        sessionId: this.id,
      });
      
      // ✅ IMPROVEMENT 1: Store event for replay on reconnection
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

  // ✅ PERPLEXITY-STYLE: Get all sections from session state
  getSections(): Array<{ id: string; title: string; content: string; kind?: string }> {
    return [...this.sections]; // Return copy to prevent external mutation
  }

  removeAllListeners(): void {
    this.listeners.clear();
    // ✅ IMPROVEMENT 3: Clear TTL timeout when cleaning up
    if (this.ttlTimeout) {
      clearTimeout(this.ttlTimeout);
      this.ttlTimeout = null;
    }
  }
}

// Import ResearcherOutput from types

// Use ClassifierOutput from types

// Researcher class that wraps search functionality
// NOTE: Currently uses simple direct search. For tool-based iterative research,
// see getResearcherPrompt() in prompts/researcher.ts (available for future enhancement)
/**
 * ✅ PERPLEXICA-STYLE: Iterative Tool-Based Researcher
 * Uses actions/tools to perform iterative research with reasoning
 */
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
      abortSignal?: AbortSignal; // ✅ CRITICAL: For cancellation support
      reasoningTracker?: { value: string | null }; // ✅ PERPLEXITY-STYLE: Pass reasoning tracker
    }
  ): Promise<ResearcherOutput> {
    // ✅ CRITICAL: Check if aborted before starting
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

    // ✅ Create research block (simplified - just for tracking, not subSteps)
    const researchBlockId = randomUUID();

    // ✅ Agent message history for tool calling
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
      // ✅ CRITICAL: Check if aborted before each iteration
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      // ✅ ENHANCEMENT 3: Emit progress event at start of iteration
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

      // ✅ CRITICAL: Check if aborted before LLM call
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

      // Process stream to collect tool calls
      for await (const partialRes of actionStream) {
        // ✅ CRITICAL: Check if aborted during streaming
        if (input.abortSignal?.aborted) {
          throw new Error('Research aborted');
        }

        if (partialRes.toolCallChunk && partialRes.toolCallChunk.length > 0) {
          partialRes.toolCallChunk.forEach((tc: ToolCall) => {
            // Note: Reasoning will be captured from executed action results, not from tool call arguments

            // Accumulate tool calls
            const existingIndex = finalToolCalls.findIndex(
              (ftc) => ftc.id === tc.id,
            );

            if (existingIndex !== -1) {
              // Merge arguments (accumulate as they stream in)
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

      // ✅ CRITICAL: Check if aborted after streaming
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      // If no tool calls, break
      if (finalToolCalls.length === 0) {
        break;
      }

      // If done action called, break
      if (finalToolCalls[finalToolCalls.length - 1].name === 'done') {
        break;
      }

      // ✅ ENHANCEMENT 3: Update progress with current action names
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

      // ✅ CRITICAL: Check if aborted before executing actions
      if (input.abortSignal?.aborted) {
        throw new Error('Research aborted');
      }

      // 1️⃣ Validate tool calls FIRST
      const validToolCalls = finalToolCalls.filter((tc) => {
        if (tc.name === 'web_search') {
          return Array.isArray(tc.arguments?.queries) && tc.arguments.queries.length > 0;
        }
        return true;
      });

      // 2️⃣ If no valid tool calls, DO NOT add assistant tool_calls message
      if (validToolCalls.length === 0) {
        continue; // go to next iteration
      }

      // 3️⃣ Only now add assistant tool_calls message
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
      } as any); // Type assertion needed for tool_calls support

      const safeToolCalls = validToolCalls;

      // Execute all tool calls
      const actionResults = await ActionRegistry.executeAll(safeToolCalls, {
        llm: input.config.llm,
        embedding: input.config.embedding || null,
        session: session,
        researchBlockId: researchBlockId,
        fileIds: input.config.fileIds || [],
        abortSignal: input.abortSignal, // ✅ CRITICAL: Pass abort signal
      });

      // ✅ PERPLEXITY-STYLE: Capture reasoning from executed action results (ONCE, first reasoning only)
      if (input.reasoningTracker && !input.reasoningTracker.value) {
        for (const action of actionResults) {
          if (action.type === 'reasoning' && 'reasoning' in action) {
            const reasoningAction = action as { type: 'reasoning'; reasoning: string };
            if (typeof reasoningAction.reasoning === 'string' && reasoningAction.reasoning.trim().length > 0) {
              input.reasoningTracker.value = reasoningAction.reasoning;
              console.log(`💭💭💭 Captured reasoning from action result: "${reasoningAction.reasoning.substring(0, 100)}..."`);
              break; // Only capture first reasoning
            }
          }
        }
      }

      actionOutput.push(...actionResults);

      // ✅ FIX: Add tool results to message history with correct OpenAI format
      // Tool messages must have tool_call_id (not id) and must match tool_calls from assistant message
      actionResults.forEach((action, i) => {
        // ✅ CRITICAL: Only add tool messages for tool calls that were actually made
        // Skip if index is out of bounds (shouldn't happen, but safety check)
        if (i >= safeToolCalls.length) {
          console.warn(`⚠️ Action result index ${i} exceeds tool calls length ${safeToolCalls.length}`);
          return;
        }
        
        const toolCall = safeToolCalls[i];
        
        // ✅ FIX: OpenAI expects tool_call_id (not id) and no name field
        agentMessageHistory.push({
          role: 'tool' as any,
          content: JSON.stringify(action),
          tool_call_id: toolCall.id, // ✅ Must match the id from tool_calls
        } as any);
      });
    }

    // Deduplicate search results by URL
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

    // ✅ Emit final source block with all deduplicated results
    if (filteredSearchResults.length > 0) {
      session.emitBlock({
        id: randomUUID(),
        type: 'source',
        data: filteredSearchResults.map((chunk) => ({
          title: chunk.metadata.title,
          url: chunk.metadata.url,
          // Include other metadata fields (excluding title/url to avoid duplicates)
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


// Widget mapping from classification flags
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
    // ✅ CRITICAL: Check if aborted before starting
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before starting');
      return;
    }
    
    // ✅ PERPLEXITY-STYLE: Track reasoning to emit as explanation section
    // Use a shared object so Researcher can update it
    const reasoningTracker = { value: null as string | null };
    
    // Store session for reconnection support
    sessionStore.set(session.id, session);
    
    // Step 0: Database operations - check/create/update message
    // TODO: Uncomment and adjust database imports based on your schema
    /*
    if (input.chatId && input.messageId) {
      const exists = await db.query.messages.findFirst({
        where: and(
          eq(messages.chatId, input.chatId),
          eq(messages.messageId, input.messageId),
        ),
      });

      if (!exists) {
        await db.insert(messages).values({
          chatId: input.chatId,
          messageId: input.messageId,
          backendId: session.id,
          query: input.followUp,
          createdAt: new Date().toISOString(),
          status: 'answering',
          responseBlocks: [],
        });
      } else {
        // Delete messages after this one (regeneration)
        await db
          .delete(messages)
          .where(
            and(eq(messages.chatId, input.chatId), gt(messages.id, exists.id)),
          )
          .execute();
        
        // Reset message status
        await db
          .update(messages)
          .set({
            status: 'answering',
            backendId: session.id,
            responseBlocks: [],
          })
          .where(
            and(
              eq(messages.chatId, input.chatId),
              eq(messages.messageId, input.messageId),
            ),
          )
          .execute();
      }
    }
    */
    // Step 1: Classify query using structured classifier
    // ✅ CRITICAL: Check if aborted before classification
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
    
    // ✅ CRITICAL: Check if aborted after classification
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted after classification');
      return;
    }
    
    console.log('✅ Classification complete:', classificationResult.classification);
    
    // Store classification for follow-up generation
    // Classifier handles format conversion internally (supports both { object: {...} } and direct object)
    const classification = classificationResult.classification || classificationResult;

    // Step 2: Execute widgets in parallel with search
    // Create classification object for widgets (they check shouldExecute)
    // Widgets will check classification.classification.showWeatherWidget, etc.
    const widgetClassification = {
      classification: classificationResult.classification, // ✅ Use classificationResult.classification directly
      widgetTypes: getWidgetTypesFromClassification(classificationResult), // ✅ Pass full classificationResult
      queryRefinement: classificationResult.standaloneFollowUp,
      query: input.followUp,
    };

    // ✅ CRITICAL: Check if aborted before starting widgets/search
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before widgets/search');
      return;
    }
    
    const widgetPromise = WidgetExecutor.executeAll({
      classification: widgetClassification,
      chatHistory: input.chatHistory,
      followUp: input.followUp,
      llm: input.config.llm,
      abortSignal: input.abortSignal, // ✅ CRITICAL: Pass abort signal
    }).then((widgetOutputs) => {
      // Emit widget blocks
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

    // ✅ FIX: Use classification directly (it's already the inner object from line 372)
    if (!classification.skipSearch) {
      const researcher = new Researcher();
      searchPromise = researcher.research(session, {
        chatHistory: input.chatHistory,
        followUp: input.followUp,
        classification: classificationResult, // ✅ Pass full classificationResult to researcher
        config: input.config,
        abortSignal: input.abortSignal, // ✅ CRITICAL: Pass abort signal
        reasoningTracker: reasoningTracker, // ✅ PERPLEXITY-STYLE: Pass reasoning tracker
      });
    } else {
      console.log('⏭️ Skipping search (skipSearch=true)');
    }

    // Step 3: Wait for both widgets and search
    console.log('⏳ Waiting for widgets and search to complete...');
    const promises: Array<Promise<WidgetResult[] | ResearcherOutput>> = [widgetPromise];
    if (searchPromise) {
      promises.push(searchPromise);
    }
    
    // ✅ CRITICAL: Use Promise.race to detect abort during wait
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
    
    // ✅ CRITICAL: Check if aborted after widgets/search
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted after widgets/search');
      return;
    }
    
    const results = await Promise.all(promises);
    const widgetOutputs = results[0] as WidgetResult[];
    const searchResults = searchPromise ? (results[1] as ResearcherOutput) : null;
    console.log('✅ Widgets and search complete');

    // ✅ PERPLEXITY-STYLE: Always create explanation section when search is executed
    // Use reasoning from tracker if available, otherwise use fallback message
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

    // ✅ CRITICAL: Add eventId and sessionId for idempotency
    session.emit('data', {
      type: 'researchComplete',
      eventId: randomUUID(),
      sessionId: session.id,
    });

    // Step 5: Format context
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

    // Step 6: Generate answer with streaming
    const writerPrompt = getWriterPrompt(
      finalContextWithWidgets,
      input.config.systemInstructions || '',
      input.config.mode || 'balanced',
    );

    // Use LLM's streamText if available, otherwise use chat completions
    const llm = input.config.llm;
    
    // ✅ CRITICAL: Check if aborted before starting answer generation
    if (input.abortSignal?.aborted) {
      console.log('⚠️ Agent search aborted before answer generation');
      return;
    }
    
    // Use BaseLLM's streamText method
    // ✅ CRITICAL: Pass abort signal if LLM supports it
    const streamOptions: any = {
      temperature: 0.3,
      maxTokens: 800,
    };
    
    // Some LLM providers support abortSignal in options
    if (input.abortSignal && typeof llm.streamText === 'function') {
      try {
        // Try to pass abortSignal if supported
        streamOptions.signal = input.abortSignal;
      } catch (e) {
        // Provider doesn't support signal, continue without it
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

    // Step 7: Stream answer chunks with block management
    console.log('📝 Starting answer generation...');
    let responseBlockId = '';
    let chunkCount = 0;
    let followUpGenerationStarted = false;
    let followUpGenerationPromise: Promise<string[]> | null = null;

    try {
      for await (const chunk of answerStream) {
        // ✅ TASK 2: Hard abort check - break immediately if aborted
        if (input.abortSignal?.aborted) {
          console.log('⚠️ Agent search aborted during answer streaming - breaking loop');
          break; // ✅ CRITICAL: Use break, not return, to exit loop immediately
        }
        
        // StreamTextOutput uses contentChunk
        const content = chunk.contentChunk || '';
        
        if (content) {
          // ✅ TASK 2: Check abort before processing content
          if (input.abortSignal?.aborted) {
            console.log('⚠️ Agent search aborted before processing chunk');
            break;
          }
          
          chunkCount++;
          if (chunkCount === 1) {
            console.log('📤 Streaming first chunk to client...');
          }
          
          if (!responseBlockId) {
            // ✅ TASK 2: Check abort before emitting new block
            if (input.abortSignal?.aborted) {
              console.log('⚠️ Agent search aborted before emitting new block');
              break;
            }
            
            // Create new text block
            const block: TextBlock = {
              id: crypto.randomUUID(),
              type: 'text',
              data: content,
            };

            session.emitBlock(block);
            responseBlockId = block.id;
          } else {
            // ✅ TASK 2: Check abort before updating block
            if (input.abortSignal?.aborted) {
              console.log('⚠️ Agent search aborted before updating block');
              break;
            }
            
            // Update existing block
            const block = session.getBlock(responseBlockId) as TextBlock | null;

            if (!block) {
              continue;
            }

            block.data += content;

            // ✅ IMPROVEMENT 2: updateBlock is now async (for rfc6902 support)
            await session.updateBlock(block.id, [
              {
                op: 'replace',
                path: '/data',
                value: block.data,
              },
            ]);

            // ✅ OPTIMIZATION: Start follow-up generation early (when we have enough text)
            // Start when answer is ~1000 chars or after 50 chunks (whichever comes first)
            if (!followUpGenerationStarted && (block.data.length > 1000 || chunkCount > 50)) {
              followUpGenerationStarted = true;
              console.log('💡 Starting early follow-up generation (answer length: ' + block.data.length + ' chars)...');
              
              // Start follow-up generation in parallel (don't await yet)
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
                    answer: block.data, // Use current answer text (will be updated)
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
      
      // ✅ TASK 2: Check abort after loop completes
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

    // Step 8: Generate follow-up suggestions using Perplexity-style system
    // ✅ PERPLEXITY-STYLE: Full sophisticated system with templates, slots, scoring
    let followUpSuggestions: string[] = [];
    
    // ✅ OPTIMIZATION: If we started early generation, wait for it; otherwise start now
    if (followUpGenerationPromise) {
      try {
        console.log('⏳ Waiting for early follow-up generation to complete...');
        followUpSuggestions = await followUpGenerationPromise;
        console.log(`✅ Early follow-up generation complete: ${followUpSuggestions.length} suggestions`);
      } catch (error: any) {
        console.warn('⚠️ Early follow-up generation failed, falling back to full answer:', error.message);
        followUpGenerationPromise = null; // Reset to trigger fallback
      }
    }
    
    // ✅ FALLBACK: If early generation didn't happen or failed, generate now with full answer
    if (!followUpGenerationPromise || followUpSuggestions.length === 0) {
      try {
        const responseBlock = session.getBlock(responseBlockId) as TextBlock | null;
        const answerText = responseBlock?.data || '';
        
        if (answerText && !input.abortSignal?.aborted) {
          console.log('💡 Generating follow-up suggestions using Perplexity-style system...');
          
          // Determine intent from classification
          let intent = 'answer';
          if (classification.academicSearch) {
            intent = 'answer';
          } else if (classification.personalSearch) {
            intent = 'answer';
          }
          // Could enhance with more specific intent detection
          
          // Get widget outputs as cards
          const cards = widgetOutputs
            .filter((o) => o.type === 'product' || o.type === 'hotel' || o.type === 'place' || o.type === 'movie')
            .map((o) => (Array.isArray(o.data) ? o.data : [o.data]))
            .flat();
          
          // Use Perplexity-style follow-up generator
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
        // Continue without suggestions - not critical
      }
    }

    // Step 9: Compute UI decision from scenario (backend decides WHAT to show)
    // Determine scenario from widget outputs and classification
    const hotelWidgets = widgetOutputs.filter((o) => o.type === 'hotel' && o.success);
    const productWidgets = widgetOutputs.filter((o) => o.type === 'product' && o.success);
    const placeWidgets = widgetOutputs.filter((o) => o.type === 'place' && o.success);
    
    let scenario = 'general_answer';
    if (hotelWidgets.length > 0) {
      const hotelCards = hotelWidgets.flatMap((w) => (Array.isArray(w.data) ? w.data : [w.data]));
      // Single hotel lookup vs browse
      scenario = hotelCards.length === 1 ? 'hotel_lookup_single' : 'hotel_browse';
    } else if (productWidgets.length > 0) {
      scenario = 'product_browse';
    } else if (placeWidgets.length > 0) {
      scenario = 'place_browse';
    }
    
    // Compute UI decision from scenario (NOT from data presence)
    const uiDecision = {
      showMap: scenario === 'hotel_browse' || scenario === 'place_browse',
      showCards: scenario !== 'hotel_lookup_single' && (hotelWidgets.length > 0 || productWidgets.length > 0 || placeWidgets.length > 0),
      showImages: scenario !== 'hotel_browse', // Hotels typically don't need image grid
      showComparison: false, // Can be enhanced later for comparison queries
    };
    
    // Step 10: Signal completion with follow-up suggestions and UI decision
    // ✅ FIX: Include sources in end event (from deduplicated search results)
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
      images: chunk.metadata.images, // ✅ Include images for media tab
    }));
    
    // ✅ FIX: Extract sources from widget results (hotels, products, places have links)
    widgetOutputs.forEach((widget) => {
      if (widget.success && Array.isArray(widget.data)) {
        widget.data.forEach((card: any) => {
          // Add link as source if available
          if (card.link && !finalSources.find((s) => s.url === card.link)) {
            finalSources.push({
              title: card.name || card.title || 'Hotel',
              url: card.link,
              content: card.description || '',
              author: undefined, // Widget cards don't have author
              thumbnail: card.thumbnail,
              images: card.photos || card.images || [],
            });
          }
        });
      }
    });

    // ✅ FIX: Aggregate all images from search results AND widget results for media tab
    const allImages: string[] = [];
    const seenImageUrls = new Set<string>();
    
    // Collect images from search findings
    searchFindings.forEach((chunk: Chunk) => {
      // Add thumbnail if present
      if (chunk.metadata.thumbnail && !seenImageUrls.has(chunk.metadata.thumbnail)) {
        allImages.push(chunk.metadata.thumbnail);
        seenImageUrls.add(chunk.metadata.thumbnail);
      }
      
      // Add images array if present
      if (chunk.metadata.images && Array.isArray(chunk.metadata.images)) {
        chunk.metadata.images.forEach((img: string) => {
          if (img && !seenImageUrls.has(img)) {
            allImages.push(img);
            seenImageUrls.add(img);
          }
        });
      }
    });
    
    // ✅ FIX: Collect images from widget results (hotels, products, places have photos)
    widgetOutputs.forEach((widget) => {
      if (widget.success && Array.isArray(widget.data)) {
        widget.data.forEach((card: any) => {
          // Add thumbnail if present
          if (card.thumbnail && !seenImageUrls.has(card.thumbnail)) {
            allImages.push(card.thumbnail);
            seenImageUrls.add(card.thumbnail);
          }
          
          // Add photos array if present
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
    
    // ✅ FIX: Aggregate videos from search results (if any)
    // Note: Videos are typically in separate video_results, but we can extract from chunks if available
    const allVideos: Array<{ url: string; thumbnail?: string; title?: string }> = [];
    // Videos would come from video-specific actions or search results with video metadata
    // For now, we'll collect from search results if they have video metadata
    
    // ✅ PERPLEXITY-STYLE: Get sections from session state (includes explanation section)
    const sections = session.getSections();
    console.log(`📋 Sending ${sections.length} sections in end event`);
    
    session.emit('end', {
      followUpSuggestions: followUpSuggestions,
      scenario: scenario,
      uiDecision: uiDecision,
      sections: sections.length > 0 ? sections : undefined, // ✅ PERPLEXITY-STYLE: Include sections from session state
      sources: finalSources, // ✅ FIX: Include sources in end event
      destination_images: allImages, // ✅ FIX: Aggregate images for media tab (snake_case for frontend)
      videos: allVideos.length > 0 ? allVideos : undefined, // ✅ FIX: Include videos if any
    });
    
    // Clean up session after completion (optional - can keep for reconnection)
    // sessionStore.delete(session.id);

    // Step 9: Update database with final blocks
    // TODO: Uncomment and adjust database imports based on your schema
    /*
    if (input.chatId && input.messageId) {
      await db
        .update(messages)
        .set({
          status: 'completed',
          responseBlocks: session.getAllBlocks(),
        })
        .where(
          and(
            eq(messages.chatId, input.chatId),
            eq(messages.messageId, input.messageId),
          ),
        )
        .execute();
    }
    */
  }
}

export default APISearchAgent;


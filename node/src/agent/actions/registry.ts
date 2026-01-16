/**
 * ✅ PERPLEXICA-STYLE: Action Registry
 * Registry pattern for managing research actions
 * 
 * Benefits:
 * - Extensible: Add new actions without modifying core logic
 * - Self-contained: Each action manages its own logic
 * - Testable: Easy to test individual actions
 * - Maintainable: Better code organization
 */

import {
  ResearchAction,
  ClassifierOutput,
  SearchAgentConfig,
  SearchSources,
  ActionOutput,
  AdditionalConfig,
} from '../types';
import { Tool, ToolCall } from '../../models/types';

class ActionRegistry {
  private static actions: Map<string, ResearchAction<any>> = new Map();

  /**
   * Register a research action
   */
  static register(action: ResearchAction<any>): void {
    this.actions.set(action.name, action);
    console.log(`✅ Registered action: ${action.name}`);
  }

  /**
   * Get an action by name
   */
  static get(name: string): ResearchAction<any> | undefined {
    return this.actions.get(name);
  }

  /**
   * Get available actions based on configuration
   */
  static getAvailableActions(config: {
    classification: ClassifierOutput;
    fileIds: string[];
    mode: SearchAgentConfig['mode'];
    sources: SearchSources[];
  }): ResearchAction<any>[] {
    return Array.from(this.actions.values()).filter((action) =>
      action.enabled(config),
    );
  }

  /**
   * Get available actions as Tool format (for LLM function calling)
   */
  static getAvailableActionTools(config: {
    classification: ClassifierOutput;
    fileIds: string[];
    mode: SearchAgentConfig['mode'];
    sources: SearchSources[];
  }): Tool[] {
    const availableActions = this.getAvailableActions(config);

    return availableActions.map((action) => ({
      name: action.name,
      description: action.getToolDescription({ mode: config.mode }),
      schema: action.schema,
    }));
  }

  /**
   * Get available actions as formatted descriptions (for prompts)
   */
  static getAvailableActionsDescriptions(config: {
    classification: ClassifierOutput;
    fileIds: string[];
    mode: SearchAgentConfig['mode'];
    sources: SearchSources[];
  }): string {
    const availableActions = this.getAvailableActions(config);

    return availableActions
      .map(
        (action) =>
          `<tool name="${action.name}">\n${action.getDescription({ mode: config.mode })}\n</tool>`,
      )
      .join('\n\n');
  }

  /**
   * Execute a single action
   */
  static async execute(
    name: string,
    params: any,
    additionalConfig: AdditionalConfig & {
      researchBlockId: string;
      fileIds: string[];
    },
  ): Promise<ActionOutput> {
    const action = this.actions.get(name);

    if (!action) {
      throw new Error(`Action with name ${name} not found`);
    }

    return action.execute(params, additionalConfig);
  }

  /**
   * Execute multiple actions in parallel
   */
  static async executeAll(
    actions: ToolCall[],
    additionalConfig: AdditionalConfig & {
      researchBlockId: string;
      fileIds: string[];
    },
  ): Promise<ActionOutput[]> {
    const results: ActionOutput[] = [];

    await Promise.all(
      actions.map(async (actionConfig) => {
        const output = await this.execute(
          actionConfig.name,
          actionConfig.arguments,
          additionalConfig,
        );
        results.push(output);
      }),
    );

    return results;
  }

  /**
   * Clear all registered actions (useful for testing)
   */
  static clear(): void {
    this.actions.clear();
  }
}

export default ActionRegistry;


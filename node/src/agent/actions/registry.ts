

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

 
  static register(action: ResearchAction<any>): void {
    this.actions.set(action.name, action);
    console.log(`✅ Registered action: ${action.name}`);
  }

  
  static get(name: string): ResearchAction<any> | undefined {
    return this.actions.get(name);
  }

  
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

  static clear(): void {
    this.actions.clear();
  }
}

export default ActionRegistry;


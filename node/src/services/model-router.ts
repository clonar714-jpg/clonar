// node/src/services/model-router.ts — central routing per task type

export type ModelName = 'small' | 'main';

export interface LlmCallOptions {
  task: 'classification' | 'planner' | 'summary' | 'critique';
  mode?: 'quick' | 'deep';
  maxTokens?: number;
}

export interface LlmClient {
  call(model: ModelName, prompt: string, options?: LlmCallOptions): Promise<string>;
}

export class SimpleModelRouter {
  private client: LlmClient;

  constructor(client: LlmClient) {
    this.client = client;
  }

  async classify(prompt: string): Promise<string> {
    return this.client.call('small', prompt, {
      task: 'classification',
      maxTokens: 256,
    });
  }

  async plan(prompt: string, mode: 'quick' | 'deep'): Promise<string> {
    const model: ModelName = mode === 'deep' ? 'main' : 'small';
    return this.client.call(model, prompt, {
      task: 'planner',
      mode,
      maxTokens: 512,
    });
  }

  async summarize(prompt: string, mode: 'quick' | 'deep'): Promise<string> {
    const model: ModelName = mode === 'deep' ? 'main' : 'small';
    return this.client.call(model, prompt, {
      task: 'summary',
      mode,
      maxTokens: mode === 'deep' ? 2048 : 1024,
    });
  }

  async critique(prompt: string): Promise<string> {
    return this.client.call('main', prompt, {
      task: 'critique',
      maxTokens: 1024,
    });
  }
}



import { ClientConfig, getClientConfig, getDefaultClientConfig } from './clientConfig';
import { SearchAgentConfig } from '../agent/types';
import { Request } from 'express';


export function buildAgentConfig(
  req: Request,
  baseConfig: {
    llm: any;
    embedding?: any;
    sources?: string[];
    mode?: 'speed' | 'balanced' | 'quality';
    fileIds?: string[];
  }
): SearchAgentConfig {
  const clientConfig = getClientConfig(req);
  const body = req.body || {};

  return {
    sources: baseConfig.sources || ['web'],
    fileIds: baseConfig.fileIds || [],
    llm: baseConfig.llm,
    embedding: baseConfig.embedding,
    mode: body.mode || baseConfig.mode || 'balanced',
    systemInstructions: body.systemInstructions || clientConfig.systemInstructions || '',
  };
}


export function getWidgetVisibility(clientConfig: ClientConfig): {
  showWeatherWidget: boolean;
  showNewsWidget: boolean;
} {
  return {
    showWeatherWidget: clientConfig.showWeatherWidget ?? true,
    showNewsWidget: clientConfig.showNewsWidget ?? true,
  };
}


export function shouldAutoMediaSearch(clientConfig: ClientConfig): boolean {
  return clientConfig.autoMediaSearch ?? true;
}


export function getMeasurementUnit(clientConfig: ClientConfig): 'metric' | 'imperial' {
  return clientConfig.measurementUnit || 'metric';
}


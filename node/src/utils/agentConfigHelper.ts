/**
 * ✅ Agent Config Helper
 * 
 * Integrates client configuration with agent settings
 */

import { ClientConfig, getClientConfig, getDefaultClientConfig } from './clientConfig';
import { SearchAgentConfig } from '../agent/types';
import { Request } from 'express';

/**
 * Build SearchAgentConfig from request and client settings
 */
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

/**
 * Get widget visibility settings from client config
 */
export function getWidgetVisibility(clientConfig: ClientConfig): {
  showWeatherWidget: boolean;
  showNewsWidget: boolean;
} {
  return {
    showWeatherWidget: clientConfig.showWeatherWidget ?? true,
    showNewsWidget: clientConfig.showNewsWidget ?? true,
  };
}

/**
 * Check if media search should be enabled
 */
export function shouldAutoMediaSearch(clientConfig: ClientConfig): boolean {
  return clientConfig.autoMediaSearch ?? true;
}

/**
 * Get measurement unit preference
 */
export function getMeasurementUnit(clientConfig: ClientConfig): 'metric' | 'imperial' {
  return clientConfig.measurementUnit || 'metric';
}


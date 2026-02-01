

import { configManager } from '../config';

export interface ClientConfig {
  theme?: 'dark' | 'light';
  autoMediaSearch?: boolean;
  systemInstructions?: string;
  showWeatherWidget?: boolean;
  showNewsWidget?: boolean;
  measurementUnit?: 'metric' | 'imperial';
}


function parseBoolean(value: any, defaultValue: boolean = true): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    return value.toLowerCase() === 'true';
  }
  return defaultValue;
}


export function getClientConfig(req: {
  headers?: Record<string, string | string[] | undefined>;
  body?: Record<string, any>;
}): ClientConfig {
  const config: ClientConfig = {};

  
  const headerConfig = req.headers?.['x-client-config'];
  if (headerConfig) {
    try {
      const parsed = typeof headerConfig === 'string' 
        ? JSON.parse(headerConfig) 
        : headerConfig;
      return normalizeConfig(parsed);
    } catch (e) {
      console.warn('⚠️ Failed to parse X-Client-Config header:', e);
    }
  }

  
  if (req.body) {
    return normalizeConfig(req.body);
  }

  return config;
}


function normalizeConfig(raw: any): ClientConfig {
  return {
    theme: raw.theme === 'light' ? 'light' : 'dark',
    autoMediaSearch: parseBoolean(raw.autoMediaSearch, true),
    systemInstructions: typeof raw.systemInstructions === 'string' 
      ? raw.systemInstructions 
      : '',
    showWeatherWidget: parseBoolean(raw.showWeatherWidget, true),
    showNewsWidget: parseBoolean(raw.showNewsWidget, true),
    measurementUnit: raw.measurementUnit === 'imperial' 
      ? 'imperial' 
      : 'metric',
  };
}


export function getDefaultClientConfig(): ClientConfig {
  
  const serverPrefs = configManager.getConfig('preferences', {});
  const serverPersonalization = configManager.getConfig('personalization', {});

  return {
    theme: serverPrefs.theme || 'dark',
    autoMediaSearch: serverPrefs.autoMediaSearch ?? true,
    systemInstructions: serverPersonalization.systemInstructions || '',
    showWeatherWidget: serverPrefs.showWeatherWidget ?? true,
    showNewsWidget: serverPrefs.showNewsWidget ?? true,
    measurementUnit: serverPrefs.measureUnit?.toLowerCase() === 'imperial' 
      ? 'imperial' 
      : 'metric',
  };
}


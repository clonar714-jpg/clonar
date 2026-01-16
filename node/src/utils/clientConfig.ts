/**
 * ✅ Client Configuration Utility
 * 
 * Parses and normalizes client-side configuration from request headers/body
 * These settings come from localStorage on the client side
 * Can also fall back to server-side config from ConfigManager
 */

import { configManager } from '../config';

export interface ClientConfig {
  theme?: 'dark' | 'light';
  autoMediaSearch?: boolean;
  systemInstructions?: string;
  showWeatherWidget?: boolean;
  showNewsWidget?: boolean;
  measurementUnit?: 'metric' | 'imperial';
}

/**
 * Parse boolean from string (handles 'true'/'false' strings)
 */
function parseBoolean(value: any, defaultValue: boolean = true): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    return value.toLowerCase() === 'true';
  }
  return defaultValue;
}

/**
 * Extract client config from request
 * Can come from headers (X-Client-Config) or body
 */
export function getClientConfig(req: {
  headers?: Record<string, string | string[] | undefined>;
  body?: Record<string, any>;
}): ClientConfig {
  const config: ClientConfig = {};

  // Try to get from headers first (if client sends as JSON header)
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

  // Fallback to body
  if (req.body) {
    return normalizeConfig(req.body);
  }

  return config;
}

/**
 * Normalize config values to proper types
 */
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

/**
 * Get default client config (for when no config is provided)
 * Falls back to server-side config if available
 */
export function getDefaultClientConfig(): ClientConfig {
  // Try to get from server config first
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


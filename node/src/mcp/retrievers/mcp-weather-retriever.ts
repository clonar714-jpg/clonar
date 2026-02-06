/**
 * MCP-backed weather retriever: calls weather_search by CAPABILITY.
 * Used by Layer 2 executor when a step has capability 'weather_search'.
 */
import type { WeatherSearchToolInput, WeatherSearchToolResult, WeatherResult } from '@/mcp/tool-contract';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';
import { callWeatherSearch } from '@/mcp/capability-client';

export interface WeatherRetriever {
  searchWeather(input: WeatherSearchToolInput): Promise<{ weather: WeatherResult; snippets: RetrievedSnippet[] }>;
}

export class McpWeatherRetriever implements WeatherRetriever {
  async searchWeather(input: WeatherSearchToolInput): Promise<WeatherSearchToolResult> {
    return callWeatherSearch(input);
  }
}

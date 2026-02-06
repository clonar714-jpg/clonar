/**
 * MCP tool server (stdio): weather_search. Returns standard envelope.
 * Run: npx tsx src/mcp/servers/weather-server.ts
 * For persistent use, prefer: npm run mcp:serve (HTTP server with all tools).
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { handleWeatherSearch } from '@/mcp/handlers';

const inputSchema = z.object({
  location: z.string().min(1),
  date: z.string().min(1),
});

async function main() {
  const server = new McpServer({ name: 'clonar-weather-search', version: '1.0.0' });

  server.registerTool(
    'weather_search',
    {
      description: 'Get weather for a location and date. Returns normalized envelope (ok, data, snippets, error?).',
      inputSchema,
    },
    async (args) => {
      const parsed = inputSchema.parse(args);
      const envelope = await handleWeatherSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Weather search MCP server running on stdio');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

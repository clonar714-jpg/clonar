/**
 * MCP tool server (stdio): flight_search. Returns standard envelope.
 * Run: npx tsx src/mcp/servers/flight-server.ts
 * For persistent use, prefer: npm run mcp:serve (HTTP server with all tools).
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { handleFlightSearch } from '@/mcp/handlers';

const inputSchema = z.object({
  rewrittenQuery: z.string().min(1),
  origin: z.string().min(1),
  destination: z.string().min(1),
  departDate: z.string().min(1),
  returnDate: z.string().optional(),
  adults: z.number().int().min(1),
  cabin: z.enum(['economy', 'premium', 'business', 'first']).optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

async function main() {
  const server = new McpServer({ name: 'clonar-flight-search', version: '1.0.0' });

  server.registerTool(
    'flight_search',
    {
      description: 'Search flights by capability. Returns normalized envelope (ok, data, snippets, error?).',
      inputSchema,
    },
    async (args) => {
      const parsed = inputSchema.parse(args);
      const envelope = await handleFlightSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Flight search MCP server running on stdio');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

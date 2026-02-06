/**
 * MCP tool server (stdio): hotel_search. Returns standard envelope. Implements provider failover.
 * Run: npx tsx src/mcp/servers/hotel-server.ts
 * For persistent use, prefer: npm run mcp:serve (HTTP server with all tools).
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { handleHotelSearch } from '@/mcp/handlers';

const inputSchema = z.object({
  rewrittenQuery: z.string().min(1),
  destination: z.string().min(1),
  checkIn: z.string().min(1),
  checkOut: z.string().min(1),
  guests: z.number().int().min(1),
  budgetMin: z.number().optional(),
  budgetMax: z.number().optional(),
  area: z.string().optional(),
  amenities: z.array(z.string()).optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

async function main() {
  const server = new McpServer({ name: 'clonar-hotel-search', version: '1.0.0' });

  server.registerTool(
    'hotel_search',
    {
      description: 'Search hotels by capability. Returns normalized envelope (ok, data, snippets, error?).',
      inputSchema,
    },
    async (args) => {
      const parsed = inputSchema.parse(args);
      const envelope = await handleHotelSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Hotel search MCP server running on stdio');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

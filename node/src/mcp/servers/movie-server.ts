/**
 * MCP tool server (stdio): movie_search. Returns standard envelope.
 * Run: npx tsx src/mcp/servers/movie-server.ts
 * For persistent use, prefer: npm run mcp:serve (HTTP server with all tools).
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { handleMovieSearch } from '@/mcp/handlers';

const inputSchema = z.object({
  rewrittenQuery: z.string().min(1),
  city: z.string().min(1),
  date: z.string().min(1),
  movieTitle: z.string().optional(),
  timeWindow: z.string().optional(),
  tickets: z.number().int().min(1),
  format: z.string().optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

async function main() {
  const server = new McpServer({ name: 'clonar-movie-search', version: '1.0.0' });

  server.registerTool(
    'movie_search',
    {
      description: 'Search movie showtimes by capability. Returns normalized envelope (ok, data, snippets, error?).',
      inputSchema,
    },
    async (args) => {
      const parsed = inputSchema.parse(args);
      const envelope = await handleMovieSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Movie search MCP server running on stdio');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

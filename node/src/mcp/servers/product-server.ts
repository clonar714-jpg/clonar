/**
 * MCP tool server (stdio): product_search. Returns standard envelope.
 * Run: npx tsx src/mcp/servers/product-server.ts
 * For persistent use, prefer: npm run mcp:serve (HTTP server with all tools).
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { handleProductSearch } from '@/mcp/handlers';

const inputSchema = z.object({
  query: z.string().min(1),
  rewrittenQuery: z.string().min(1),
  category: z.string().optional(),
  budgetMin: z.number().optional(),
  budgetMax: z.number().optional(),
  brands: z.array(z.string()).optional(),
  attributes: z.record(z.union([z.string(), z.number(), z.boolean()])).optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

async function main() {
  const server = new McpServer({ name: 'clonar-product-search', version: '1.0.0' });

  server.registerTool(
    'product_search',
    {
      description: 'Search products by capability. Returns normalized envelope (ok, data, snippets, error?).',
      inputSchema,
    },
    async (args) => {
      const parsed = inputSchema.parse(args);
      const envelope = await handleProductSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Product search MCP server running on stdio');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

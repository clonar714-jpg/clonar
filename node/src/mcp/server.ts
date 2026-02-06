/**
 * MCP server: exposes the Clonar query pipeline as an MCP tool so clients (Cursor, Claude Desktop, etc.) can call it.
 * Run with: npm run mcp  (or npx tsx src/mcp/server.ts)
 * For stdio: do not use console.log — use console.error for logging.
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { runPipeline } from '@/services/orchestrator';
import { getPipelineDeps } from '@/services/pipeline-deps';
import type { QueryContext, QueryMode } from '@/types/core';

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function normalizeMode(raw: unknown): QueryMode {
  if (raw === 'deep' || raw === 'pro') return 'deep';
  return 'quick';
}

function buildContext(params: { message: string; history?: string[]; mode?: string }): QueryContext {
  const message = params.message.trim();
  let history: string[] = [];
  if (Array.isArray(params.history)) {
    history = params.history.filter((h): h is string => isNonEmptyString(h)).map((h) => h.trim()).slice(-5);
  }
  const mode = normalizeMode(params.mode);
  return { message, history, mode };
}

async function main() {
  const server = new McpServer({
    name: 'clonar',
    version: '1.0.0',
  });

  const inputSchema = z.object({
    message: z.string().min(1).describe('User question (e.g. "Hotels in NYC downtown and things to do in Philadelphia")'),
    history: z.array(z.string()).optional().describe('Optional previous messages in the conversation'),
    mode: z.enum(['quick', 'deep']).optional().describe('quick = fast single pass; deep = research + critique'),
  });

  server.registerTool(
    'clonar_query',
    {
      description: 'Run the Clonar search/answer pipeline for a user question (hotels, flights, products, web).',
      inputSchema,
    },
    async ({ message, history, mode }) => {
      try {
        const ctx = buildContext({ message, history, mode });
        const deps = getPipelineDeps();
        const result = await runPipeline(ctx, deps);

        const summary = result.summary ?? '';
        const vertical = result.vertical;
        const citationsCount = result.citations?.length ?? 0;
        const text = [
          `[Clonar · ${vertical}]`,
          '',
          summary,
          '',
          citationsCount > 0 ? `Sources: ${citationsCount} citation(s).` : '',
        ]
          .filter(Boolean)
          .join('\n');

        return {
          content: [{ type: 'text' as const, text }],
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error('clonar_query tool error:', msg);
        return {
          content: [{ type: 'text' as const, text: `Error: ${msg}` }],
          isError: true,
        };
      }
    },
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Clonar MCP server running on stdio');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

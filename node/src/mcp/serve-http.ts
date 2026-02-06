/**
 * Persistent HTTP MCP server: all 5 capability tools on one long-lived process.
 * Run: npm run mcp:serve  (or npx tsx src/mcp/serve-http.ts)
 * No spawn per request; clients connect to this URL and reuse the connection.
 */
import path from 'path';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import {
  handleProductSearch,
  handleHotelSearch,
  handleFlightSearch,
  handleMovieSearch,
  handleWeatherSearch,
} from '@/mcp/handlers';

const productInputSchema = z.object({
  query: z.string().min(1),
  rewrittenQuery: z.string().min(1),
  category: z.string().optional(),
  budgetMin: z.number().optional(),
  budgetMax: z.number().optional(),
  brands: z.array(z.string()).optional(),
  attributes: z.record(z.union([z.string(), z.number(), z.boolean()])).optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

const hotelInputSchema = z.object({
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

const flightInputSchema = z.object({
  rewrittenQuery: z.string().min(1),
  origin: z.string().min(1),
  destination: z.string().min(1),
  departDate: z.string().min(1),
  returnDate: z.string().optional(),
  adults: z.number().int().min(1),
  cabin: z.enum(['economy', 'premium', 'business', 'first']).optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

const movieInputSchema = z.object({
  rewrittenQuery: z.string().min(1),
  city: z.string().min(1),
  date: z.string().min(1),
  movieTitle: z.string().optional(),
  timeWindow: z.string().optional(),
  tickets: z.number().int().min(1),
  format: z.string().optional(),
  preferenceContext: z.union([z.string(), z.array(z.string())]).optional(),
});

const weatherInputSchema = z.object({
  location: z.string().min(1),
  date: z.string().min(1),
});

function buildMcpServer(): McpServer {
  const server = new McpServer({ name: 'clonar-capability-server', version: '1.0.0' });

  server.registerTool(
    'product_search',
    { description: 'Search products by capability. Returns normalized envelope.', inputSchema: productInputSchema },
    async (args) => {
      const parsed = productInputSchema.parse(args);
      const envelope = await handleProductSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  server.registerTool(
    'hotel_search',
    { description: 'Search hotels by capability. Returns normalized envelope.', inputSchema: hotelInputSchema },
    async (args) => {
      const parsed = hotelInputSchema.parse(args);
      const envelope = await handleHotelSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  server.registerTool(
    'flight_search',
    { description: 'Search flights by capability. Returns normalized envelope.', inputSchema: flightInputSchema },
    async (args) => {
      const parsed = flightInputSchema.parse(args);
      const envelope = await handleFlightSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  server.registerTool(
    'movie_search',
    { description: 'Search movie showtimes by capability. Returns normalized envelope.', inputSchema: movieInputSchema },
    async (args) => {
      const parsed = movieInputSchema.parse(args);
      const envelope = await handleMovieSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  server.registerTool(
    'weather_search',
    { description: 'Get weather for a location and date. Returns normalized envelope.', inputSchema: weatherInputSchema },
    async (args) => {
      const parsed = weatherInputSchema.parse(args);
      const envelope = await handleWeatherSearch(parsed);
      return { content: [{ type: 'text' as const, text: JSON.stringify(envelope) }] };
    },
  );

  return server;
}

const MCP_PORT = process.env.MCP_HTTP_PORT ? parseInt(process.env.MCP_HTTP_PORT, 10) : 3100;
const app = createMcpExpressApp({ host: '0.0.0.0' });
const server = buildMcpServer();

app.post('/mcp', async (req, res) => {
  try {
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
    res.on('close', () => {
      transport.close();
    });
  } catch (err) {
    console.error('MCP HTTP request error:', err);
    if (!res.headersSent) {
      res.status(500).json({ jsonrpc: '2.0', error: { code: -32603, message: 'Internal server error' }, id: null });
    }
  }
});

app.get('/mcp', (_req, res) => {
  res.writeHead(405).end(JSON.stringify({ jsonrpc: '2.0', error: { code: -32000, message: 'Method not allowed' }, id: null }));
});

app.listen(MCP_PORT, () => {
  console.error(`Clonar MCP HTTP server listening on port ${MCP_PORT} (persistent)`);
});

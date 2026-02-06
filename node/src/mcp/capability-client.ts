/**
 * MCP capability client: call tools by CAPABILITY (product_search, hotel_search, flight_search, movie_search).
 * By default uses in-process handlers (no spawn, no network). When MCP_SERVER_URL is set, reuses one HTTP client.
 * All tools return the standard envelope; we map to result or throw with retryable for app retry/fallback.
 */
import path from 'path';
import { fileURLToPath } from 'url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import {
  handleProductSearch,
  handleHotelSearch,
  handleFlightSearch,
  handleMovieSearch,
  handleWeatherSearch,
} from '@/mcp/handlers';
import type {
  ProductSearchToolInput,
  ProductSearchToolResult,
  HotelSearchToolInput,
  HotelSearchToolResult,
  FlightSearchToolInput,
  FlightSearchToolResult,
  MovieSearchToolInput,
  MovieSearchToolResult,
  WeatherSearchToolInput,
  WeatherSearchToolResult,
} from '@/mcp/tool-contract';
import type { McpToolEnvelope } from '@/mcp/envelope';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const nodeDir = path.resolve(__dirname, '..', '..');

/** Thrown when tool returns ok: false; app can use retryable for retry/fallback. */
export class McpToolError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly retryable: boolean,
  ) {
    super(message);
    this.name = 'McpToolError';
  }
}

function parseEnvelope(raw: string): McpToolEnvelope {
  const envelope = JSON.parse(raw) as McpToolEnvelope;
  if (envelope && typeof envelope.ok === 'boolean') return envelope;
  throw new McpToolError('Invalid MCP tool response', 'INVALID_ENVELOPE', false);
}

function envelopeToResultOrThrow<T>(
  envelope: McpToolEnvelope,
  mapOk: () => T,
): T {
  if (envelope.ok) return mapOk();
  const err = envelope.error;
  throw new McpToolError(
    err?.message ?? 'Tool failed',
    err?.code ?? 'UNKNOWN',
    err?.retryable ?? false,
  );
}

/** In-process: no spawn, no network. */
async function callProductSearchInProcess(input: ProductSearchToolInput): Promise<McpToolEnvelope> {
  return handleProductSearch(input);
}

async function callHotelSearchInProcess(input: HotelSearchToolInput): Promise<McpToolEnvelope> {
  return handleHotelSearch(input);
}

async function callFlightSearchInProcess(input: FlightSearchToolInput): Promise<McpToolEnvelope> {
  return handleFlightSearch(input);
}

async function callMovieSearchInProcess(input: MovieSearchToolInput): Promise<McpToolEnvelope> {
  return handleMovieSearch(input);
}

async function callWeatherSearchInProcess(input: WeatherSearchToolInput): Promise<McpToolEnvelope> {
  return handleWeatherSearch(input);
}

/** Reusable HTTP client for persistent MCP server. */
let sharedClient: Client | null = null;
let sharedTransport: StreamableHTTPClientTransport | null = null;

async function getSharedHttpClient(): Promise<{ client: Client; transport: StreamableHTTPClientTransport }> {
  const url = process.env.MCP_SERVER_URL;
  if (!url) throw new Error('MCP_SERVER_URL is not set');
  if (sharedClient && sharedTransport) return { client: sharedClient, transport: sharedTransport };
  const transport = new StreamableHTTPClientTransport(new URL(url));
  const client = new Client({ name: 'clonar-app', version: '1.0.0' });
  await client.connect(transport);
  sharedTransport = transport;
  sharedClient = client;
  return { client, transport };
}

function getTextFromToolResult(result: Awaited<ReturnType<Client['callTool']>>): string {
  const first = result.content?.[0];
  if (first && first.type === 'text') return first.text;
  if (result.isError && first && 'text' in first) return first.text;
  throw new McpToolError('MCP tool did not return text content', 'INVALID_RESPONSE', false);
}

async function callToolOverHttp(
  toolName: string,
  args: Record<string, unknown>,
): Promise<McpToolEnvelope> {
  const { client } = await getSharedHttpClient();
  const result = await client.callTool({ name: toolName, arguments: args });
  const text = getTextFromToolResult(result);
  return parseEnvelope(text);
}

function useHttpServer(): boolean {
  const v = process.env.MCP_SERVER_URL;
  return typeof v === 'string' && v.trim().length > 0;
}

/** Call tool once; on ok: false and retryable, retry once. */
async function getEnvelopeWithRetry(
  getEnvelope: () => Promise<McpToolEnvelope>,
): Promise<McpToolEnvelope> {
  const envelope = await getEnvelope();
  if (envelope.ok) return envelope;
  if (envelope.error?.retryable) {
    const retry = await getEnvelope();
    return retry;
  }
  return envelope;
}

/**
 * Call product_search by capability. Returns normalized products and snippets.
 * Uses in-process handlers when MCP_SERVER_URL is not set; otherwise reuses HTTP client.
 */
export async function callProductSearch(
  input: ProductSearchToolInput,
): Promise<ProductSearchToolResult> {
  const envelope = await getEnvelopeWithRetry(() =>
    useHttpServer()
      ? callToolOverHttp('product_search', input as unknown as Record<string, unknown>)
      : callProductSearchInProcess(input),
  );
  return envelopeToResultOrThrow(envelope, () => ({
    products: envelope.data && 'products' in envelope.data ? envelope.data.products : [],
    snippets: envelope.snippets ?? [],
  }));
}

/**
 * Call hotel_search by capability. Returns normalized hotels and snippets.
 */
export async function callHotelSearch(input: HotelSearchToolInput): Promise<HotelSearchToolResult> {
  const envelope = await getEnvelopeWithRetry(() =>
    useHttpServer()
      ? callToolOverHttp('hotel_search', input as unknown as Record<string, unknown>)
      : callHotelSearchInProcess(input),
  );
  return envelopeToResultOrThrow(envelope, () => ({
    hotels: envelope.data && 'hotels' in envelope.data ? envelope.data.hotels : [],
    snippets: envelope.snippets ?? [],
  }));
}

/**
 * Call flight_search by capability. Returns normalized flights and snippets.
 */
export async function callFlightSearch(
  input: FlightSearchToolInput,
): Promise<FlightSearchToolResult> {
  const envelope = await getEnvelopeWithRetry(() =>
    useHttpServer()
      ? callToolOverHttp('flight_search', input as unknown as Record<string, unknown>)
      : callFlightSearchInProcess(input),
  );
  return envelopeToResultOrThrow(envelope, () => ({
    flights: envelope.data && 'flights' in envelope.data ? envelope.data.flights : [],
    snippets: envelope.snippets ?? [],
  }));
}

/**
 * Call movie_search by capability. Returns normalized showtimes and snippets.
 */
export async function callMovieSearch(
  input: MovieSearchToolInput,
): Promise<MovieSearchToolResult> {
  const envelope = await getEnvelopeWithRetry(() =>
    useHttpServer()
      ? callToolOverHttp('movie_search', input as unknown as Record<string, unknown>)
      : callMovieSearchInProcess(input),
  );
  return envelopeToResultOrThrow(envelope, () => ({
    showtimes: envelope.data && 'showtimes' in envelope.data ? envelope.data.showtimes : [],
    snippets: envelope.snippets ?? [],
  }));
}

/**
 * Call weather_search by capability. Returns normalized weather for location/date.
 */
export async function callWeatherSearch(
  input: WeatherSearchToolInput,
): Promise<WeatherSearchToolResult> {
  const envelope = await getEnvelopeWithRetry(() =>
    useHttpServer()
      ? callToolOverHttp('weather_search', input as unknown as Record<string, unknown>)
      : callWeatherSearchInProcess(input),
  );
  return envelopeToResultOrThrow(envelope, () => ({
    weather: (envelope.data as { weather: WeatherSearchToolResult['weather'] }).weather,
    snippets: envelope.snippets ?? [],
  }));
}

/** Optional: for backward compatibility when passing server config (ignored when using in-process or MCP_SERVER_URL). */
export type CapabilityServerConfig = {
  command: string;
  args: string[];
  cwd?: string;
};

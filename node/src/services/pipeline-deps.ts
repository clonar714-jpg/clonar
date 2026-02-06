// src/services/pipeline-deps.ts — shared pipeline dependencies for HTTP route and MCP server
import type { OrchestratorDeps } from '@/services/orchestrator';
import { SqlCatalogProvider } from '@/services/providers/catalog/sql-catalog';
import { HybridProductRetriever } from '@/services/providers/catalog/product-retriever-hybrid';
import { SqlHotelProvider } from '@/services/providers/hotels/sql-hotel';
import { HybridHotelRetriever } from '@/services/providers/hotels/hotel-retriever-hybrid';
import { SqlFlightProvider } from '@/services/providers/flights/sql-flight';
import { HybridFlightRetriever } from '@/services/providers/flights/flight-retriever-hybrid';
import { SqlMovieProvider } from '@/services/providers/movies/sql-movie';
import { HybridMovieRetriever } from '@/services/providers/movies/movie-retriever-hybrid';
import { SimpleEmbedder } from '@/services/providers/web/simple-embedder';
import { SemanticPassageReranker } from '@/services/passage-reranker';
import { McpProductRetriever } from '@/mcp/retrievers/mcp-product-retriever';
import { McpHotelRetriever } from '@/mcp/retrievers/mcp-hotel-retriever';
import { McpFlightRetriever } from '@/mcp/retrievers/mcp-flight-retriever';
import { McpMovieRetriever } from '@/mcp/retrievers/mcp-movie-retriever';

let cachedDeps: OrchestratorDeps | null = null;

/** When set (e.g. "1" or "true"), product/hotel/flight/movie retrievers use MCP capability tools. */
function useMcpRetrievers(): boolean {
  const v = process.env.USE_MCP_RETRIEVERS;
  return v === '1' || v === 'true' || v === 'yes';
}

/**
 * Returns shared pipeline dependencies (retrievers). Used by the HTTP query route and the MCP server.
 * When USE_MCP_RETRIEVERS=1, product/hotel/flight use MCP tool servers (capability-based); app receives normalized results only.
 */
export function getPipelineDeps(): OrchestratorDeps {
  if (cachedDeps) return cachedDeps;

  const sqlCatalog = new SqlCatalogProvider();
  const sqlHotel = new SqlHotelProvider();
  const sqlFlight = new SqlFlightProvider();
  const sqlMovie = new SqlMovieProvider();
  const simpleEmbedder = new SimpleEmbedder(64);

  const useMcp = useMcpRetrievers();

  cachedDeps = {
    productRetriever: useMcp
      ? new McpProductRetriever()
      : new HybridProductRetriever(sqlCatalog, simpleEmbedder, {
          bm25Weight: 0.6,
          denseWeight: 0.4,
          maxItems: 20,
        }),
    hotelRetriever: useMcp
      ? new McpHotelRetriever()
      : new HybridHotelRetriever(sqlHotel, simpleEmbedder, {
          bm25Weight: 0.6,
          denseWeight: 0.4,
          maxItems: 20,
        }),
    flightRetriever: useMcp
      ? new McpFlightRetriever()
      : new HybridFlightRetriever(sqlFlight, simpleEmbedder, {
          bm25Weight: 0.6,
          denseWeight: 0.4,
          maxItems: 20,
        }),
    movieRetriever: useMcp
      ? new McpMovieRetriever()
      : new HybridMovieRetriever(sqlMovie, simpleEmbedder, {
          bm25Weight: 0.6,
          denseWeight: 0.4,
          maxItems: 20,
        }),
  };
  return cachedDeps;
}

/** Cached hybrid-only deps for MCP handlers/servers. Avoids circular dependency when app uses MCP retrievers. */
let cachedMcpHandlersDeps: OrchestratorDeps | null = null;

/**
 * Returns retrievers for MCP server/handler use only. Always uses hybrid retrievers (never MCP).
 * Use this inside MCP in-process handlers and inside MCP HTTP/stdio servers so they never get MCP retrievers.
 */
export function getRetrieversForMcpHandlers(): OrchestratorDeps {
  if (cachedMcpHandlersDeps) return cachedMcpHandlersDeps;
  const sqlCatalog = new SqlCatalogProvider();
  const sqlHotel = new SqlHotelProvider();
  const sqlFlight = new SqlFlightProvider();
  const sqlMovie = new SqlMovieProvider();
  const simpleEmbedder = new SimpleEmbedder(64);
  const passageReranker = new SemanticPassageReranker(simpleEmbedder);
  cachedMcpHandlersDeps = {
    embedder: simpleEmbedder,
    passageReranker,
    productRetriever: new HybridProductRetriever(sqlCatalog, simpleEmbedder, {
      bm25Weight: 0.6,
      denseWeight: 0.4,
      maxItems: 20,
    }),
    hotelRetriever: new HybridHotelRetriever(sqlHotel, simpleEmbedder, {
      bm25Weight: 0.6,
      denseWeight: 0.4,
      maxItems: 20,
    }),
    flightRetriever: new HybridFlightRetriever(sqlFlight, simpleEmbedder, {
      bm25Weight: 0.6,
      denseWeight: 0.4,
      maxItems: 20,
    }),
    movieRetriever: new HybridMovieRetriever(sqlMovie, simpleEmbedder, {
      bm25Weight: 0.6,
      denseWeight: 0.4,
      maxItems: 20,
    }),
  };
  return cachedMcpHandlersDeps;
}

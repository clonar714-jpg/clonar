// Pipeline dependencies for the query flow (health + /api/query only).
import type { OrchestratorDeps } from '@/services/orchestrator';
import { SqlCatalogProvider } from '@/services/providers/catalog/sql-catalog';
import { SerpCatalogProvider } from '@/services/providers/catalog/serp-catalog';
import { HybridProductRetriever } from '@/services/providers/catalog/product-retriever-hybrid';
import { GoogleMapsHotelProvider } from '@/services/providers/hotels/google-maps-hotel';
import { SerpHotelProvider } from '@/services/providers/hotels/serp-hotel';
import { HybridHotelRetriever } from '@/services/providers/hotels/hotel-retriever-hybrid';
import { SqlFlightProvider } from '@/services/providers/flights/sql-flight';
import { HybridFlightRetriever } from '@/services/providers/flights/flight-retriever-hybrid';
import { SqlMovieProvider } from '@/services/providers/movies/sql-movie';
import { HybridMovieRetriever } from '@/services/providers/movies/movie-retriever-hybrid';
import { SimpleEmbedder } from '@/services/providers/web/simple-embedder';
import { SemanticPassageReranker } from '@/services/passage-reranker';

let cachedDeps: OrchestratorDeps | null = null;

function useSerpProviders(): boolean {
  return !!process.env.SERP_API_KEY;
}

export function getPipelineDeps(): OrchestratorDeps {
  if (cachedDeps) return cachedDeps;

  const sqlCatalog = new SqlCatalogProvider();
  const serpCatalog = new SerpCatalogProvider();
  const catalogProvider = useSerpProviders() ? serpCatalog : sqlCatalog;
  const googleMapsHotel = new GoogleMapsHotelProvider();
  const serpHotel = new SerpHotelProvider();
  const hotelProvider = useSerpProviders() ? serpHotel : googleMapsHotel;
  const sqlFlight = new SqlFlightProvider();
  const sqlMovie = new SqlMovieProvider();
  const simpleEmbedder = new SimpleEmbedder(64);

  cachedDeps = {
    productRetriever: new HybridProductRetriever(catalogProvider, simpleEmbedder, {
      bm25Weight: 0.6,
      denseWeight: 0.4,
      maxItems: 20,
    }),
    hotelRetriever: new HybridHotelRetriever(hotelProvider, simpleEmbedder, {
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
  return cachedDeps;
}

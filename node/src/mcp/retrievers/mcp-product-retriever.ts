/**
 * MCP-backed product retriever: calls product_search by CAPABILITY.
 * Provider selection, auth, request formatting, and response normalization
 * live inside the MCP tool server; the app receives normalized results only.
 */
import { ProductRetriever } from '@/services/providers/catalog/product-retriever';
import type { ProductFilters } from '@/types/verticals';
import { callProductSearch } from '@/mcp/capability-client';

const DEFAULT_MAX_ITEMS = 20;

export class McpProductRetriever implements ProductRetriever {
  constructor() {}

  getMaxItems?(): number {
    return DEFAULT_MAX_ITEMS;
  }

  async searchProducts(
    filters: ProductFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ products: import('@/services/providers/catalog/catalog-provider').Product[]; snippets: import('@/services/providers/retrieval-types').RetrievedSnippet[] }> {
    const input = {
      query: filters.query,
      rewrittenQuery: filters.rewrittenQuery,
      ...(filters.category != null && { category: filters.category }),
      ...(filters.budgetMin != null && { budgetMin: filters.budgetMin }),
      ...(filters.budgetMax != null && { budgetMax: filters.budgetMax }),
      ...(filters.brands != null && { brands: filters.brands }),
      ...(filters.attributes != null && { attributes: filters.attributes }),
      ...(filters.preferenceContext != null && { preferenceContext: filters.preferenceContext }),
    };
    return callProductSearch(input);
  }
}

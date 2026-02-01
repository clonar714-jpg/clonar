import { ProductFilters } from '@/types/verticals';
import { Product } from './catalog-provider';
import type { RetrievedSnippet } from '../retrieval-types';

export interface ProductRetriever {
  searchProducts(
    filters: ProductFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{
    products: Product[];
    snippets: RetrievedSnippet[];
  }>;
  /** Optional: max items cap used by this retriever (for retrieval-quality heuristics). */
  getMaxItems?(): number;
}

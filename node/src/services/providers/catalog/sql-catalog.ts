// Stub SQL catalog provider. Replace with real DB in production.
import { ProductFilters } from '@/types/verticals';
import { Product, CatalogProvider } from './catalog-provider';

export class SqlCatalogProvider implements CatalogProvider {
  readonly name = 'sql-catalog';

  async searchProducts(_filters: ProductFilters): Promise<Product[]> {
    return [];
  }
}

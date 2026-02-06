// src/services/providers/catalog/catalog-provider.ts
// Canonical product shape for all providers. Aligns with e‑commerce / Perplexity-style
// display: brand, category, media, availability, specs, compare price.
import { ProductFilters } from '@/types/verticals';

export interface Product {
  id: string;
  title: string;
  description?: string;
  price: number;
  currency: string;
  /** Compare-at / list price when on sale. */
  compareAtPrice?: number;
  /** Primary image for list/card. */
  imageUrl?: string;
  /** Additional images for detail/gallery. */
  imageUrls?: string[];
  rating?: number;
  reviewCount?: number;
  merchantId: string;
  merchantName: string;
  /** External link or your PDP. */
  productUrl?: string;
  /** Brand name (e.g. "Nike", "Sony"). */
  brand?: string;
  /** Category or product type (e.g. "Running Shoes", "Electronics"). */
  category?: string;
  /** SKU or variant identifier. */
  sku?: string;
  /** In stock / available for purchase. */
  inStock?: boolean;
  /** Key-value specs (e.g. { "Color": "Black", "Size": "M" }). */
  attributes?: Record<string, string | number | boolean>;
}

export interface CatalogProvider {
  name: string;
  searchProducts(filters: ProductFilters): Promise<Product[]>;
}

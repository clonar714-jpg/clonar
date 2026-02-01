// src/services/providers/catalog/catalog-provider.ts
import { ProductFilters } from '@/types/verticals';

export interface Product {
  id: string;
  title: string;
  description?: string;
  price: number;
  currency: string;
  imageUrl?: string;
  rating?: number;
  reviewCount?: number;
  merchantId: string;
  merchantName: string;
  productUrl?: string;       // external link or your PDP
}

export interface CatalogProvider {
  name: string;
  searchProducts(filters: ProductFilters): Promise<Product[]>;
}

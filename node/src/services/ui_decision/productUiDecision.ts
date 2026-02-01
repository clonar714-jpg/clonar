import type { UiDecision } from '@/types/core';
import type { Product } from '@/services/providers/catalog/catalog-provider';

export function buildProductUiDecision(
  query: string,
  products: Product[],
): UiDecision {
  if (!products.length) {
    return {
      layout: 'list',
      showMap: false,
      highlightImages: false,
      showCards: false,
      primaryActions: [],
    };
  }

  const single = products.length === 1;

  const looksLikeModelQuery =
    /review|specs|specifications|vs|compare|difference|best/i.test(query) ||
    /\b\d{4}\b/.test(query);

  if (single && looksLikeModelQuery) {
    return {
      layout: 'detail',
      showMap: false,
      highlightImages: true,
      showCards: true,
      primaryActions: ['buy', 'website'],
    };
  }

  return {
    layout: 'list',
    showMap: false,
    highlightImages: false,
    showCards: true,
    primaryActions: ['buy', 'website'],
  };
}

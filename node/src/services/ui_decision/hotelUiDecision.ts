import type { UiDecision } from '@/types/core';
import type { Hotel } from '@/services/providers/hotels/hotel-provider';

export function buildHotelUiDecision(
  query: string,
  hotels: Hotel[],
): UiDecision {
  if (!hotels.length) {
    return {
      layout: 'list',
      showMap: false,
      highlightImages: false,
      showCards: false,
      primaryActions: [],
    };
  }

  const manyHotels = hotels.length >= 2;
  const specific = looksLikeSpecificHotelQuery(query, hotels);

  if (specific) {
    return {
      layout: 'detail',
      showMap: false,
      highlightImages: true,
      showCards: true,
      primaryActions: ['book', 'website', 'call', 'directions'],
    };
  }

  return {
    layout: 'list',
    showMap: manyHotels && hotels.some((h) => h.lat && h.lng),
    highlightImages: false,
    showCards: true,
    primaryActions: ['book', 'website', 'directions'],
  };
}

function looksLikeSpecificHotelQuery(
  q: string,
  hotels: Hotel[],
): boolean {
  const lower = q.toLowerCase().trim();
  if (!lower) return false;

  if (hotels.length === 1) return true;

  const top = hotels[0];
  const name = (top.name ?? '').toLowerCase();
  if (name && lower.includes(name)) return true;

  const brandTokens = ['marriott', 'hilton', 'kimpton', 'hyatt', 'ritz'];
  if (lower.includes('hotel') && brandTokens.some((b) => lower.includes(b))) {
    return true;
  }

  return false;
}

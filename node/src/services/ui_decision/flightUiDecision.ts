import type { UiDecision } from '@/types/core';
import type { Flight } from '@/services/providers/flights/flight-provider';

export function buildFlightUiDecision(
  _query: string,
  flights: Flight[],
): UiDecision {
  if (!flights.length) {
    return {
      layout: 'list',
      showMap: false,
      highlightImages: false,
      showCards: false,
      primaryActions: [],
    };
  }

  return {
    layout: 'list',
    showMap: false,
    highlightImages: false,
    showCards: true,
    primaryActions: ['buy'],
  };
}

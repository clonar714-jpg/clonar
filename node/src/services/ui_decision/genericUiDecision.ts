import type { UiDecision } from '@/types/core';

export function buildGenericUiDecision(query: string): UiDecision {
  const looksVisual =
    /design|ideas|inspiration|examples|logo|interior|exterior|architecture|diagram|layout/i.test(
      query,
    );

  return {
    layout: 'list',
    showMap: false,
    highlightImages: looksVisual,
    showCards: false,
    primaryActions: [],
  };
}

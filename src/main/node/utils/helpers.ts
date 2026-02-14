/** General helpers. */
export function truncate(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max) + '...';
}

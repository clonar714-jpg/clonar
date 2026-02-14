/**
 * ChatGPT-style User Memory: explicit facts + structured slots, keyed by userId.
 * No vector DB; stored facts and slots are injected into context each request.
 */

import type { UserMemory } from "@/types/core";

const store = new Map<string, UserMemory>();

function hasAnyContent(m: UserMemory): boolean {
  return (
    (m.brands?.length ?? 0) > 0 ||
    (m.dietary?.length ?? 0) > 0 ||
    (m.hobbies?.length ?? 0) > 0 ||
    (m.projects?.length ?? 0) > 0 ||
    (m.facts?.length ?? 0) > 0 ||
    !!m.birthday ||
    !!m.location
  );
}

export async function getUserMemory(userId: string): Promise<UserMemory | null> {
  const m = store.get(userId);
  return m ? { ...m, facts: m.facts ? [...m.facts] : undefined } : null;
}

export async function updateUserMemory(
  userId: string,
  updates: Partial<UserMemory>,
): Promise<void> {
  const current = store.get(userId) ?? {};
  const next: UserMemory = {
    brands: updates.brands ?? current.brands,
    dietary: updates.dietary ?? current.dietary,
    hobbies: updates.hobbies ?? current.hobbies,
    projects: updates.projects ?? current.projects,
    facts: updates.facts ?? current.facts,
    birthday: updates.birthday !== undefined ? updates.birthday : current.birthday,
    location: updates.location !== undefined ? updates.location : current.location,
  };
  if (hasAnyContent(next)) store.set(userId, next);
}

/** Add one fact (ChatGPT-style "remember that X"). Deduplicates by normalized text. */
export async function addMemoryFact(userId: string, fact: string): Promise<void> {
  const trimmed = fact.trim();
  if (!trimmed) return;
  const current = store.get(userId) ?? {};
  const list = current.facts ?? [];
  const normalized = trimmed.toLowerCase();
  if (list.some((f) => f.trim().toLowerCase() === normalized)) return;
  const next = { ...current, facts: [...list, trimmed] };
  store.set(userId, next);
}

/** Remove one fact by exact text or by index (0-based). */
export async function removeMemoryFact(
  userId: string,
  factOrIndex: string | number,
): Promise<boolean> {
  const current = store.get(userId);
  if (!current?.facts?.length) return false;
  let nextFacts: string[];
  if (typeof factOrIndex === "number") {
    if (factOrIndex < 0 || factOrIndex >= current.facts.length) return false;
    nextFacts = current.facts.filter((_, i) => i !== factOrIndex);
  } else {
    const match = current.facts.find((f) => f.trim() === String(factOrIndex).trim());
    if (!match) return false;
    nextFacts = current.facts.filter((f) => f !== match);
  }
  const next: UserMemory = { ...current, facts: nextFacts.length > 0 ? nextFacts : undefined };
  if (hasAnyContent(next)) store.set(userId, next);
  else store.delete(userId);
  return true;
}

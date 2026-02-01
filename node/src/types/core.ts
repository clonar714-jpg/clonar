// src/types/core.ts
export type Vertical = 'product' | 'hotel' | 'flight' | 'movie' | 'other';
export type Intent = 'browse' | 'compare' | 'buy' | 'book';

export type QueryMode = 'quick' | 'deep';

/**
 * UI decision: backend emits HINTS and CAPABILITIES (available layouts, data richness, maps possible).
 * Frontend chooses final presentation within those constraints. Backend does not prescribe exact UI.
 * Keeps UI evolvable without backend rewrites.
 */
export type UiDecision = {
  layout: 'list' | 'detail';
  showMap: boolean;
  highlightImages: boolean;
  showCards: boolean;
  primaryActions: Array<'book' | 'website' | 'call' | 'directions' | 'buy' | 'watch'>;
};

export interface QueryContext {
  message: string;
  history: string[];
  userId?: string;
  /** optional, default 'quick' */
  mode?: QueryMode;
}

/** Optional per-vertical filter blobs for a candidate (accepts full filter types from verticals). */
export interface PlanCandidateProductFilters {
  query?: string;
  category?: string;
  budgetMin?: number;
  budgetMax?: number;
  brands?: string[];
  attributes?: Record<string, string | number | boolean>;
}
export interface PlanCandidateHotelFilters {
  destination?: string;
  checkIn?: string;
  checkOut?: string;
  guests?: number;
  budgetMin?: number;
  budgetMax?: number;
  area?: string;
  amenities?: string[];
}
export interface PlanCandidateFlightFilters {
  origin?: string;
  destination?: string;
  departDate?: string;
  returnDate?: string;
  adults?: number;
  cabin?: string;
}
export interface PlanCandidateMovieFilters {
  city?: string;
  movieTitle?: string;
  date?: string;
  timeWindow?: string;
  tickets?: number;
  format?: string;
}

/** Optional candidate for multi-vertical routing (primary + close runner-up). */
export interface PlanCandidate {
  vertical: Vertical;
  intent: Intent;
  score: number;
  /** Per-vertical preference context when decomposed (e.g. "cheap", "quiet near airport"); downstream may ignore. */
  preferenceContext?: string;
  productFilters?: PlanCandidateProductFilters;
  hotelFilters?: PlanCandidateHotelFilters;
  flightFilters?: PlanCandidateFlightFilters;
  movieFilters?: PlanCandidateMovieFilters;
}

/** Extracted entities and locations for structured anchors (rewrite/filters). */
export interface ExtractedEntities {
  entities?: string[];
  locations?: string[];
  concepts?: string[];
}

/** Ambiguous term with possible interpretations (e.g. "Apple" → company vs fruit). */
export interface AmbiguityInfo {
  term: string;
  interpretations: string[];
  /** Resolved interpretation if we picked one from context. */
  resolved?: string;
}

export interface BasePlan {
  vertical: Vertical;
  intent: Intent;
  rewrittenPrompt: string;
  /** Filled by understandQuery for soft routing; best candidate is plan.vertical. */
  candidates?: PlanCandidate[];
  /** User preference context (free-form). Carried through retrieval and summarization; not a filter schema. */
  preferenceContext?: string | string[];
  /** Per-vertical decomposed context when multi-vertical (e.g. flight + hotel with different locations). Each vertical gets only the slice of the query that applies to it. */
  decomposedContext?: Partial<Record<Vertical, string>>;
  /** Extracted entities and locations for rewrite/filter anchors. */
  entities?: ExtractedEntities;
  /** When a term has multiple interpretations (e.g. "Apple"); answer can disambiguate. */
  ambiguity?: AmbiguityInfo;
  /** Per-vertical search-oriented reformulations (synonyms, key terms) for retrieval fan-out. */
  searchQueries?: Partial<Record<Vertical, string[]>>;
  /** Per-vertical sub-queries for within-vertical fan-out (retrieve per sub-query, then combine). */
  subQueries?: Partial<Record<Vertical, string[]>>;
  /** Time sensitivity (especially for "other"): orchestrator uses for web overview vs encyclopedic retrieval. */
  timeSensitivity?: 'timeless' | 'time_sensitive';
  /** Ordered preference phrases (highest priority first). When results are thin, relaxation can drop lowest-priority first. */
  preferencePriority?: string[];
  /** When set, "airport" etc. are not pinned to a single code; downstream can align after retrieval (e.g. hotel near arrival airport). */
  softConstraints?: { airport?: 'city_only' | 'unspecified' };
}

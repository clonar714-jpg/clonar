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

/** ChatGPT-style Memory: explicit facts + structured slots. Injected into context each request (no vector DB). */
export interface UserMemory {
  brands?: string[];
  dietary?: string[];
  hobbies?: string[];
  projects?: string[];
  /** Explicit "remember that X" facts (ChatGPT-style). */
  facts?: string[];
  /** Resolve "my birthday" (e.g. "2025-03-15" or "March 15"). */
  birthday?: string;
  /** Resolve "where I live" / weather (e.g. "Boston" or "San Francisco"). */
  location?: string;
}

/** One turn in the conversation thread (for Perplexity-style rewrite context). */
export interface ConversationTurn {
  query: string;
  answer: string;
}

export interface QueryContext {
  message: string;
  history: string[];
  userId?: string;
  /** optional, default 'quick' */
  mode?: QueryMode;
  /** For loading/saving session state. Use sessionId ?? userId when calling getSession/saveSession. */
  sessionId?: string;
  /** Conversation thread from session (last N turns) for rewrite/context like Perplexity. Set by route from getSession(). */
  conversationThread?: ConversationTurn[];
  /** Perplexity-style Memory (brands, dietary, hobbies, projects). Set by route when userId present. */
  userMemory?: UserMemory | null;
  /** Last-used filters from session; merged with extracted filters (session default, query overrides). */
  lastHotelFilters?: PlanCandidateHotelFilters;
  lastFlightFilters?: PlanCandidateFlightFilters;
  lastMovieFilters?: PlanCandidateMovieFilters;
  lastProductFilters?: PlanCandidateProductFilters;
  /** A/B: "default" = run rewrite; "none" = skip rewrite, use message as rewrittenPrompt (for online eval). */
  rewriteVariant?: 'default' | 'none';
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
  /** Confidence in [0,1] for this vertical choice (same as score when from classifier; can differ when combined with intent). */
  confidence?: number;
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
  /** Flat list of sub-queries for retrieval (from decomposition). No vertical grouping. */
  subQueries?: string[];
  /** Gated typo correction: confidence in [0,1] for the rewrite; when low, UI may show rewriteAlternatives. */
  rewriteConfidence?: number;
  /** Alternative phrasings when rewrite confidence is low (for "Did you mean?" in UI). */
  rewriteAlternatives?: string[];
  /** Confidence in [0,1] for intent classification (browse/compare/buy/book). */
  intentConfidence?: number;
}

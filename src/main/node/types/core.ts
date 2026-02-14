
export type Vertical = 'product' | 'hotel' | 'flight' | 'movie' | 'other';
export type Intent = 'browse' | 'compare' | 'buy' | 'book';

export type QueryMode = 'quick' | 'deep';


export type UiDecision = {
  layout: 'list' | 'detail';
  showMap: boolean;
  highlightImages: boolean;
  showCards: boolean;
  primaryActions: Array<'book' | 'website' | 'call' | 'directions' | 'buy' | 'watch'>;
  
  answerConfidence?: 'strong' | 'medium' | 'weak';
};


export type UiIntent = {
  preferredLayout: 'answer-first' | 'cards-first' | 'sections';
  expectedVertical?: Vertical;
  confidenceExpectation: 'high' | 'medium' | 'low';
};


export interface UserMemory {
  brands?: string[];
  dietary?: string[];
  hobbies?: string[];
  projects?: string[];
  
  facts?: string[];
 
  birthday?: string;
  
  location?: string;
}


export interface ConversationTurn {
  query: string;
  answer: string;
}

export interface QueryContext {
  message: string;
  history: string[];
  userId?: string;
 
  mode?: QueryMode;
  
  sessionId?: string;
  
  conversationThread?: ConversationTurn[];
  
  userMemory?: UserMemory | null;
  
  lastHotelFilters?: PlanCandidateHotelFilters;
  lastFlightFilters?: PlanCandidateFlightFilters;
  lastMovieFilters?: PlanCandidateMovieFilters;
  lastProductFilters?: PlanCandidateProductFilters;
 
  lastSuccessfulVertical?: Vertical;
  
  lastResultStrength?: 'weak' | 'ok' | 'strong';
  
  rewriteVariant?: 'default' | 'none';
  
  uiIntent?: UiIntent;

  /** When set, the user marked the previous answer as unhelpful; improve for this follow-up. */
  previousFeedback?: { thumb: 'up' | 'down'; reason?: string; comment?: string };
}


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


export interface PlanCandidate {
  vertical: Vertical;
  intent: Intent;
  score: number;
  
  confidence?: number;
  productFilters?: PlanCandidateProductFilters;
  hotelFilters?: PlanCandidateHotelFilters;
  flightFilters?: PlanCandidateFlightFilters;
  movieFilters?: PlanCandidateMovieFilters;
}


export interface ExtractedEntities {
  entities?: string[];
  locations?: string[];
  concepts?: string[];
}


export interface AmbiguityInfo {
  term: string;
  interpretations: string[];
  
  resolved?: string;
}

export interface BasePlan {
  vertical: Vertical;
  intent: Intent;
  rewrittenPrompt: string;
 
  candidates?: PlanCandidate[];
  
  preferenceContext?: string | string[];
  
  decomposedContext?: Partial<Record<Vertical, string>>;
  
  entities?: ExtractedEntities;
  
  ambiguity?: AmbiguityInfo;
 
  searchQueries?: Partial<Record<Vertical, string[]>>;
  
  subQueries?: string[];
  
  rewriteConfidence?: number;
  
  rewriteAlternatives?: string[];
  
  intentConfidence?: number;
}

// Shared retrieval types for RAG / hybrid search layer
export interface RetrievedSnippet {
  id: string;
  title: string;
  url: string;
  text: string;
  score: number;
}

/** Cap on items returned per vertical (keeps prompts small, latency predictable). */
export const MAX_RETRIEVED_ITEMS = 10;
/** Cap on snippets passed to the LLM (primary rank = score when using a reranker). */
export const MAX_RETRIEVED_SNIPPETS = 8;

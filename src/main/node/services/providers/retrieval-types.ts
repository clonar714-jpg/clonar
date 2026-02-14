// Shared retrieval types for RAG / hybrid search layer
export interface RetrievedSnippet {
  id: string;
  title: string;
  url: string;
  text: string;
  score: number;
}

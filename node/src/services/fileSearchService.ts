// src/services/fileSearchService.ts
// ✅ PERPLEXICA-STYLE: Semantic search over user-uploaded files
// Uses embeddings to find relevant file chunks based on query similarity

import { db } from './database';
import { getEmbedding, cosine } from '../embeddings/embeddingClient';
import { Document } from './searchService';

interface FileChunk {
  id: string;
  file_id: string;
  chunk_index: number;
  content: string;
  embedding: number[];
  metadata?: any;
}

interface UserFile {
  id: string;
  user_id: string;
  file_name: string;
  mime_type: string;
  size: number;
  uploaded_at: string;
  storage_path?: string;
}

/**
 * Search user files semantically using embeddings
 * Returns relevant file chunks as Document objects (matching web search format)
 */
export async function searchUserFiles(
  userId: string,
  query: string,
  limit: number = 5
): Promise<Document[]> {
  try {
    // Get all file chunks for the user
    // First get user's files
    const { data: userFiles, error: filesError } = await db.userFiles()
      .select('id')
      .eq('user_id', userId);
    
    if (filesError || !userFiles || userFiles.length === 0) {
      return [];
    }
    
    const fileIds = userFiles.map(f => f.id);
    
    // Get chunks for user's files with file metadata
    const { data: chunks, error: chunksError } = await db.userFileChunks()
      .select(`
        *,
        user_files (
          id,
          file_name,
          mime_type
        )
      `)
      .in('file_id', fileIds);
    
    if (chunksError) {
      console.error('❌ Error fetching user file chunks:', chunksError);
      return [];
    }
    
    if (!chunks || chunks.length === 0) {
      console.log('📁 No user files found for search');
      return [];
    }
    
    // Get query embedding
    const queryEmbedding = await getEmbedding(query);
    if (queryEmbedding.length === 0) {
      console.warn('⚠️ Failed to generate query embedding');
      return [];
    }
    
    // Calculate similarity scores for each chunk
    const scoredChunks = chunks
      .filter((chunk: any) => chunk.embedding && Array.isArray(chunk.embedding))
      .map((chunk: any) => {
        const similarity = cosine(queryEmbedding, chunk.embedding);
        return {
          chunk,
          similarity,
        };
      })
      .filter((item: any) => item.similarity > 0.3) // Minimum similarity threshold
      .sort((a: any, b: any) => b.similarity - a.similarity)
      .slice(0, limit);
    
    console.log(`📁 Found ${scoredChunks.length} relevant file chunks (from ${chunks.length} total)`);
    
    // Convert to Document format (matching web search results)
    const documents: Document[] = scoredChunks.map((item: any) => {
      const chunk = item.chunk;
      const file = chunk.user_files;
      
      return {
        title: `${file.file_name} (chunk ${chunk.chunk_index + 1})`,
        url: `file://${file.id}/${chunk.chunk_index}`, // Virtual URL for file chunks
        content: chunk.content,
        summary: chunk.content.substring(0, 500), // Use first 500 chars as summary
      };
    });
    
    return documents;
  } catch (error: any) {
    console.error('❌ File search error:', error.message);
    return [];
  }
}

/**
 * Check if user has uploaded files
 */
export async function hasUserFiles(userId: string): Promise<boolean> {
  try {
    const { data, error } = await db.userFiles()
      .select('id')
      .eq('user_id', userId)
      .limit(1);
    
    if (error) {
      console.error('❌ Error checking user files:', error);
      return false;
    }
    
    return (data?.length || 0) > 0;
  } catch (error: any) {
    console.error('❌ Error checking user files:', error.message);
    return false;
  }
}


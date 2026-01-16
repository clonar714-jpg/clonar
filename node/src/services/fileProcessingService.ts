// src/services/fileProcessingService.ts
// ✅ PERPLEXICA-STYLE: File processing service for user-uploaded files
// Extracts text from various file formats and chunks them for embedding

import fs from 'fs';
import path from 'path';

/**
 * Extract text content from a file based on its MIME type
 */
export async function extractTextFromFile(
  filePath: string,
  mimeType: string,
  fileName: string
): Promise<string> {
  try {
    const ext = path.extname(fileName).toLowerCase();
    
    // Text files
    if (mimeType.startsWith('text/') || ext === '.txt' || ext === '.md') {
      return fs.readFileSync(filePath, 'utf-8');
    }
    
    // PDF files
    if (mimeType === 'application/pdf' || ext === '.pdf') {
      try {
        const pdfParse = require('pdf-parse');
        const dataBuffer = fs.readFileSync(filePath);
        const data = await pdfParse(dataBuffer);
        return data.text || '';
      } catch (error: any) {
        console.warn(`⚠️ PDF parsing failed for ${fileName}:`, error.message);
        return '';
      }
    }
    
    // Word documents (.docx)
    if (
      mimeType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      ext === '.docx'
    ) {
      try {
        const mammoth = require('mammoth');
        const result = await mammoth.extractRawText({ path: filePath });
        return result.value || '';
      } catch (error: any) {
        console.warn(`⚠️ DOCX parsing failed for ${fileName}:`, error.message);
        return '';
      }
    }
    
    // Plain text fallback
    try {
      return fs.readFileSync(filePath, 'utf-8');
    } catch (error: any) {
      console.warn(`⚠️ Text extraction failed for ${fileName}:`, error.message);
      return '';
    }
  } catch (error: any) {
    console.error(`❌ File processing error for ${fileName}:`, error.message);
    return '';
  }
}

/**
 * Chunk text into smaller pieces for embedding
 * Each chunk should be ~500-1000 tokens (roughly 2000-4000 characters)
 */
export function chunkText(text: string, chunkSize: number = 3000, overlap: number = 200): string[] {
  if (!text || text.trim().length === 0) {
    return [];
  }
  
  const chunks: string[] = [];
  let start = 0;
  
  while (start < text.length) {
    let end = Math.min(start + chunkSize, text.length);
    
    // Try to break at sentence boundary
    if (end < text.length) {
      const lastPeriod = text.lastIndexOf('.', end);
      const lastNewline = text.lastIndexOf('\n', end);
      const breakPoint = Math.max(lastPeriod, lastNewline);
      
      if (breakPoint > start + chunkSize * 0.5) {
        // Only use break point if it's not too early
        end = breakPoint + 1;
      }
    }
    
    const chunk = text.substring(start, end).trim();
    if (chunk.length > 0) {
      chunks.push(chunk);
    }
    
    // Move start forward with overlap
    start = end - overlap;
    if (start >= text.length) break;
  }
  
  return chunks;
}

/**
 * Get file metadata
 */
export function getFileMetadata(filePath: string, fileName: string, mimeType: string) {
  try {
    const stats = fs.statSync(filePath);
    return {
      fileName,
      mimeType,
      size: stats.size,
      uploadedAt: new Date().toISOString(),
    };
  } catch (error: any) {
    return {
      fileName,
      mimeType,
      size: 0,
      uploadedAt: new Date().toISOString(),
    };
  }
}




import fs from 'fs';
import path from 'path';

export async function extractTextFromFile(
  filePath: string,
  mimeType: string,
  fileName: string
): Promise<string> {
  try {
    const ext = path.extname(fileName).toLowerCase();
    
    
    if (mimeType.startsWith('text/') || ext === '.txt' || ext === '.md') {
      return fs.readFileSync(filePath, 'utf-8');
    }
    
    
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


export function chunkText(text: string, chunkSize: number = 3000, overlap: number = 200): string[] {
  if (!text || text.trim().length === 0) {
    return [];
  }
  
  const chunks: string[] = [];
  let start = 0;
  
  while (start < text.length) {
    let end = Math.min(start + chunkSize, text.length);
    
    
    if (end < text.length) {
      const lastPeriod = text.lastIndexOf('.', end);
      const lastNewline = text.lastIndexOf('\n', end);
      const breakPoint = Math.max(lastPeriod, lastNewline);
      
      if (breakPoint > start + chunkSize * 0.5) {
        
        end = breakPoint + 1;
      }
    }
    
    const chunk = text.substring(start, end).trim();
    if (chunk.length > 0) {
      chunks.push(chunk);
    }
    
    
    start = end - overlap;
    if (start >= text.length) break;
  }
  
  return chunks;
}


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


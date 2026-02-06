/**
 * Stub file processing so /api/files routes load.
 * Replace with real extraction (mammoth, pdf-parse, etc.) for production.
 */
import fs from 'fs';

export async function extractTextFromFile(
  filePath: string,
  _mimeType: string,
  _fileName: string
): Promise<string> {
  try {
    return fs.readFileSync(filePath, 'utf-8');
  } catch {
    return '';
  }
}

export function chunkText(text: string, maxChunkSize: number = 500): string[] {
  const chunks: string[] = [];
  let start = 0;
  while (start < text.length) {
    let end = Math.min(start + maxChunkSize, text.length);
    if (end < text.length) {
      const lastSpace = text.lastIndexOf(' ', end);
      if (lastSpace > start) end = lastSpace;
    }
    chunks.push(text.slice(start, end).trim());
    start = end;
  }
  return chunks.filter(Boolean);
}

export function getFileMetadata(
  filePath: string,
  _fileName: string,
  _mimeType: string
): { size: number; uploadedAt: string } {
  try {
    const stat = fs.statSync(filePath);
    return {
      size: stat.size,
      uploadedAt: new Date().toISOString(),
    };
  } catch {
    return { size: 0, uploadedAt: new Date().toISOString() };
  }
}

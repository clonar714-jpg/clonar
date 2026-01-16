// src/routes/files.ts
// ✅ PERPLEXICA-STYLE: API endpoints for user file upload and management

import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { v4 as uuidv4 } from 'uuid';
import { db } from '@/services/database';
import { authenticateToken as verifyToken } from '@/middleware/auth';
import skipAuthInDev from '@/middleware/skipAuthInDev';
import { extractTextFromFile, chunkText, getFileMetadata } from '@/services/fileProcessingService';
import { getEmbeddings } from '@/embeddings/embeddingClient';
import { ApiResponse, AuthenticatedRequest } from '@/types';

const router = express.Router();

// Configure multer for file uploads
const upload = multer({
  dest: './uploads/files',
  limits: {
    fileSize: 50 * 1024 * 1024, // 50MB max
  },
  fileFilter: (req, file, cb) => {
    // Allow text, PDF, and Word documents
    const allowedMimes = [
      'text/plain',
      'text/markdown',
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ];
    
    if (allowedMimes.includes(file.mimetype) || 
        ['.txt', '.md', '.pdf', '.docx'].includes(path.extname(file.originalname).toLowerCase())) {
      cb(null, true);
    } else {
      cb(new Error('File type not supported. Allowed: .txt, .md, .pdf, .docx'));
    }
  },
});

/**
 * POST /api/files/upload
 * Upload a file and process it for semantic search
 */
router.post('/upload', skipAuthInDev(), upload.single('file'), async (req: AuthenticatedRequest, res: express.Response) => {
  try {
    if (!req.file) {
      const response: ApiResponse = {
        success: false,
        error: 'No file uploaded',
      };
      return res.status(400).json(response);
    }

    const userId = req.user?.id || 'anonymous';
    const filePath = req.file.path;
    const fileName = req.file.originalname;
    const mimeType = req.file.mimetype;

    console.log(`📁 Processing file upload: ${fileName} (${mimeType})`);

    // Extract text from file
    const text = await extractTextFromFile(filePath, mimeType, fileName);
    
    if (!text || text.trim().length === 0) {
      // Clean up file
      fs.unlinkSync(filePath);
      const response: ApiResponse = {
        success: false,
        error: 'Could not extract text from file. Supported formats: .txt, .md, .pdf, .docx',
      };
      return res.status(400).json(response);
    }

    // Upload to Supabase Storage
    const fileBuffer = fs.readFileSync(filePath);
    const storageFileName = `${userId}/${uuidv4()}_${fileName}`;
    
    const { data: uploadData, error: uploadError } = await db.storage()
      .from('files')
      .upload(storageFileName, fileBuffer, {
        contentType: mimeType,
        upsert: false,
      });

    if (uploadError) {
      console.error('❌ Storage upload error:', uploadError);
      fs.unlinkSync(filePath);
      throw uploadError;
    }

    // Get public URL
    const { data: urlData } = db.storage()
      .from('files')
      .getPublicUrl(storageFileName);

    // Get file metadata
    const metadata = getFileMetadata(filePath, fileName, mimeType);

    // Create file record in database
    const { data: fileRecord, error: fileError } = await db.userFiles()
      .insert({
        user_id: userId,
        file_name: fileName,
        mime_type: mimeType,
        size: metadata.size,
        storage_path: storageFileName,
        uploaded_at: metadata.uploadedAt,
      })
      .select()
      .single();

    if (fileError) {
      console.error('❌ Database error:', fileError);
      // Clean up storage
      await db.storage().from('files').remove([storageFileName]);
      fs.unlinkSync(filePath);
      throw fileError;
    }

    // Chunk text for embedding
    const chunks = chunkText(text);
    console.log(`📄 Extracted ${chunks.length} chunks from file`);

    // Generate embeddings for chunks
    const embeddings = await getEmbeddings(chunks);
    console.log(`✅ Generated ${embeddings.length} embeddings`);

    // Store chunks with embeddings
    const chunkRecords = chunks.map((chunk, index) => ({
      file_id: fileRecord.id,
      chunk_index: index,
      content: chunk,
      embedding: embeddings[index],
    }));

    const { error: chunksError } = await db.userFileChunks()
      .insert(chunkRecords);

    if (chunksError) {
      console.error('❌ Error storing chunks:', chunksError);
      // Clean up file record
      await db.userFiles().delete().eq('id', fileRecord.id);
      await db.storage().from('files').remove([storageFileName]);
      fs.unlinkSync(filePath);
      throw chunksError;
    }

    // Clean up local file
    fs.unlinkSync(filePath);

    console.log(`✅ File processed successfully: ${fileName} (${chunks.length} chunks)`);

    const response: ApiResponse = {
      success: true,
      data: {
        file: {
          id: fileRecord.id,
          fileName,
          mimeType,
          size: metadata.size,
          url: urlData.publicUrl,
          chunks: chunks.length,
          uploadedAt: metadata.uploadedAt,
        },
      },
      message: 'File uploaded and processed successfully',
    };

    res.json(response);
  } catch (error: any) {
    console.error('❌ File upload error:', error);
    const response: ApiResponse = {
      success: false,
      error: error.message || 'Failed to upload and process file',
    };
    res.status(500).json(response);
  }
});

/**
 * GET /api/files
 * List all user's uploaded files
 */
router.get('/', skipAuthInDev(), async (req: AuthenticatedRequest, res: express.Response) => {
  try {
    const userId = req.user?.id || 'anonymous';

    const { data: files, error } = await db.userFiles()
      .select('id, file_name, mime_type, size, uploaded_at, storage_path')
      .eq('user_id', userId)
      .order('uploaded_at', { ascending: false });

    if (error) {
      throw error;
    }

    const response: ApiResponse = {
      success: true,
      data: {
        files: files || [],
        count: files?.length || 0,
      },
    };

    res.json(response);
  } catch (error: any) {
    console.error('❌ Error listing files:', error);
    const response: ApiResponse = {
      success: false,
      error: error.message || 'Failed to list files',
    };
    res.status(500).json(response);
  }
});

/**
 * DELETE /api/files/:id
 * Delete a file and its chunks
 */
router.delete('/:id', skipAuthInDev(), async (req: AuthenticatedRequest, res: express.Response) => {
  try {
    const userId = req.user?.id || 'anonymous';
    const fileId = req.params.id;

    // Get file record
    const { data: file, error: fileError } = await db.userFiles()
      .select('storage_path')
      .eq('id', fileId)
      .eq('user_id', userId)
      .single();

    if (fileError || !file) {
      const response: ApiResponse = {
        success: false,
        error: 'File not found',
      };
      return res.status(404).json(response);
    }

    // Delete chunks
    await db.userFileChunks().delete().eq('file_id', fileId);

    // Delete file record
    await db.userFiles().delete().eq('id', fileId);

    // Delete from storage
    if (file.storage_path) {
      await db.storage().from('files').remove([file.storage_path]);
    }

    const response: ApiResponse = {
      success: true,
      message: 'File deleted successfully',
    };

    res.json(response);
  } catch (error: any) {
    console.error('❌ Error deleting file:', error);
    const response: ApiResponse = {
      success: false,
      error: error.message || 'Failed to delete file',
    };
    res.status(500).json(response);
  }
});

export default router;


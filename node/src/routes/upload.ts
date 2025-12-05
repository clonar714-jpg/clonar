import express from 'express';
import path from 'path';
import sharp from 'sharp';
import { db } from '@/services/database';
import { authenticateToken as verifyToken } from '@/middleware/auth';
import skipAuthInDev from '@/middleware/skipAuthInDev';
import { upload, uploadSingle, uploadMultiple, processImage, handleUploadError } from '@/middleware/upload';
import { ApiResponse, AuthenticatedRequest } from '@/types';

const router = express.Router();

// Upload single image - improved debugging version
router.post("/single", skipAuthInDev(), (req, res, next) => {
  console.log("📤 Upload request received");

  const handler = upload.single("image");
  handler(req, res, async (err) => {
    if (err) {
      console.error("❌ Multer error:", err);
      return res.status(400).json({ success: false, error: err.message });
    }

    if (!req.file) {
      console.error("❌ No file found in request");
      return res.status(400).json({ success: false, error: "No file uploaded" });
    }

    try {
      console.log("📦 Received file field:", req.file.fieldname);
      console.log("📦 File:", req.file.originalname, req.file.mimetype);

      const uploadDir = process.env.UPLOAD_PATH || './uploads';
      const processedPath = path.join(uploadDir, `${req.file.filename}_processed.jpg`);
      await sharp(req.file.path).resize(1080).toFile(processedPath);

      const fileUrl = `http://10.0.2.2:4000/uploads/${req.file.filename}_processed.jpg`;
      console.log("✅ Upload success:", fileUrl);

      return res.json({ success: true, url: fileUrl });
    } catch (err) {
      console.error("🔥 Upload processing error:", err);
      return res.status(500).json({ success: false, error: "Failed to process image" });
    }
  });
});

// Upload multiple images
router.post('/multiple', skipAuthInDev(), uploadMultiple, processImage, handleUploadError, async (req: AuthenticatedRequest, res: express.Response) => {
  try {
    if (!req.files || (req.files as Express.Multer.File[]).length === 0) {
      const response: ApiResponse = {
        success: false,
        error: 'No files uploaded',
      };
      return res.status(400).json(response);
    }

    const files = req.files as Express.Multer.File[];
    const uploadedFiles = files.map(file => ({
      filename: file.filename,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: file.size,
      url: `/uploads/${file.filename}`,
    }));

    const response: ApiResponse = {
      success: true,
      data: {
        files: uploadedFiles,
        count: files.length,
      },
      message: `${files.length} files uploaded successfully`,
    };

    res.json(response);
  } catch (error) {
    console.error('Upload multiple files error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to upload files',
    };
    res.status(500).json(response);
  }
});

// Upload to Supabase Storage (for production)
router.post('/supabase', skipAuthInDev(), uploadSingle, processImage, handleUploadError, async (req: AuthenticatedRequest, res: express.Response) => {
  try {
    if (!req.file) {
      const response: ApiResponse = {
        success: false,
        error: 'No file uploaded',
      };
      return res.status(400).json(response);
    }

    // Upload to Supabase Storage
    const fileBuffer = require('fs').readFileSync(req.file.path);
    const fileName = `${req.user!.id}/${req.file.filename}`;
    
    const { data, error } = await db.storage()
      .from('images')
      .upload(fileName, fileBuffer, {
        contentType: req.file.mimetype,
        upsert: false,
      });

    if (error) {
      throw error;
    }

    // Get public URL
    const { data: urlData } = db.storage()
      .from('images')
      .getPublicUrl(fileName);

    // Clean up local file
    require('fs').unlinkSync(req.file.path);

    const response: ApiResponse = {
      success: true,
      data: {
        filename: req.file.filename,
        originalname: req.file.originalname,
        mimetype: req.file.mimetype,
        size: req.file.size,
        url: urlData.publicUrl,
        path: data.path,
      },
      message: 'File uploaded to cloud storage successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Upload to Supabase error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to upload file to cloud storage',
    };
    res.status(500).json(response);
  }
});

// Delete uploaded file
router.delete('/:filename', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    const { filename } = req.params;
    const filePath = path.join(process.env.UPLOAD_PATH || './uploads', filename);

    // Check if file exists
    if (!require('fs').existsSync(filePath)) {
      const response: ApiResponse = {
        success: false,
        error: 'File not found',
      };
      return res.status(404).json(response);
    }

    // Delete file
    require('fs').unlinkSync(filePath);

    const response: ApiResponse = {
      success: true,
      message: 'File deleted successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Delete file error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to delete file',
    };
    res.status(500).json(response);
  }
});

// Get file info
router.get('/:filename', skipAuthInDev(), async (req, res) => {
  try {
    const { filename } = req.params;
    const filePath = path.join(process.env.UPLOAD_PATH || './uploads', filename);

    // Check if file exists
    if (!require('fs').existsSync(filePath)) {
      const response: ApiResponse = {
        success: false,
        error: 'File not found',
      };
      return res.status(404).json(response);
    }

    const stats = require('fs').statSync(filePath);
    const fileUrl = `/uploads/${filename}`;

    const response: ApiResponse = {
      success: true,
      data: {
        filename,
        url: fileUrl,
        size: stats.size,
        created: stats.birthtime,
        modified: stats.mtime,
      },
    };

    res.json(response);
  } catch (error) {
    console.error('Get file info error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to get file info',
    };
    res.status(500).json(response);
  }
});

export default router;

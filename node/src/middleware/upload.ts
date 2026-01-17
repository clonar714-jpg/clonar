import multer from 'multer';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import sharp from 'sharp';
import fs from 'fs';
import { Request } from 'express';


const uploadDir = process.env.UPLOAD_PATH || './uploads';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}


const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueName = `${uuidv4()}-${Date.now()}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  },
});


const fileFilter = (req: Request, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
  const allowedTypes = (process.env.ALLOWED_IMAGE_TYPES || 'image/jpeg,image/png,image/webp,image/gif,image/jpg').split(',');
  
  console.log('🔍 File upload debug:');
  console.log('  - Original name:', file.originalname);
  console.log('  - MIME type:', file.mimetype);
  console.log('  - Field name:', file.fieldname);
  console.log('  - Allowed types:', allowedTypes);
  
  
  const isAllowed = allowedTypes.includes(file.mimetype) || 
                   file.mimetype.startsWith('image/') ||
                   /\.(jpg|jpeg|png|webp|gif)$/i.test(file.originalname);
  
  if (isAllowed) {
    console.log('✅ File type accepted');
    cb(null, true);
  } else {
    console.log('❌ File type rejected');
    cb(new Error(`Invalid file type. Allowed types: ${allowedTypes.join(', ')}`));
  }
};


export const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE || '10485760'), // 10MB default
  },
});


export const processImage = async (req: Request, res: any, next: any) => {
  try {
    if (!req.file) {
      return next();
    }

    const filePath = req.file.path;
    const processedPath = filePath.replace(path.extname(filePath), '_processed.jpg');

    
    await sharp(filePath)
      .resize(1920, 1920, { 
        fit: 'inside',
        withoutEnlargement: true 
      })
      .jpeg({ quality: 85 })
      .toFile(processedPath);

    
    fs.unlinkSync(filePath);

    
    req.file.path = processedPath;
    req.file.filename = path.basename(processedPath);
    req.file.mimetype = 'image/jpeg';

    next();
  } catch (error) {
    console.error('Image processing error:', error);
    next(error);
  }
};


export const uploadMultiple = upload.array('images', 10); // Max 10 files


export const uploadSingle = upload.single('image');


export const handleUploadError = (error: any, req: Request, res: any, next: any) => {
  console.log('❌ Upload Error:', error);
  console.log('❌ Upload Error Type:', typeof error);
  console.log('❌ Upload Error Message:', error?.message);
  console.log('❌ Upload Error Code:', error?.code);
  
  if (error instanceof multer.MulterError) {
    console.log('❌ Multer Error Code:', error.code);
    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({
        success: false,
        error: 'File too large. Maximum size is 10MB.',
      });
    }
    if (error.code === 'LIMIT_FILE_COUNT') {
      return res.status(400).json({
        success: false,
        error: 'Too many files. Maximum is 10 files.',
      });
    }
    if (error.code === 'LIMIT_UNEXPECTED_FILE') {
      return res.status(400).json({
        success: false,
        error: 'Unexpected field name. Expected field name: "image"',
      });
    }
  }
  
  if (error.message.includes('Invalid file type')) {
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }

  next(error);
};

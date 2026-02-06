import multer from 'multer';
import path from 'path';
import type { Request, Response, NextFunction } from 'express';

const uploadDir = process.env.UPLOAD_PATH || './uploads';

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) =>
    cb(null, `${Date.now()}-${path.basename(file.originalname)}`),
});

export const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const allowed = /\.(jpg|jpeg|png|gif|webp)$/i.test(file.originalname);
    cb(null, !!allowed);
  },
});

export const uploadSingle = upload.single('image');
export const uploadMultiple = upload.array('images', 10);

export function processImage(req: Request, _res: Response, next: NextFunction): void {
  // no-op; route handlers do their own processing if needed
  next();
}

export function handleUploadError(
  err: Error,
  _req: Request,
  res: Response,
  next: NextFunction
): void {
  if (err) {
    res.status(400).json({ success: false, error: err.message });
    return;
  }
  next();
}

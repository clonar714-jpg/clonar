import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'default-secret';

export interface AuthPayload {
  id: string;
  email?: string;
  name?: string;
}

export function authenticateToken(
  req: Request & { user?: AuthPayload },
  res: Response,
  next: NextFunction
): void {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    res.status(401).json({ success: false, error: 'Access token required' });
    return;
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as AuthPayload;
    req.user = { id: decoded.id, email: decoded.email, name: decoded.name };
    next();
  } catch {
    res.status(403).json({ success: false, error: 'Invalid or expired token' });
  }
}

export function optionalAuth(
  req: Request & { user?: AuthPayload },
  _res: Response,
  next: NextFunction
): void {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    next();
    return;
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as AuthPayload;
    req.user = { id: decoded.id, email: decoded.email, name: decoded.name };
  } catch {
    // leave req.user undefined
  }
  next();
}

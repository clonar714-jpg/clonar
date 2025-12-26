import { Request, Response } from 'express';
import { ApiResponse } from '@/types';

export const notFoundHandler = (req: Request, res: Response): void => {
  const response: ApiResponse = {
    success: false,
    error: `Route ${req.originalUrl} not found`,
  };
  
  res.status(404).json(response);
};

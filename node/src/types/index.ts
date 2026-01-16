/**
 * ✅ Shared Types
 * Common types used across the application
 */

import { Request } from 'express';

/**
 * Authenticated request with user information
 * Extends Express Request with optional user property
 */
export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email?: string;
    name?: string;
    [key: string]: any;
  };
}

/**
 * Standard API response format
 */
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  [key: string]: any;
}

/**
 * Auth response format
 */
export interface AuthResponse {
  token: string;
  refreshToken?: string;
  user: {
    id: string;
    email: string;
    name?: string;
    [key: string]: any;
  };
}

/**
 * Login request format
 */
export interface LoginRequest {
  email: string;
  password: string;
}

/**
 * Register request format
 */
export interface RegisterRequest {
  email: string;
  password: string;
  username?: string;
  full_name?: string;
}

/**
 * User type
 */
export interface User {
  id: string;
  email: string;
  username?: string;
  full_name?: string;
  bio?: string;
  is_verified?: boolean;
  created_at?: string;
  updated_at?: string;
  [key: string]: any;
}

/**
 * Collage-related types
 */
export interface CreateCollageRequest {
  title: string;
  description?: string;
  is_public?: boolean;
}

export interface UpdateCollageRequest {
  title?: string;
  description?: string;
  is_public?: boolean;
}

export interface AddCollageItemRequest {
  item_type: string;
  item_data: any;
  position?: number;
}

export interface CollageFilters {
  user_id?: string;
  is_public?: boolean;
  search?: string;
}


import type { Request } from 'express';

export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface AuthUser {
  id: string;
  email?: string;
  name?: string;
}

export interface AuthenticatedRequest extends Request {
  user?: AuthUser;
}

export interface User {
  id: string;
  email?: string;
  full_name?: string;
  username?: string;
  bio?: string;
  password?: string;
  is_verified?: boolean;
  created_at?: string;
  updated_at?: string;
}

export interface AuthResponse {
  token: string;
  user?: User;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  email: string;
  password: string;
  username?: string;
  full_name?: string;
}

export interface CreateCollageRequest {
  title?: string;
  description?: string;
  cover_image_url?: string;
  layout?: string;
  settings?: Record<string, unknown>;
  tags?: string[];
  is_published?: boolean;
  items?: Array<{ type: string; content?: string; image_url?: string; order?: number }>;
}

export interface UpdateCollageRequest extends Partial<CreateCollageRequest> {}

export interface AddCollageItemRequest {
  type: string;
  content?: string;
  image_url?: string;
  order?: number;
}

export interface CollageFilters {
  page?: string;
  limit?: string;
  user_id?: string;
  is_published?: string;
  tags?: string;
}

export interface CreatePersonaRequest {
  title?: string;
  description?: string;
  cover_image_url?: string;
  [key: string]: unknown;
}



import { Request } from 'express';


export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email?: string;
    name?: string;
    [key: string]: any;
  };
}


export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  [key: string]: any;
}


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


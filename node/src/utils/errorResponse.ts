/**
 * ✅ IMPROVEMENT: Standardized error response format
 * 
 * Benefits:
 * - Consistent error format across all endpoints
 * - Easier for frontend to handle errors
 * - Better error messages for debugging
 */

export interface ErrorResponse {
  success: false;
  message: string;
  errors?: Array<{ path: string; message: string }>;
  code?: string;
}

export interface SuccessResponse<T> {
  success: true;
  data: T;
}

/**
 * Creates a standardized error response
 */
export function createErrorResponse(
  message: string,
  errors?: Array<{ path: string; message: string }>,
  code?: string
): ErrorResponse {
  return {
    success: false,
    message,
    ...(errors && errors.length > 0 && { errors }),
    ...(code && { code }),
  };
}

/**
 * Creates a standardized success response
 */
export function createSuccessResponse<T>(data: T): SuccessResponse<T> {
  return {
    success: true,
    data,
  };
}




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


export function createSuccessResponse<T>(data: T): SuccessResponse<T> {
  return {
    success: true,
    data,
  };
}


/**
 * ✅ IMPROVEMENT: Standardized error response format
 *
 * Benefits:
 * - Consistent error format across all endpoints
 * - Easier for frontend to handle errors
 * - Better error messages for debugging
 */
/**
 * Creates a standardized error response
 */
export function createErrorResponse(message, errors, code) {
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
export function createSuccessResponse(data) {
    return {
        success: true,
        data,
    };
}

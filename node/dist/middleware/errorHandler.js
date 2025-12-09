export const errorHandler = (err, req, res, next) => {
    let error = { ...err };
    error.message = err.message;
    // Log error
    console.error('Error:', err);
    // Mongoose bad ObjectId
    if (err.name === 'CastError') {
        const message = 'Resource not found';
        error = createError(message, 404);
    }
    // Mongoose duplicate key
    if (err.name === 'MongoError' && err.code === 11000) {
        const message = 'Duplicate field value entered';
        error = createError(message, 400);
    }
    // Mongoose validation error
    if (err.name === 'ValidationError') {
        const message = Object.values(err.errors).map((val) => val.message).join(', ');
        error = createError(message, 400);
    }
    // JWT errors
    if (err.name === 'JsonWebTokenError') {
        const message = 'Invalid token';
        error = createError(message, 401);
    }
    if (err.name === 'TokenExpiredError') {
        const message = 'Token expired';
        error = createError(message, 401);
    }
    const response = {
        success: false,
        error: error.message || 'Server Error',
    };
    res.status(error.statusCode || 500).json(response);
};
const createError = (message, statusCode) => {
    const error = new Error(message);
    error.statusCode = statusCode;
    error.isOperational = true;
    return error;
};

export const notFoundHandler = (req, res) => {
    const response = {
        success: false,
        error: `Route ${req.originalUrl} not found`,
    };
    res.status(404).json(response);
};

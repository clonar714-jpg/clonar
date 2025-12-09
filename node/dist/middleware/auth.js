import jwt from 'jsonwebtoken';
export const authenticateToken = (req, res, next) => {
    console.log(`🌍 Environment: ${process.env.NODE_ENV}`); // ✅ dev auth bypass
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    console.log('🔍 Incoming token:', token ? token.substring(0, 40) + '...' : 'NONE');
    if (!token) {
        console.log('❌ No token provided');
        res.status(403).json({ success: false, error: 'Token missing' });
        return;
    }
    try {
        const jwtSecret = process.env.JWT_SECRET;
        if (!jwtSecret)
            throw new Error('JWT_SECRET missing');
        const decoded = jwt.verify(token, jwtSecret);
        req.user = decoded;
        console.log('✅ Token valid for user:', decoded);
        next();
    }
    catch (err) {
        console.log('❌ Token verification failed:', err.message);
        res.status(403).json({ success: false, error: 'Invalid or expired token' });
        return;
    }
};
export const optionalAuth = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) {
        next();
        return;
    }
    try {
        const jwtSecret = process.env.JWT_SECRET;
        if (!jwtSecret) {
            next();
            return;
        }
        const decoded = jwt.verify(token, jwtSecret);
        req.user = decoded;
        next();
    }
    catch (err) {
        console.log('❌ Optional auth token verification failed:', err.message);
        next();
    }
};

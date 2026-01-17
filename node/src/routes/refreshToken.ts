import express from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '@/services/database';

const router = express.Router();
const REFRESH_TOKEN_SECRET = process.env.REFRESH_TOKEN_SECRET || 'refresh-secret-fallback';
const ACCESS_TOKEN_SECRET = process.env.JWT_SECRET || 'default-secret';


const refreshTokens: string[] = [];


router.post('/refresh', async (req, res) => {
  try {
    console.log('🔄 Refresh token request received');
    const { refreshToken } = req.body;

    if (!refreshToken) {
      console.log('❌ No refresh token provided');
      return res.status(400).json({ success: false, error: 'Refresh token required' });
    }

    if (!refreshTokens.includes(refreshToken)) {
      console.log('❌ Invalid refresh token');
      return res.status(403).json({ success: false, error: 'Invalid refresh token' });
    }

    jwt.verify(refreshToken, REFRESH_TOKEN_SECRET, (err: any, user: any) => {
      if (err) {
        console.log('❌ Refresh token verification failed:', err.message);
        return res.status(403).json({ success: false, error: 'Invalid or expired refresh token' });
      }

      console.log('✅ Refresh token valid for user:', user.id);

      const newAccessToken = jwt.sign(
        { id: user.id, email: user.email },
        ACCESS_TOKEN_SECRET,
        { expiresIn: '1h' }
      );

      const newRefreshToken = jwt.sign(
        { id: user.id, email: user.email },
        REFRESH_TOKEN_SECRET,
        { expiresIn: '7d' }
      );

      
      const index = refreshTokens.indexOf(refreshToken);
      if (index !== -1) refreshTokens.splice(index, 1);
      refreshTokens.push(newRefreshToken);

      console.log('✅ New tokens issued for user:', user.id);

      res.json({
        success: true,
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
        message: 'Tokens refreshed successfully',
      });
    });
  } catch (error: any) {
    console.error('🔥 Refresh token error:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});


router.post('/revoke', async (req, res) => {
  try {
    const { refreshToken } = req.body;
    
    if (!refreshToken) {
      return res.status(400).json({ success: false, error: 'Refresh token required' });
    }

    const index = refreshTokens.indexOf(refreshToken);
    if (index !== -1) {
      refreshTokens.splice(index, 1);
      console.log('✅ Refresh token revoked');
    }

    res.json({ success: true, message: 'Token revoked successfully' });
  } catch (error: any) {
    console.error('🔥 Revoke token error:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});


router.get('/stats', (req, res) => {
  res.json({
    success: true,
    activeRefreshTokens: refreshTokens.length,
    message: 'Refresh token statistics'
  });
});

export default router;

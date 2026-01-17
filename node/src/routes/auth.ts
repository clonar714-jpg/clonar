import express from 'express';
import jwt from 'jsonwebtoken';
import { supabase, db } from '@/services/database';
import { ApiResponse, AuthResponse, LoginRequest, RegisterRequest, User } from '@/types';
import { loginSchema, registerSchema } from '@/middleware/validation';
import { authenticateToken as verifyToken } from '@/middleware/auth';
import skipAuthInDev from '@/middleware/skipAuthInDev';

const router = express.Router();


const refreshTokens: string[] = [];


router.post('/register', async (req, res) => {
  try {
    console.log('🔐 Register: Starting registration process...');
    console.log('📦 Request body:', JSON.stringify(req.body, null, 2));

    
    const { error, value } = registerSchema.validate(req.body);
    if (error) {
      console.log('❌ Register: Validation error:', error.details[0].message);
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    const { email, username, password, full_name }: RegisterRequest = value;
    console.log('✅ Register: Validation passed');
    console.log('📧 Register: Email:', email);
    console.log('👤 Register: Username:', username);
    console.log('🔑 Register: Password provided:', !!password);

    
    console.log('🔍 Register: Checking if username exists...');
    const { data: existingUser, error: userError } = await db.users()
      .select('username')
      .eq('username', username)
      .single();

    if (existingUser) {
      console.log('❌ Register: Username already taken');
      const response: ApiResponse = {
        success: false,
        error: 'Username already taken',
      };
      return res.status(400).json(response);
    }

    
    console.log('🔐 Register: Calling Supabase auth.signUp...');
    const { data: authData, error: authError } = await supabase().auth.signUp({
      email,
      password,
    });

    console.log('🔐 Register: Supabase auth result:', {
      hasData: !!authData,
      hasError: !!authError,
      errorMessage: authError?.message,
      userId: authData?.user?.id,
      userEmail: authData?.user?.email
    });

    if (authError) {
      console.error('❌ Register: Supabase auth signup error:', authError);
      console.error('❌ Register: Auth error details:', {
        code: authError.code,
        message: authError.message,
      });

      let errorMessage = 'Registration failed';
      if (authError.message.includes('User already registered')) {
        errorMessage = 'User with this email already exists';
      } else if (authError.message.includes('Invalid email')) {
        errorMessage = 'Invalid email format';
      } else if (authError.message.includes('Password should be at least')) {
        errorMessage = 'Password is too short';
      }

      const response: ApiResponse = {
        success: false,
        error: errorMessage,
      };
      return res.status(400).json(response);
    }

    if (!authData.user) {
      console.error('❌ Register: No user data returned from Supabase');
      const response: ApiResponse = {
        success: false,
        error: 'Registration failed',
      };
      return res.status(500).json(response);
    }

    console.log('✅ Register: Supabase auth successful');
    console.log('🔍 Register: Supabase user data:', {
      id: authData.user.id,
      email: authData.user.email,
      email_confirmed_at: authData.user.email_confirmed_at
    });

    
    console.log('💾 Register: Inserting user profile...');
    const { data: newUser, error: insertError } = await db.users()
      .insert({
        id: authData.user.id,
        email: authData.user.email!,
        username,
        full_name: full_name || null,
        avatar_url: null,
        bio: 'Welcome to Clonar!',
        password: 'supabase_auth_user', 
        is_verified: !!authData.user.email_confirmed_at,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (insertError) {
      console.error('❌ Register: Database insert error:', insertError);
      
      let errorMessage = 'Registration failed';
      if (insertError.code === '23505') {
        if (insertError.message.includes('username')) {
          errorMessage = 'Username already taken';
        } else if (insertError.message.includes('email')) {
          errorMessage = 'User with this email already exists';
        }
      } else if (insertError.code === '23502') {
        errorMessage = 'Required field is missing';
      }

      const response: ApiResponse = {
        success: false,
        error: errorMessage,
      };
      return res.status(400).json(response);
    }

    console.log('✅ Register: User profile created successfully');
    console.log('👤 Register: New user data:', newUser);

    
    console.log('🔑 Register: Generating JWT tokens...');
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      console.error('❌ Register: JWT_SECRET is not configured');
      throw new Error('JWT_SECRET is not configured');
    }

    const token = jwt.sign(
      { id: newUser.id, email: authData.user.email!, username },
      jwtSecret,
      { expiresIn: '7d' } as jwt.SignOptions
    );

    
    const refreshToken = jwt.sign(
      { id: newUser.id },
      jwtSecret,
      { expiresIn: '30d' }
    );

    console.log('✅ Register: JWT tokens generated successfully');

    const response: ApiResponse<AuthResponse> = {
      success: true,
      data: {
        user: {
          id: newUser.id,
          email: newUser.email,
          username: newUser.username,
          full_name: newUser.full_name,
          avatar_url: newUser.avatar_url,
          bio: newUser.bio,
          is_verified: newUser.is_verified,
          created_at: newUser.created_at,
          updated_at: newUser.updated_at,
        },
        token: authData.session?.access_token || token,
        refresh_token: authData.session?.refresh_token || refreshToken,
      },
      message: 'Registration successful',
    };

    console.log('🎉 Register: Registration completed successfully');
    return res.status(201).json(response);
  } catch (error: any) {
    console.error('💥 Register: Unexpected error during registration:', error);
    const response: ApiResponse = {
      success: false,
      error: error.message || 'Registration failed',
    };
    return res.status(500).json(response);
  }
});


router.post('/login', async (req, res) => {
  try {
    console.log('🔐 Login: Starting login process...');
    console.log('📦 Request body:', JSON.stringify(req.body, null, 2));

    
    const { error, value } = loginSchema.validate(req.body);
    if (error) {
      console.log('❌ Login: Validation error:', error.details[0].message);
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    const { email, password }: LoginRequest = value;
    console.log('✅ Login: Validation passed');
    console.log('📧 Login: Email:', email);
    console.log('🔑 Login: Password provided:', !!password);
    console.log('👤 Login attempt for email:', email);

    
    console.log('🔍 Login: Looking up user in Supabase database...');
    
    const { data: userProfile, error: profileError } = await db.users()
      .select('*')
      .eq('email', email)
      .single();

    if (profileError || !userProfile) {
      console.log('❌ Login: User not found in database');
      const response: ApiResponse = {
        success: false,
        error: 'Invalid email or password',
      };
      return res.status(401).json(response);
    }

    console.log('✅ Login: User found in database:', userProfile);
    
    
    if (userProfile.password === 'supabase_auth_user') {
      console.log('✅ Login: Supabase auth user - accepting any password for development');
      
    } else {
      
      console.log('✅ Login: Regular user - password validation would go here');
    }
    
   
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      throw new Error('JWT_SECRET is not configured');
    }
    
    const token = jwt.sign(
      { 
        id: userProfile.id, 
        email: userProfile.email, 
        username: userProfile.username
      },
      jwtSecret,
      { expiresIn: '7d' }
    );

    const REFRESH_TOKEN_SECRET = process.env.REFRESH_TOKEN_SECRET || 'refresh-secret-fallback';
    const refreshToken = jwt.sign(
      { id: userProfile.id, email: userProfile.email },
      REFRESH_TOKEN_SECRET,
      { expiresIn: '7d' }
    );

   
    refreshTokens.push(refreshToken);
    console.log('✅ Login: Refresh token stored, total active tokens:', refreshTokens.length);

    const response: ApiResponse<AuthResponse> = {
      success: true,
      data: {
        user: {
          id: userProfile.id,
          email: userProfile.email,
          username: userProfile.username,
          full_name: userProfile.full_name,
          avatar_url: userProfile.avatar_url,
          bio: userProfile.bio,
          is_verified: userProfile.is_verified,
          created_at: userProfile.created_at,
          updated_at: userProfile.updated_at,
        },
        token: token,
        refresh_token: refreshToken,
      },
      message: 'Login successful',
    };

    console.log('🎉 Login: Test login completed successfully');
    return res.json(response);
  } catch (error: any) {
    console.error('💥 Login: Unexpected error during login:', error);
    const response: ApiResponse = {
      success: false,
      error: error.message || 'Login failed',
    };
    return res.status(500).json(response);
  }
});


router.get('/me', skipAuthInDev(), async (req, res) => {
  try {
    
    if (process.env.NODE_ENV === 'development' && req.user) {
      return res.json({
        success: true,
        data: {
          id: req.user.id,
          email: req.user.email,
          name: req.user.full_name || 'Dev User',
        },
      });
    }

    
    const authHeader = req.headers.authorization || '';
    const token = authHeader.split(' ')[1];
    if (!token) {
      return res.status(401).json({ success: false, error: 'Missing token' });
    }

    
    return res.json({
      success: true,
      data: { id: 'real-user-id', email: 'real@user.com' },
    });

  } catch (error) {
    console.error('Auth /me error:', error);
    res.status(500).json({ success: false, error: 'Failed to verify user' });
  }
});


router.post('/refresh', async (req, res) => {
  try {
    const { refresh_token } = req.body;
    
    if (!refresh_token) {
      const response: ApiResponse = {
        success: false,
        error: 'Refresh token required',
      };
      return res.status(400).json(response);
    }

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      throw new Error('JWT_SECRET is not configured');
    }

    const decoded = jwt.verify(refresh_token, jwtSecret) as any;
    const userId = decoded.id;

    
    const newToken = jwt.sign(
      { id: userId },
      jwtSecret,
      { expiresIn: '7d' }
    );

    const response: ApiResponse = {
      success: true,
      data: {
        token: newToken,
      },
    };

    res.json(response);
  } catch (error: any) {
    console.error('Refresh token error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Invalid refresh token',
    };
    res.status(401).json(response);
  }
});

export default router;
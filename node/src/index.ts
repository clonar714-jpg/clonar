/// <reference path="./types/express/index.d.ts" />

// Load environment variables FIRST
import dotenv from 'dotenv';
import path from 'path';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import compression from 'compression';
import rateLimit from 'express-rate-limit';

import { errorHandler } from '@/middleware/errorHandler';
import { notFoundHandler } from '@/middleware/notFoundHandler';
import authRoutes from '@/routes/auth';
import refreshTokenRoutes from '@/routes/refreshToken';
import personaRoutes from '@/routes/personas';
import collageRoutes from '@/routes/collages';
import userRoutes from '@/routes/users';
import uploadRoutes from '@/routes/upload';
import agentRoutes from '@/routes/agent';
import generateSuggestionsRoutes from '@/routes/generateSuggestions';
import productDetailsRoutes from '@/routes/productDetails';
import hotelDetailsRoutes from '@/routes/hotelDetails';
import autocompleteRoutes from '@/routes/autocomplete';
import moviesRoutes from '@/routes/movies';
import geocodeRoutes from '@/routes/geocode';
import hotelRoomsRoutes from '@/routes/hotelRooms';
import chatsRoutes from '@/routes/chats';
import { connectDatabase } from '@/services/database';
import { startBackgroundJob } from '@/services/personalization/backgroundAggregator';
// ✅ PHASE 10: Stability & Concurrency imports
import { setupUnhandledRejectionHandler, setupUncaughtExceptionHandler, setupGracefulShutdown, requestTimeout, setServerInstance } from './stability/errorHandlers';
import { startMemoryFlushScheduler } from './stability/memoryFlush';
console.log("DEBUG: SUPABASE_URL =", process.env.SUPABASE_URL);
console.log("DEBUG: SUPABASE_ANON_KEY =", process.env.SUPABASE_ANON_KEY ? "Loaded ✅" : "Missing ❌");
console.log("DEBUG: SUPABASE_SERVICE_ROLE_KEY =", process.env.SUPABASE_SERVICE_ROLE_KEY ? "Loaded ✅" : "Missing ❌");
console.log("DEBUG: TMDB_API_KEY =", process.env.TMDB_API_KEY ? "Loaded ✅" : "Missing ❌");


const app = express();
const PORT = parseInt(process.env.PORT || '4000', 10);

// Security middleware
app.use(helmet());

// CORS configuration
app.use(cors({
  origin: process.env.CORS_ORIGIN?.split(',') || ['http://localhost:3000'],
  credentials: true,
}));

// ✅ PHASE 10: Enhanced rate limiting - disabled in dev mode
if (process.env.NODE_ENV !== "development") {
  // ✅ Keep protection in production
  app.use(
    rateLimit({
      windowMs: 60 * 1000, // 1 minute window
      max: 100, // limit to 100 requests per minute per IP
      standardHeaders: true,
      legacyHeaders: false,
    })
  );
  console.log("🚦 Production mode: rate limiting enabled");
} else {
  // ✅ Disable all rate limiting in dev
  console.log("🧪 Dev mode: rate limiting disabled");
}

// ✅ PHASE 10: Request timeout middleware (15s default)
app.use(requestTimeout(15000));

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Serve static files from uploads directory
app.use("/uploads", express.static(path.join(process.cwd(), "uploads")));
console.log("🗂️ Serving static uploads at /uploads");

// Compression middleware
app.use(compression());

// Logging middleware
if (process.env.NODE_ENV === 'development') {
  app.use(morgan('dev'));
} else {
  app.use(morgan('combined'));
}

// Health check endpoint
app.get('/health', (req, res) => {
  console.log(`🏥 Health check requested from ${req.ip || req.headers['x-forwarded-for'] || 'unknown'}`);
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV,
  });
});

// ✅ PRODUCTION-GRADE: Test endpoint to verify connectivity from emulator
app.get('/api/test', (req, res) => {
  console.log(`🧪 Test endpoint hit from ${req.ip || req.headers['x-forwarded-for'] || 'unknown'}`);
  console.log(`   Headers: ${JSON.stringify(req.headers)}`);
  res.status(200).json({
    success: true,
    message: 'Backend is reachable!',
    timestamp: new Date().toISOString(),
    ip: req.ip || req.headers['x-forwarded-for'] || 'unknown',
  });
});

// ✅ PRODUCTION-GRADE: Test endpoint to verify connectivity
app.get('/api/test', (req, res) => {
  console.log(`🧪 Test endpoint hit from ${req.ip || req.headers['x-forwarded-for'] || 'unknown'}`);
  console.log(`   Headers: ${JSON.stringify(req.headers)}`);
  res.status(200).json({
    success: true,
    message: 'Backend is reachable!',
    timestamp: new Date().toISOString(),
    ip: req.ip || req.headers['x-forwarded-for'] || 'unknown',
  });
});

// Global multer error handler
app.use((error: any, req: any, res: any, next: any) => {
  if (error && error.code === 'LIMIT_UNEXPECTED_FILE') {
    console.log('❌ Global Multer Error: Unexpected field name');
    return res.status(400).json({
      success: false,
      error: 'Unexpected field name. Expected field name: "image"',
    });
  }
  if (error && error.code === 'LIMIT_FILE_SIZE') {
    console.log('❌ Global Multer Error: File too large');
    return res.status(400).json({
      success: false,
      error: 'File too large. Maximum size is 10MB.',
    });
  }
  next(error);
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/auth', refreshTokenRoutes);
app.use('/api/personas', personaRoutes);
app.use('/api/collages', collageRoutes);
app.use('/api/users', userRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/agent', agentRoutes);
app.use('/api/agent/generate-suggestions', generateSuggestionsRoutes);
app.use('/api/product-details', productDetailsRoutes);
app.use('/api/hotel-details', hotelDetailsRoutes);
app.use('/api/autocomplete', autocompleteRoutes);
app.use('/api/movies', moviesRoutes);
app.use('/api/geocode', geocodeRoutes);
console.log('✅ Geocode route registered at /api/geocode');
app.use('/api/chats', chatsRoutes);
console.log('✅ Chats route registered at /api/chats');

// Error handling middleware
app.use(notFoundHandler);
app.use(errorHandler);

// ✅ PHASE 10: Setup global error handlers (before server start)
setupUnhandledRejectionHandler();
setupUncaughtExceptionHandler();
setupGracefulShutdown();

// Start server
const startServer = async () => {
  try {
    // Connect to database
    await connectDatabase();
    
    const server = app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 Server running on http://localhost:${PORT}`);
      console.log(`📊 Environment: ${process.env.NODE_ENV}`);
      console.log(`🔗 Health check: http://localhost:${PORT}/health`);
      console.log(`🌐 Listening on ALL interfaces (0.0.0.0:${PORT}) - accessible from emulator at 10.0.2.2:${PORT}`);
      console.log(`🧪 Test endpoint: http://localhost:${PORT}/api/test`);
      console.log(`🌐 Listening on ALL interfaces (0.0.0.0:${PORT}) - accessible from emulator at 10.0.2.2:${PORT}`);
      console.log(`🧪 Test endpoint: http://localhost:${PORT}/api/test`);
      
      if (process.env.NODE_ENV === 'development') {
        console.log('⚙️  Dev Mode Active: Authentication checks are skipped for all routes');
      }

      // ✅ PHASE 4: Start background aggregation job
      startBackgroundJob();
      
      // ✅ PHASE 10: Start memory flush scheduler
      startMemoryFlushScheduler();
      
      // ✅ PHASE 10: Set server instance for graceful shutdown
      setServerInstance(server);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
};

startServer();

export default app;

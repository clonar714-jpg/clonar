#!/usr/bin/env node

/**
 * Script to extract agent framework files for open sourcing
 * This script copies only the agent-related files to a new directory
 */

const fs = require('fs');
const path = require('path');

const SOURCE_DIR = path.join(__dirname, 'node', 'src');
const TARGET_DIR = path.join(__dirname, 'agent-framework', 'node', 'src');
const FLUTTER_SOURCE_DIR = path.join(__dirname, 'lib');
const FLUTTER_TARGET_DIR = path.join(__dirname, 'agent-framework', 'lib');

// Directories to copy (agent framework) - Only core framework directories
const AGENT_DIRS = [
  'agent',
  'memory',
  'stability',
  'embeddings',
  'utils',
];

// Files to copy from services (core agent services only)
const AGENT_SERVICES = [
  'perplexityAnswer.ts',      // Main service - LangChain-style flow
  'queryGenerator.ts',        // Query optimization
  'documentSummarizer.ts',    // Document summarization
  'answerParser.ts',          // Answer parsing
];

// Files to copy from routes (agent route only)
const AGENT_ROUTES = [
  'agent.ts',
];

// Middleware to copy
const AGENT_MIDDLEWARE = [
  'errorHandler.ts',
  'validation.ts',
  'notFoundHandler.ts',
];

// Files to copy from root of src
const ROOT_FILES = [];

// Directories to exclude
const EXCLUDE_DIRS = [
  'services/personalization',  // App-specific personalization
  'services/providers',         // App-specific providers (hotels, products, etc.)
  'routes',                     // We'll copy routes manually (only agent.ts)
  'middleware',                 // We'll copy middleware manually (only specific files)
];

// Files to exclude from agent directory
const AGENT_EXCLUDE_FILES = [
  'agent/detail.handler.ts',  // App-specific detail handler
];

// Files to exclude from memory directory
const MEMORY_EXCLUDE_FILES = [
  'memory/genderDetector.ts',  // App-specific
];

// Files to exclude from utils directory
const UTILS_EXCLUDE_FILES = [
  'utils/cardFetchDecision.ts',
  'utils/semanticIntent.ts',
  'utils/followUpIntent.ts',
  'utils/streamingOptimizer.ts',
  'utils/userIdHelper.ts',
];

// Files to exclude from services
const SERVICES_EXCLUDE_FILES = [
  'services/productSearch.ts',
  'services/hotelSearch.ts',
  'services/flightSearch.ts',
  'services/restaurantSearch.ts',
  'services/placesSearch.ts',
  'services/tmdbService.ts',
  'services/hotelAmenitiesExtractor.ts',
  'services/hotelDescriptionGenerator.ts',
  'services/hotelGrouping.ts',
  'services/hotelThemeExtractor.ts',
  'services/productDescriptionGenerator.ts',
  'services/placesCardEngine.ts',
  'services/placesSectionGenerator.ts',
  'services/brightDataPlaces.ts',
  'services/roomsProvider.ts',
  'services/database.ts',
  'services/batchSummarization.ts',
  'services/llmAnswer.ts',              // Legacy, replaced by perplexityAnswer
  'services/llmQueryRefiner.ts',         // App-specific
  'services/llmContextExtractor.ts',    // App-specific
  'services/llmContextCache.ts',         // App-specific
  'services/imageAnalysis.ts',           // Optional, exclude for now
  'services/queryRepair.ts',             // App-specific
  'services/llmWarmup.ts',               // App-specific
];

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function copyFile(src, dest, baseDir = SOURCE_DIR) {
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
  const relativePath = path.relative(baseDir, src);
  console.log(`✅ Copied: ${relativePath}`);
}

function copyDirectory(src, dest, excludeDirs = [], excludeFiles = [], baseDir = SOURCE_DIR) {
  if (!fs.existsSync(src)) {
    console.log(`⚠️  Directory not found: ${src}`);
    return;
  }

  ensureDir(dest);
  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    const relativePath = path.relative(baseDir, srcPath);

    // Check if excluded
    if (excludeDirs.some(exclude => relativePath.startsWith(exclude))) {
      console.log(`⏭️  Skipped (excluded dir): ${relativePath}`);
      continue;
    }

    if (excludeFiles.includes(relativePath)) {
      console.log(`⏭️  Skipped (excluded file): ${relativePath}`);
      continue;
    }

    if (entry.isDirectory()) {
      copyDirectory(srcPath, destPath, excludeDirs, excludeFiles, baseDir);
    } else if (entry.isFile()) {
      copyFile(srcPath, destPath, baseDir);
    }
  }
}

function main() {
  console.log('🚀 Starting agent framework extraction...\n');
  console.log(`Source: ${SOURCE_DIR}`);
  console.log(`Target: ${TARGET_DIR}\n`);

  if (!fs.existsSync(SOURCE_DIR)) {
    console.error(`❌ Source directory not found: ${SOURCE_DIR}`);
    process.exit(1);
  }

  // Copy agent directories (with specific exclusions)
  console.log('📁 Copying agent directories...');
  for (const dir of AGENT_DIRS) {
    const src = path.join(SOURCE_DIR, dir);
    const dest = path.join(TARGET_DIR, dir);
    
    // Build exclusion list for this directory
    let excludeFiles = [...SERVICES_EXCLUDE_FILES];
    if (dir === 'agent') {
      excludeFiles = excludeFiles.concat(AGENT_EXCLUDE_FILES);
    } else if (dir === 'memory') {
      excludeFiles = excludeFiles.concat(MEMORY_EXCLUDE_FILES);
    } else if (dir === 'utils') {
      excludeFiles = excludeFiles.concat(UTILS_EXCLUDE_FILES);
    }
    
    copyDirectory(src, dest, EXCLUDE_DIRS, excludeFiles);
  }

  // Copy agent services (only core framework services)
  console.log('\n📄 Copying agent services...');
  ensureDir(path.join(TARGET_DIR, 'services'));
  for (const file of AGENT_SERVICES) {
    const src = path.join(SOURCE_DIR, 'services', file);
    const dest = path.join(TARGET_DIR, 'services', file);
    if (fs.existsSync(src)) {
      copyFile(src, dest);
    } else {
      console.log(`⚠️  File not found: ${src}`);
    }
  }
  
  // Log excluded services for reference
  console.log('\n⏭️  Excluded app-specific services:');
  SERVICES_EXCLUDE_FILES.forEach(file => {
    console.log(`   - ${file}`);
  });

  // Copy agent routes
  console.log('\n📄 Copying agent routes...');
  ensureDir(path.join(TARGET_DIR, 'routes'));
  for (const file of AGENT_ROUTES) {
    const src = path.join(SOURCE_DIR, 'routes', file);
    const dest = path.join(TARGET_DIR, 'routes', file);
    if (fs.existsSync(src)) {
      copyFile(src, dest);
    } else {
      console.log(`⚠️  File not found: ${src}`);
    }
  }

  // Copy middleware
  console.log('\n📄 Copying middleware...');
  ensureDir(path.join(TARGET_DIR, 'middleware'));
  for (const file of AGENT_MIDDLEWARE) {
    const src = path.join(SOURCE_DIR, 'middleware', file);
    const dest = path.join(TARGET_DIR, 'middleware', file);
    if (fs.existsSync(src)) {
      copyFile(src, dest);
    } else {
      console.log(`⚠️  File not found: ${src}`);
    }
  }

  // Copy root files
  console.log('\n📄 Copying root files...');
  for (const file of ROOT_FILES) {
    const src = path.join(SOURCE_DIR, file);
    const dest = path.join(TARGET_DIR, file);
    if (fs.existsSync(src)) {
      copyFile(src, dest);
    }
  }

  // Copy TypeScript config
  console.log('\n📄 Copying TypeScript config...');
  const tsconfigSrc = path.join(__dirname, 'node', 'tsconfig.json');
  const tsconfigDest = path.join(__dirname, 'agent-framework', 'node', 'tsconfig.json');
  if (fs.existsSync(tsconfigSrc)) {
    ensureDir(path.dirname(tsconfigDest));
    copyFile(tsconfigSrc, tsconfigDest, __dirname);
  }

  // Create filtered package.json
  console.log('\n📦 Creating filtered package.json...');
  const packageJsonSrc = path.join(__dirname, 'node', 'package.json');
  const packageJsonDest = path.join(__dirname, 'agent-framework', 'node', 'package.json');
  
  if (fs.existsSync(packageJsonSrc)) {
    const pkg = JSON.parse(fs.readFileSync(packageJsonSrc, 'utf8'));
    
    // Filter dependencies - keep only agent framework dependencies
    // You may need to manually review this
    const filteredPkg = {
      name: 'agent-framework',
      version: pkg.version || '1.0.0',
      description: 'Agentic framework for query processing and response generation',
      type: 'module',
      main: 'dist/index.js',
      scripts: {
        build: 'tsc',
        dev: 'tsx watch src/index.ts',
        start: 'tsx src/index.ts',
      },
      dependencies: {
        // Core dependencies - review and adjust
        'express': pkg.dependencies?.express,
        'cors': pkg.dependencies?.cors,
        'helmet': pkg.dependencies?.helmet,
        'compression': pkg.dependencies?.compression,
        'dotenv': pkg.dependencies?.dotenv,
        'openai': pkg.dependencies?.openai,
        'axios': pkg.dependencies?.axios,
        'ioredis': pkg.dependencies?.ioredis,
        'lru-cache': pkg.dependencies?.['lru-cache'],
        'express-rate-limit': pkg.dependencies?.['express-rate-limit'],
        'sharp': pkg.dependencies?.sharp,
        'node-fetch': pkg.dependencies?.['node-fetch'],
      },
      devDependencies: {
        '@types/express': pkg.devDependencies?.['@types/express'],
        '@types/node': pkg.devDependencies?.['@types/node'],
        '@types/cors': pkg.devDependencies?.['@types/cors'],
        'typescript': pkg.devDependencies?.typescript,
        'tsx': pkg.devDependencies?.tsx,
        'cross-env': pkg.devDependencies?.['cross-env'],
      },
      keywords: ['agent', 'llm', 'query-processing', 'ai'],
      license: 'MIT', // Change as needed
    };

    // Remove undefined values
    Object.keys(filteredPkg.dependencies).forEach(key => {
      if (filteredPkg.dependencies[key] === undefined) {
        delete filteredPkg.dependencies[key];
      }
    });
    Object.keys(filteredPkg.devDependencies).forEach(key => {
      if (filteredPkg.devDependencies[key] === undefined) {
        delete filteredPkg.devDependencies[key];
      }
    });

    fs.writeFileSync(packageJsonDest, JSON.stringify(filteredPkg, null, 2));
    console.log(`✅ Created: package.json`);
  }

  // Create .env.example
  console.log('\n📄 Creating .env.example...');
  const envExample = `# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here

# Server Configuration
PORT=4000
NODE_ENV=development

# CORS Configuration
CORS_ORIGIN=http://localhost:3000

# Redis Configuration (optional, for session storage)
REDIS_URL=redis://localhost:6379

# Session Storage Type: 'redis' or 'memory'
SESSION_STORAGE_TYPE=memory
`;
  fs.writeFileSync(
    path.join(__dirname, 'agent-framework', '.env.example'),
    envExample
  );
  console.log(`✅ Created: .env.example`);

  // Copy README from agent-framework directory (already created)
  console.log('\n📄 Checking for existing README...');
  const readmeSrc = path.join(__dirname, 'agent-framework', 'README.md');
  if (fs.existsSync(readmeSrc)) {
    console.log(`✅ Using existing README.md`);
  } else {
    console.log(`⚠️  README.md not found. Please create it manually.`);
  }

  // Skip Flutter UI components - they are app-specific, not part of the framework
  console.log('\n⏭️  Skipping Flutter UI components (app-specific, not framework)');

  // Create a minimal index.ts example
  console.log('\n📄 Creating minimal index.ts example...');
  const indexExample = `import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import agentRoutes from './routes/agent';
import { errorHandler } from './middleware/errorHandler';
import { notFoundHandler } from './middleware/notFoundHandler';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 4000;

// Middleware
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
  credentials: true,
}));
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Agent route
app.use('/api/agent', agentRoutes);

// Error handling
app.use(notFoundHandler);
app.use(errorHandler);

// Start server
app.listen(PORT, () => {
  console.log(\`🚀 Agent Framework server running on http://localhost:\${PORT}\`);
  console.log(\`📊 Health check: http://localhost:\${PORT}/health\`);
  console.log(\`🔍 Agent endpoint: http://localhost:\${PORT}/api/agent\`);
});

export default app;
`;
  const indexDest = path.join(TARGET_DIR, 'index.ts');
  fs.writeFileSync(indexDest, indexExample);
  console.log(`✅ Created: index.ts (minimal example)`);

  console.log('\n✨ Extraction complete!');
  console.log(`\n📁 Extracted files are in: ${path.join(__dirname, 'agent-framework')}`);
  console.log('\n📊 Summary:');
  console.log(`   - Core agent files: ${AGENT_DIRS.length} directories`);
  console.log(`   - Core services: ${AGENT_SERVICES.length} files`);
  console.log(`   - Middleware: ${AGENT_MIDDLEWARE.length} files`);
  console.log(`   - Routes: ${AGENT_ROUTES.length} file`);
  console.log('\n⚠️  Next steps:');
  console.log('1. Review extracted files for any app-specific code');
  console.log('2. Create abstraction interfaces for search/LLM providers');
  console.log('3. Update package.json dependencies (remove app-specific packages)');
  console.log('4. Add example integrations in examples/ directory');
  console.log('5. Add tests');
  console.log('6. Review and update README.md if needed');
}

main();


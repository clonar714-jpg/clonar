/**
 * ✅ Drizzle ORM Database Setup
 * SQLite database using better-sqlite3
 */

import { drizzle } from 'drizzle-orm/better-sqlite3';
import Database from 'better-sqlite3';
import * as schema from './schema';
import path from 'path';
import fs from 'fs';
import { runMigrations } from './migrate';

const DATA_DIR = process.env.DATA_DIR || process.cwd();
const dbPath = path.join(DATA_DIR, './data/db.sqlite');

// Ensure data directory exists
const dataDir = path.dirname(dbPath);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const sqlite = new Database(dbPath);
const db = drizzle(sqlite, {
  schema: schema,
});

// Run migrations on initialization
runMigrations();

export default db;


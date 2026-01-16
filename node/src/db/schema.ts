/**
 * ✅ Drizzle Schema
 * Database schema definitions for SQLite
 */

import { sql } from 'drizzle-orm';
import { text, integer, sqliteTable, index } from 'drizzle-orm/sqlite-core';
import { Block } from '../agent/types';
import { SearchSources } from '../agent/types';

export const messages = sqliteTable('messages', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  messageId: text('messageId').notNull(),
  chatId: text('chatId').notNull(),
  backendId: text('backendId').notNull(),
  query: text('query').notNull(),
  createdAt: text('createdAt').notNull().default(sql`CURRENT_TIMESTAMP`),
  responseBlocks: text('responseBlocks', { mode: 'json' })
    .$type<Block[]>()
    .default(sql`'[]'`),
  status: text('status', { enum: ['answering', 'completed', 'error'] }).default(
    'answering',
  ),
}, (table) => ({
  chatIdIdx: index('idx_messages_chat_id').on(table.chatId),
  messageIdIdx: index('idx_messages_message_id').on(table.chatId, table.messageId),
}));

interface DBFile {
  name: string;
  fileId: string;
}

export const chats = sqliteTable('chats', {
  id: text('id').primaryKey(),
  title: text('title').notNull(),
  createdAt: text('createdAt').notNull().default(sql`CURRENT_TIMESTAMP`),
  sources: text('sources', {
    mode: 'json',
  })
    .$type<SearchSources[]>()
    .default(sql`'[]'`),
  files: text('files', { mode: 'json' })
    .$type<DBFile[]>()
    .default(sql`'[]'`),
}, (table) => ({
  createdAtIdx: index('idx_chats_created_at').on(table.createdAt),
}));

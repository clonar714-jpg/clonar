import { z } from 'zod';

/**
 * ✅ IMPROVEMENT: Type-safe request validation using Zod
 * 
 * Benefits:
 * - Type inference for TypeScript
 * - Detailed error messages
 * - Single source of truth for request structure
 * - Runtime validation with compile-time types
 */

// Conversation history item schema
const conversationHistoryItemSchema = z.object({
  query: z.string().min(1, 'Query cannot be empty'),
  summary: z.string().optional(),
  intent: z.string().optional(),
  cardType: z.string().optional(),
});

// Main agent request body schema
export const agentRequestSchema = z.object({
  query: z.string().min(1, 'Query is required and cannot be empty'),
  conversationHistory: z.array(conversationHistoryItemSchema).optional().default([]),
  stream: z.union([z.boolean(), z.enum(['true', 'false'])]).optional().default(false),
  sessionId: z.string().optional(),
  conversationId: z.string().optional(),
  userId: z.string().optional(),
  lastFollowUp: z.string().optional(),
  parentQuery: z.string().optional(),
  imageUrl: z.union([z.string().url(), z.literal('')]).optional(),
});

// Infer TypeScript type from schema
export type AgentRequestBody = z.infer<typeof agentRequestSchema>;

/**
 * Validates agent request body
 * @param data - Request body to validate
 * @returns Validation result with typed data or detailed errors
 */
export function validateAgentRequest(data: unknown): {
  success: true;
  data: AgentRequestBody;
} | {
  success: false;
  error: Array<{ path: string; message: string }>;
} {
  const result = agentRequestSchema.safeParse(data);

  if (!result.success) {
    return {
      success: false,
      error: result.error.errors.map((e) => ({
        path: e.path.join('.') || 'root',
        message: e.message,
      })),
    };
  }

  return {
    success: true,
    data: result.data,
  };
}


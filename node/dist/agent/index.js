// MOVED VERBATIM — NO LOGIC CHANGES
import express from "express";
import { handleAgentRequestSimple as handleAgentRequest } from "./agent.handler.simple";
import { requestQueue, getProcessingCount, incrementProcessingCount, decrementProcessingCount, MAX_CONCURRENT_REQUESTS, MAX_QUEUE_SIZE, processQueue } from "./agent.queue";
const router = express.Router();
/**
 * MAIN AGENT ENDPOINT
 * Handles:
 * - First queries
 * - Follow-up queries
 * - Streaming or non-stream
 * ✅ FIX: Added request queuing to prevent overwhelming the system
 */
router.post("/", async (req, res) => {
    // ✅ PRODUCTION-GRADE: Log ALL incoming requests FIRST (before any processing)
    const requestId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    const timestamp = new Date().toISOString();
    console.log(`\n📥 [${timestamp}] [${requestId}] ========== NEW REQUEST ==========`);
    console.log(`   Method: POST /api/agent`);
    console.log(`   Query: "${req.body?.query || 'MISSING'}"`);
    console.log(`   Has conversationHistory: ${!!req.body?.conversationHistory}`);
    console.log(`   ConversationHistory length: ${Array.isArray(req.body?.conversationHistory) ? req.body.conversationHistory.length : 'N/A'}`);
    console.log(`   Headers: user-id=${req.headers['user-id'] || 'MISSING'}, content-type=${req.headers['content-type'] || 'MISSING'}`);
    console.log(`   Body keys: ${Object.keys(req.body || {}).join(', ') || 'EMPTY'}`);
    // ✅ FIX: Check queue size
    if (requestQueue.length >= MAX_QUEUE_SIZE) {
        console.error(`❌ [${requestId}] Queue full (${requestQueue.length}/${MAX_QUEUE_SIZE}), rejecting`);
        return res.status(503).json({
            error: "Server busy",
            message: "Too many requests in queue. Please try again in a moment."
        });
    }
    // ✅ FIX: If we have capacity, process immediately
    const currentProcessingCount = getProcessingCount();
    if (currentProcessingCount < MAX_CONCURRENT_REQUESTS) {
        console.log(`✅ [${requestId}] Processing immediately (${currentProcessingCount}/${MAX_CONCURRENT_REQUESTS} active)`);
        incrementProcessingCount();
        try {
            await handleAgentRequest(req, res);
            console.log(`✅ [${requestId}] Request completed successfully`);
        }
        catch (err) {
            console.error(`❌ [${requestId}] Request error:`, err);
            if (!res.headersSent) {
                const { createErrorResponse } = await import("../utils/errorResponse");
                res.status(500).json(createErrorResponse("Request failed", undefined, "REQUEST_ERROR"));
            }
        }
        finally {
            decrementProcessingCount();
            processQueue();
        }
    }
    else {
        // ✅ FIX: Queue the request
        console.log(`⏳ [${requestId}] Queued (${requestQueue.length} in queue, ${currentProcessingCount} processing)`);
        await new Promise((resolve) => {
            requestQueue.push({ req, res, resolve });
            processQueue();
        });
    }
});
export default router;

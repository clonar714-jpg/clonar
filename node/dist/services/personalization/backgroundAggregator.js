/**
 * Phase 4: Background Jobs for Automated Preference Aggregation
 * Aggregates preferences every 5 conversations OR every 24 hours
 */
import { aggregateUserPreferences } from "./preferenceAggregator";
import { getRecentSignals } from "./preferenceStorage";
import { db } from "../database";
// Track conversation counts per user (in-memory, resets on restart)
// In production, this could be stored in database
const conversationCounts = new Map();
// Track last aggregation time per user
const lastAggregationTime = new Map();
/**
 * Check if user needs aggregation
 * Returns true if:
 * - User has 5+ new conversations since last aggregation, OR
 * - 24 hours have passed since last aggregation
 */
function shouldAggregate(userId) {
    const userData = conversationCounts.get(userId);
    const lastAgg = lastAggregationTime.get(userId);
    // Check conversation count (5+ conversations)
    if (userData && userData.count >= 5) {
        return true;
    }
    // Check time (24 hours)
    if (lastAgg) {
        const hoursSinceLastAgg = (Date.now() - lastAgg.getTime()) / (1000 * 60 * 60);
        if (hoursSinceLastAgg >= 24) {
            return true;
        }
    }
    else {
        // Never aggregated, check if user has enough signals
        return true; // Will check signal count in aggregateIfNeeded
    }
    return false;
}
/**
 * Increment conversation count for user
 * Called after each query that stores a preference signal
 */
export function incrementConversationCount(userId) {
    const current = conversationCounts.get(userId);
    if (current) {
        conversationCounts.set(userId, {
            count: current.count + 1,
            lastAggregated: current.lastAggregated,
        });
    }
    else {
        conversationCounts.set(userId, {
            count: 1,
            lastAggregated: new Date(),
        });
    }
}
/**
 * Aggregate preferences for a user if needed
 * Called periodically or after conversation count threshold
 */
export async function aggregateIfNeeded(userId) {
    if (!userId || userId === "global" || userId === "dev-user-id") {
        return;
    }
    try {
        // Check if aggregation is needed
        if (!shouldAggregate(userId)) {
            return;
        }
        // Check if user has enough signals (minimum 3)
        const signals = await getRecentSignals(userId, 10);
        if (signals.length < 3) {
            console.log(`ℹ️ Not enough signals for user ${userId} (${signals.length} < 3), skipping aggregation`);
            return;
        }
        console.log(`🔄 Phase 4: Aggregating preferences for user ${userId} (${signals.length} signals)`);
        // Aggregate preferences
        const result = await aggregateUserPreferences(userId);
        if (result) {
            // Reset conversation count
            conversationCounts.set(userId, {
                count: 0,
                lastAggregated: new Date(),
            });
            lastAggregationTime.set(userId, new Date());
            console.log(`✅ Phase 4: Aggregated preferences for user ${userId}`);
        }
    }
    catch (err) {
        console.error(`❌ Phase 4: Error aggregating preferences for user ${userId}:`, err.message);
    }
}
/**
 * Clean up old preference signals (keep last 100 per user)
 */
export async function cleanupOldSignals(userId) {
    if (!userId || userId === "global" || userId === "dev-user-id") {
        return;
    }
    try {
        // Get all signals for user (ordered by created_at DESC)
        const { data: signals, error } = await db.preferenceSignals()
            .select("id, created_at")
            .eq("user_id", userId)
            .order("created_at", { ascending: false });
        if (error) {
            console.error(`❌ Error fetching signals for cleanup:`, error);
            return;
        }
        if (!signals || signals.length <= 100) {
            // No cleanup needed
            return;
        }
        // Get IDs of signals to delete (keep first 100, delete the rest)
        const signalsToDelete = signals.slice(100).map(s => s.id);
        if (signalsToDelete.length > 0) {
            // Delete old signals
            const { error: deleteError } = await db.preferenceSignals()
                .delete()
                .in("id", signalsToDelete);
            if (deleteError) {
                console.error(`❌ Error deleting old signals:`, deleteError);
            }
            else {
                console.log(`🧹 Phase 4: Cleaned up ${signalsToDelete.length} old signals for user ${userId}`);
            }
        }
    }
    catch (err) {
        console.error(`❌ Phase 4: Error cleaning up signals for user ${userId}:`, err.message);
    }
}
/**
 * Process a single user (aggregate + cleanup)
 */
async function processUser(userId) {
    await aggregateIfNeeded(userId);
    await cleanupOldSignals(userId);
}
/**
 * Get all users who have preference signals
 */
async function getUsersWithSignals() {
    try {
        const { data, error } = await db.preferenceSignals()
            .select("user_id")
            .order("created_at", { ascending: false });
        if (error) {
            console.error(`❌ Error fetching users with signals:`, error);
            return [];
        }
        // Get unique user IDs
        const userIds = [...new Set((data || []).map((s) => s.user_id))];
        return userIds.filter(id => id && id !== "global" && id !== "dev-user-id");
    }
    catch (err) {
        console.error(`❌ Error getting users with signals:`, err.message);
        return [];
    }
}
/**
 * Run background aggregation for all users
 * Called periodically (every hour)
 */
export async function runBackgroundAggregation() {
    console.log(`🔄 Phase 4: Starting background aggregation job...`);
    try {
        // Get all users with signals
        const userIds = await getUsersWithSignals();
        if (userIds.length === 0) {
            console.log(`ℹ️ Phase 4: No users with signals to process`);
            return;
        }
        console.log(`🔄 Phase 4: Processing ${userIds.length} users...`);
        // Process users in batches (to avoid overwhelming the system)
        const BATCH_SIZE = 10;
        for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
            const batch = userIds.slice(i, i + BATCH_SIZE);
            // Process batch in parallel
            await Promise.allSettled(batch.map(userId => processUser(userId)));
            // Small delay between batches
            if (i + BATCH_SIZE < userIds.length) {
                await new Promise(resolve => setTimeout(resolve, 1000)); // 1 second delay
            }
        }
        console.log(`✅ Phase 4: Background aggregation job completed`);
    }
    catch (err) {
        console.error(`❌ Phase 4: Background aggregation job failed:`, err.message);
    }
}
// ✅ Production-grade: Prevent multiple schedulers from running
let schedulerStarted = false;
let backgroundInterval = null;
let initialTimeout = null;
/**
 * Start background job scheduler
 * Runs aggregation every hour
 * Production-grade: Prevents duplicate schedulers, clears old intervals
 */
export function startBackgroundJob() {
    // ✅ Guard: Prevent multiple schedulers (important for hot reload in dev mode)
    if (schedulerStarted) {
        console.log(`⚠️ Phase 4: Background job scheduler already started, skipping duplicate call`);
        return;
    }
    console.log(`🚀 Phase 4: Starting background aggregation scheduler (runs every hour)`);
    // ✅ Clear any existing intervals (safety check)
    if (backgroundInterval) {
        clearInterval(backgroundInterval);
        backgroundInterval = null;
    }
    if (initialTimeout) {
        clearTimeout(initialTimeout);
        initialTimeout = null;
    }
    // Run immediately on startup (after 30 seconds to let server initialize)
    initialTimeout = setTimeout(() => {
        runBackgroundAggregation();
        initialTimeout = null;
    }, 30000); // 30 seconds
    // Then run every hour
    backgroundInterval = setInterval(() => {
        runBackgroundAggregation();
    }, 60 * 60 * 1000); // 1 hour
    schedulerStarted = true;
    console.log(`✅ Phase 4: Background job scheduler started`);
}
/**
 * Stop background job scheduler (for testing or graceful shutdown)
 */
export function stopBackgroundJob() {
    if (backgroundInterval) {
        clearInterval(backgroundInterval);
        backgroundInterval = null;
    }
    if (initialTimeout) {
        clearTimeout(initialTimeout);
        initialTimeout = null;
    }
    schedulerStarted = false;
    console.log(`🛑 Phase 4: Background job scheduler stopped`);
}

// ✅ PHASE 10: Per-User Throttling & Query Queue Control
class UserThrottleManager {
    constructor() {
        this.activeQueries = new Map(); // userId -> count
        this.queryQueue = [];
        this.maxActivePerUser = 3;
        this.maxQueueSize = 100;
    }
    /**
     * Check if user can make a query
     */
    canMakeQuery(userId) {
        const active = this.activeQueries.get(userId) || 0;
        return active < this.maxActivePerUser;
    }
    /**
     * Register active query
     */
    registerQuery(userId) {
        const current = this.activeQueries.get(userId) || 0;
        this.activeQueries.set(userId, current + 1);
    }
    /**
     * Unregister active query
     */
    unregisterQuery(userId) {
        const current = this.activeQueries.get(userId) || 0;
        if (current > 0) {
            this.activeQueries.set(userId, current - 1);
        }
        else {
            this.activeQueries.delete(userId);
        }
        // Process next in queue
        this.processQueue();
    }
    /**
     * Queue a query with priority
     */
    async queueQuery(userId, query, isFollowUp = false) {
        return new Promise((resolve, reject) => {
            if (this.queryQueue.length >= this.maxQueueSize) {
                reject(new Error('Query queue is full'));
                return;
            }
            const priority = isFollowUp ? 10 : 5; // Follow-ups get higher priority
            this.queryQueue.push({
                userId,
                query,
                priority,
                timestamp: Date.now(),
                resolve,
                reject,
            });
            // Sort by priority (higher first), then by timestamp
            this.queryQueue.sort((a, b) => {
                if (b.priority !== a.priority) {
                    return b.priority - a.priority;
                }
                return a.timestamp - b.timestamp;
            });
            // Try to process immediately
            this.processQueue();
        });
    }
    /**
     * Process queued queries
     */
    processQueue() {
        while (this.queryQueue.length > 0) {
            const queued = this.queryQueue[0];
            if (this.canMakeQuery(queued.userId)) {
                // Can process
                this.queryQueue.shift();
                this.registerQuery(queued.userId);
                queued.resolve(undefined);
            }
            else {
                // Can't process yet, wait
                break;
            }
        }
    }
    /**
     * Get queue status
     */
    getQueueStatus() {
        return {
            queueLength: this.queryQueue.length,
            activeUsers: this.activeQueries.size,
        };
    }
    /**
     * Clear queue for user (on error/timeout)
     */
    clearUserQueue(userId) {
        this.queryQueue = this.queryQueue.filter(q => q.userId !== userId);
        this.activeQueries.delete(userId);
    }
}
// ✅ PHASE 10: Global user throttle manager
export const userThrottleManager = new UserThrottleManager();



import { aggregateUserPreferences } from "./preferenceAggregator";
import { getRecentSignals, getUserPreferences } from "./preferenceStorage";
import { db } from "../database";


const conversationCounts: Map<string, { count: number; lastAggregated: Date }> = new Map();


const lastAggregationTime: Map<string, Date> = new Map();


function shouldAggregate(userId: string): boolean {
  const userData = conversationCounts.get(userId);
  const lastAgg = lastAggregationTime.get(userId);

  
  if (userData && userData.count >= 5) {
    return true;
  }


  if (lastAgg) {
    const hoursSinceLastAgg = (Date.now() - lastAgg.getTime()) / (1000 * 60 * 60);
    if (hoursSinceLastAgg >= 24) {
      return true;
    }
  } else {
    
    return true; 
  }

  return false;
}


export function incrementConversationCount(userId: string): void {
  const current = conversationCounts.get(userId);
  if (current) {
    conversationCounts.set(userId, {
      count: current.count + 1,
      lastAggregated: current.lastAggregated,
    });
  } else {
    conversationCounts.set(userId, {
      count: 1,
      lastAggregated: new Date(),
    });
  }
}


export async function aggregateIfNeeded(userId: string): Promise<void> {
  if (!userId || userId === "global" || userId === "dev-user-id") {
    return;
  }

  try {
    
    if (!shouldAggregate(userId)) {
      return;
    }

    
    const signals = await getRecentSignals(userId, 10);
    if (signals.length < 3) {
      console.log(`ℹ️ Not enough signals for user ${userId} (${signals.length} < 3), skipping aggregation`);
      return;
    }

    console.log(`🔄 Phase 4: Aggregating preferences for user ${userId} (${signals.length} signals)`);

   
    const result = await aggregateUserPreferences(userId);

    if (result) {
      
      conversationCounts.set(userId, {
        count: 0,
        lastAggregated: new Date(),
      });
      lastAggregationTime.set(userId, new Date());

      console.log(`✅ Phase 4: Aggregated preferences for user ${userId}`);
    }
  } catch (err: any) {
    console.error(`❌ Phase 4: Error aggregating preferences for user ${userId}:`, err.message);
  }
}


export async function cleanupOldSignals(userId: string): Promise<void> {
  if (!userId || userId === "global" || userId === "dev-user-id") {
    return;
  }

  try {
   
    const { data: signals, error } = await db.preferenceSignals()
      .select("id, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false });

    if (error) {
      console.error(`❌ Error fetching signals for cleanup:`, error);
      return;
    }

    if (!signals || signals.length <= 100) {
     
      return;
    }

    
    const signalsToDelete = signals.slice(100).map(s => s.id);

    if (signalsToDelete.length > 0) {
      
      const { error: deleteError } = await db.preferenceSignals()
        .delete()
        .in("id", signalsToDelete);

      if (deleteError) {
        console.error(`❌ Error deleting old signals:`, deleteError);
      } else {
        console.log(`🧹 Phase 4: Cleaned up ${signalsToDelete.length} old signals for user ${userId}`);
      }
    }
  } catch (err: any) {
    console.error(`❌ Phase 4: Error cleaning up signals for user ${userId}:`, err.message);
  }
}


async function processUser(userId: string): Promise<void> {
  await aggregateIfNeeded(userId);
  await cleanupOldSignals(userId);
}


async function getUsersWithSignals(): Promise<string[]> {
  try {
    const { data, error } = await db.preferenceSignals()
      .select("user_id")
      .order("created_at", { ascending: false });

    if (error) {
      console.error(`❌ Error fetching users with signals:`, error);
      return [];
    }

   
    const userIds = [...new Set((data || []).map((s: any) => s.user_id))];
    return userIds.filter(id => id && id !== "global" && id !== "dev-user-id");
  } catch (err: any) {
    console.error(`❌ Error getting users with signals:`, err.message);
    return [];
  }
}


export async function runBackgroundAggregation(): Promise<void> {
  console.log(`🔄 Phase 4: Starting background aggregation job...`);

  try {
    
    const userIds = await getUsersWithSignals();

    if (userIds.length === 0) {
      console.log(`ℹ️ Phase 4: No users with signals to process`);
      return;
    }

    console.log(`🔄 Phase 4: Processing ${userIds.length} users...`);

    
    const BATCH_SIZE = 10;
    for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
      const batch = userIds.slice(i, i + BATCH_SIZE);
      
    
      await Promise.allSettled(
        batch.map(userId => processUser(userId))
      );

      
      if (i + BATCH_SIZE < userIds.length) {
        await new Promise(resolve => setTimeout(resolve, 1000)); // 1 second delay
      }
    }

    console.log(`✅ Phase 4: Background aggregation job completed`);
  } catch (err: any) {
    console.error(`❌ Phase 4: Background aggregation job failed:`, err.message);
  }
}


let schedulerStarted = false;
let backgroundInterval: NodeJS.Timeout | null = null;
let initialTimeout: NodeJS.Timeout | null = null;


export function startBackgroundJob(): void {
  
  if (schedulerStarted) {
    console.log(`⚠️ Phase 4: Background job scheduler already started, skipping duplicate call`);
    return;
  }

  console.log(`🚀 Phase 4: Starting background aggregation scheduler (runs every hour)`);

  if (backgroundInterval) {
    clearInterval(backgroundInterval);
    backgroundInterval = null;
  }
  if (initialTimeout) {
    clearTimeout(initialTimeout);
    initialTimeout = null;
  }

 
  initialTimeout = setTimeout(() => {
    runBackgroundAggregation();
    initialTimeout = null;
  }, 30000); 

  
  backgroundInterval = setInterval(() => {
    runBackgroundAggregation();
  }, 60 * 60 * 1000); 

  schedulerStarted = true;
  console.log(`✅ Phase 4: Background job scheduler started`);
}


export function stopBackgroundJob(): void {
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


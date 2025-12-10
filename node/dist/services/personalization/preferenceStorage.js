/**
 * Preference Storage Service
 * Handles storing and retrieving user preferences
 */
import { db } from "../database";
/**
 * Store preference signal (non-blocking, async)
 */
export async function storePreferenceSignal(signal) {
    try {
        // Use admin client to bypass RLS (signals are stored server-side)
        const { error } = await db.preferenceSignals()
            .insert({
            user_id: signal.user_id,
            conversation_id: signal.conversation_id || null,
            query: signal.query,
            intent: signal.intent || null,
            style_keywords: signal.style_keywords || [],
            price_mentions: signal.price_mentions || [],
            brand_mentions: signal.brand_mentions || [],
            rating_mentions: signal.rating_mentions || [],
            cards_shown: signal.cards_shown ? JSON.stringify(signal.cards_shown) : null,
            user_interaction: signal.user_interaction ? JSON.stringify(signal.user_interaction) : null,
        });
        if (error) {
            console.error("❌ Error storing preference signal:", error);
            // Don't throw - this is non-critical
        }
        else {
            console.log(`✅ Stored preference signal for user ${signal.user_id}`);
        }
    }
    catch (err) {
        console.error("❌ Unexpected error storing preference signal:", err.message);
        // Don't throw - this is non-critical
    }
}
/**
 * Get user preferences (cached in production)
 */
export async function getUserPreferences(userId) {
    try {
        const { data, error } = await db.userPreferences()
            .select("*")
            .eq("user_id", userId)
            .single();
        if (error) {
            if (error.code === 'PGRST116') {
                // No preferences found (not an error)
                return null;
            }
            console.error("❌ Error fetching user preferences:", error);
            return null;
        }
        return data;
    }
    catch (err) {
        console.error("❌ Unexpected error fetching user preferences:", err.message);
        return null;
    }
}
/**
 * Update user preferences
 */
export async function updateUserPreferences(userId, preferences) {
    try {
        // Check if preferences exist
        const existing = await getUserPreferences(userId);
        if (existing) {
            // Update existing
            const { data, error } = await db.userPreferences()
                .update({
                ...preferences,
                last_updated_at: new Date().toISOString(),
            })
                .eq("user_id", userId)
                .select()
                .single();
            if (error) {
                console.error("❌ Error updating user preferences:", error);
                return null;
            }
            return data;
        }
        else {
            // Create new
            const { data, error } = await db.userPreferences()
                .insert({
                user_id: userId,
                ...preferences,
            })
                .select()
                .single();
            if (error) {
                console.error("❌ Error creating user preferences:", error);
                return null;
            }
            return data;
        }
    }
    catch (err) {
        console.error("❌ Unexpected error updating user preferences:", err.message);
        return null;
    }
}
/**
 * Get recent preference signals for a user
 */
export async function getRecentSignals(userId, limit = 50) {
    try {
        const { data, error } = await db.preferenceSignals()
            .select("*")
            .eq("user_id", userId)
            .order("created_at", { ascending: false })
            .limit(limit);
        if (error) {
            console.error("❌ Error fetching preference signals:", error);
            return [];
        }
        return (data || []).map((signal) => ({
            user_id: signal.user_id,
            conversation_id: signal.conversation_id,
            query: signal.query,
            intent: signal.intent,
            style_keywords: signal.style_keywords || [],
            price_mentions: signal.price_mentions || [],
            brand_mentions: signal.brand_mentions || [],
            rating_mentions: signal.rating_mentions || [],
            cards_shown: signal.cards_shown ? JSON.parse(signal.cards_shown) : [],
            user_interaction: signal.user_interaction ? JSON.parse(signal.user_interaction) : {},
        }));
    }
    catch (err) {
        console.error("❌ Unexpected error fetching preference signals:", err.message);
        return [];
    }
}

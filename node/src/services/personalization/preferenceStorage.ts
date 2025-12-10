/**
 * Preference Storage Service
 * Handles storing and retrieving user preferences
 */

import { db } from "../database";

export interface UserPreferences {
  id?: string;
  user_id: string;
  style_keywords?: string[];
  price_range_min?: number;
  price_range_max?: number;
  category_preferences?: Record<string, any>;
  brand_preferences?: string[];
  confidence_score?: number;
  conversations_analyzed?: number;
  last_updated_at?: string;
  created_at?: string;
}

export interface PreferenceSignal {
  user_id: string;
  conversation_id?: string;
  query: string;
  intent?: string;
  style_keywords?: string[];
  price_mentions?: string[];
  brand_mentions?: string[];
  rating_mentions?: string[];
  cards_shown?: any[];
  user_interaction?: Record<string, any>;
}

/**
 * Store preference signal (non-blocking, async)
 */
export async function storePreferenceSignal(signal: PreferenceSignal): Promise<void> {
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
    } else {
      console.log(`✅ Stored preference signal for user ${signal.user_id}`);
    }
  } catch (err: any) {
    console.error("❌ Unexpected error storing preference signal:", err.message);
    // Don't throw - this is non-critical
  }
}

/**
 * Get user preferences (cached in production)
 */
export async function getUserPreferences(userId: string): Promise<UserPreferences | null> {
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

    return data as UserPreferences;
  } catch (err: any) {
    console.error("❌ Unexpected error fetching user preferences:", err.message);
    return null;
  }
}

/**
 * Update user preferences
 */
export async function updateUserPreferences(
  userId: string,
  preferences: Partial<UserPreferences>
): Promise<UserPreferences | null> {
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

      return data as UserPreferences;
    } else {
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

      return data as UserPreferences;
    }
  } catch (err: any) {
    console.error("❌ Unexpected error updating user preferences:", err.message);
    return null;
  }
}

/**
 * Get recent preference signals for a user
 */
export async function getRecentSignals(
  userId: string,
  limit: number = 50
): Promise<PreferenceSignal[]> {
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

    return (data || []).map((signal: any) => ({
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
  } catch (err: any) {
    console.error("❌ Unexpected error fetching preference signals:", err.message);
    return [];
  }
}


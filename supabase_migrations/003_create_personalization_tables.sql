-- =====================================================
-- Personalization System Tables
-- =====================================================

-- Table 1: user_preferences (aggregated user preferences)
CREATE TABLE IF NOT EXISTS user_preferences (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Style Preferences (learned from conversations)
  style_keywords TEXT[], -- ["luxury", "budget", "modern", "vintage"]
  price_range_min DECIMAL(10,2),
  price_range_max DECIMAL(10,2),
  
  -- Category-specific preferences (JSONB for flexibility)
  category_preferences JSONB DEFAULT '{}', 
  -- Example: {"hotels": {"rating_min": 4, "style": "luxury"}, "watches": {"brands": ["Rolex", "Omega"]}}
  
  -- Brand preferences (learned from searches)
  brand_preferences TEXT[],
  
  -- Preference strength (confidence)
  confidence_score DECIMAL(3,2) DEFAULT 0.0 CHECK (confidence_score >= 0.0 AND confidence_score <= 1.0),
  
  -- Metadata
  conversations_analyzed INT DEFAULT 0,
  last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(user_id)
);

-- ✅ FIX: Add missing columns if table already exists
DO $$ 
BEGIN
  -- Add last_updated_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_preferences' 
    AND column_name = 'last_updated_at'
  ) THEN
    ALTER TABLE user_preferences 
    ADD COLUMN last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
  END IF;
  
  -- Add created_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_preferences' 
    AND column_name = 'created_at'
  ) THEN
    ALTER TABLE user_preferences 
    ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
  END IF;
END $$;

-- Table 2: preference_signals (raw signals from conversations for incremental learning)
CREATE TABLE IF NOT EXISTS preference_signals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID, -- Optional: link to conversation (if using conversation_messages table)
  query TEXT NOT NULL,
  intent TEXT, -- "shopping", "hotels", "flights", etc.
  
  -- Extracted signals
  style_keywords TEXT[], -- ["luxury", "5-star"]
  price_mentions TEXT[], -- ["$200-$500", "expensive"]
  brand_mentions TEXT[],
  rating_mentions TEXT[], -- ["4-star", "5-star"]
  
  -- Context (what was shown to user)
  cards_shown JSONB, -- Products/hotels shown in results
  user_interaction JSONB DEFAULT '{}', -- Future: clicks, time spent, etc.
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON user_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_preferences_last_updated ON user_preferences(last_updated_at);

CREATE INDEX IF NOT EXISTS idx_preference_signals_user_id ON preference_signals(user_id);
CREATE INDEX IF NOT EXISTS idx_preference_signals_created_at ON preference_signals(created_at);
CREATE INDEX IF NOT EXISTS idx_preference_signals_intent ON preference_signals(intent);

-- Row Level Security (RLS)
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE preference_signals ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_preferences
CREATE POLICY "Users can view their own preferences"
  ON user_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own preferences"
  ON user_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own preferences"
  ON user_preferences FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own preferences"
  ON user_preferences FOR DELETE
  USING (auth.uid() = user_id);

-- RLS Policies for preference_signals
CREATE POLICY "Users can view their own signals"
  ON preference_signals FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own signals"
  ON preference_signals FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own signals"
  ON preference_signals FOR DELETE
  USING (auth.uid() = user_id);

-- Function to automatically update last_updated_at
CREATE OR REPLACE FUNCTION update_user_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ✅ FIX: Create trigger only if table and column exist
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_preferences' 
    AND column_name = 'last_updated_at'
  ) THEN
    -- Drop trigger if exists (to avoid conflicts)
    DROP TRIGGER IF EXISTS update_user_preferences_updated_at ON user_preferences;
    
    -- Create trigger
    CREATE TRIGGER update_user_preferences_updated_at
      BEFORE UPDATE ON user_preferences
      FOR EACH ROW
      EXECUTE FUNCTION update_user_preferences_updated_at();
  END IF;
END $$;

-- Function to clean old preference signals (keep last 100 per user)
CREATE OR REPLACE FUNCTION cleanup_old_preference_signals()
RETURNS void AS $$
BEGIN
  DELETE FROM preference_signals
  WHERE id NOT IN (
    SELECT id FROM preference_signals
    WHERE user_id = preference_signals.user_id
    ORDER BY created_at DESC
    LIMIT 100
  );
END;
$$ LANGUAGE plpgsql;


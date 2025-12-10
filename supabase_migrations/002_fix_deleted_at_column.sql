-- ✅ Fix: Add deleted_at column if it doesn't exist
-- Run this if you get an error about deleted_at column missing

-- Add deleted_at column to conversations table if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'conversations' 
    AND column_name = 'deleted_at'
  ) THEN
    ALTER TABLE conversations ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
    RAISE NOTICE 'Added deleted_at column to conversations table';
  ELSE
    RAISE NOTICE 'deleted_at column already exists';
  END IF;
END $$;

-- Create index on deleted_at if it doesn't exist
CREATE INDEX IF NOT EXISTS idx_conversations_deleted_at 
ON conversations(deleted_at) 
WHERE deleted_at IS NULL;


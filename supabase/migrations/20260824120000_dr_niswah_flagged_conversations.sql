-- Clinical-review log for red-flag symptoms caught by the Dr. Niswah chat
-- backend. Written only by the dr-niswah-chat edge function via the
-- service role, which bypasses RLS — no client-facing policies are needed
-- since RLS with zero policies denies anon/authenticated access outright.

CREATE TABLE IF NOT EXISTS flagged_conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  thread_id UUID REFERENCES chat_threads(id) ON DELETE CASCADE,
  message_excerpt TEXT NOT NULL,
  matched_categories TEXT[] NOT NULL,
  reviewed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_flagged_conversations_user_id_created_at
  ON flagged_conversations(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_flagged_conversations_reviewed
  ON flagged_conversations(reviewed) WHERE reviewed = false;

ALTER TABLE flagged_conversations ENABLE ROW LEVEL SECURITY;

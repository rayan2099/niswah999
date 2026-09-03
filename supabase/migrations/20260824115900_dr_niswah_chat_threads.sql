-- chat_threads / chat_messages back the ai_assistant feature (general chat,
-- Doctor Niswah, and fiqh advisory threads — see
-- lib/features/ai_assistant/data/repositories/chat_repository_impl.dart).
-- These tables are documented in supabase/schema.sql but were never turned
-- into an applied migration, which is why 20260824120000's
-- flagged_conversations.thread_id FK to chat_threads(id) failed with
-- "relation chat_threads does not exist" — chat_threads was missing on the
-- remote database, not misnamed.
--
-- NOTE: the thread_type CHECK values below intentionally differ from
-- schema.sql's ('dr_niswah','dream_interpreter','general') — schema.sql's
-- snake_case values don't match ChatThreadType.name in
-- lib/features/ai_assistant/domain/entities/chat_thread.dart, which writes
-- the raw Dart enum names ('drNiswah','dreamInterpreter','general',
-- 'fiqhAdvisory') via `threadType.name`. Copying schema.sql verbatim here
-- would have made every "drNiswah" or "fiqhAdvisory" thread insert fail
-- the CHECK constraint. schema.sql should be corrected to match.

CREATE TABLE IF NOT EXISTS chat_threads (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New conversation',
  thread_type TEXT NOT NULL CHECK (thread_type IN ('drNiswah','dreamInterpreter','general','fiqhAdvisory')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived','deleted')),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  thread_id UUID NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user','assistant','system')),
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_threads_user_id_created_at
  ON chat_threads(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_id_created_at
  ON chat_messages(thread_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_chat_messages_user_id
  ON chat_messages(user_id);

ALTER TABLE chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own chat_threads" ON chat_threads
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own chat_threads" ON chat_threads
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own chat_threads" ON chat_threads
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own chat_threads" ON chat_threads
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read their own chat_messages or messages in their threads" ON chat_messages
  FOR SELECT USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1
      FROM chat_threads ct
      WHERE ct.id = chat_messages.thread_id
        AND ct.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert messages into their own chat threads" ON chat_messages
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM chat_threads ct
      WHERE ct.id = chat_messages.thread_id
        AND ct.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their own chat messages" ON chat_messages
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own chat messages" ON chat_messages
  FOR DELETE USING (auth.uid() = user_id);

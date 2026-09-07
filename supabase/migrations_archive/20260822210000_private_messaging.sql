-- Private Direct Messaging schema
-- Conversations track active chat threads between exactly two users.
-- Messages store individual messages within a conversation.

CREATE TABLE IF NOT EXISTS private_conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  participant_one UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  participant_two UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT no_self_conversation CHECK (participant_one <> participant_two),
  -- Enforce one conversation per unordered pair of users
  CONSTRAINT unique_pair UNIQUE (participant_one, participant_two)
);

CREATE TABLE IF NOT EXISTS private_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES private_conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (length(content) > 0 AND length(content) <= 5000),
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for fast querying
CREATE INDEX IF NOT EXISTS idx_private_conversations_participant_one
  ON private_conversations(participant_one);
CREATE INDEX IF NOT EXISTS idx_private_conversations_participant_two
  ON private_conversations(participant_two);
CREATE INDEX IF NOT EXISTS idx_private_conversations_updated_at
  ON private_conversations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_private_messages_conversation_id_created_at
  ON private_messages(conversation_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_private_messages_sender_id
  ON private_messages(sender_id);

-- Row Level Security
ALTER TABLE private_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_messages ENABLE ROW LEVEL SECURITY;

-- Helper: current user participates in a conversation
CREATE OR REPLACE FUNCTION is_conversation_participant(conversation UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM private_conversations pc
    WHERE pc.id = conversation
      AND (pc.participant_one = auth.uid() OR pc.participant_two = auth.uid())
  );
$$;

-- Conversations policies
CREATE POLICY "Participants can read their conversations" ON private_conversations
  FOR SELECT USING (
    auth.uid() = participant_one OR auth.uid() = participant_two
  );

CREATE POLICY "Users can create conversations they participate in" ON private_conversations
  FOR INSERT WITH CHECK (
    auth.uid() = participant_one OR auth.uid() = participant_two
  );

CREATE POLICY "Participants can update their conversations" ON private_conversations
  FOR UPDATE USING (
    auth.uid() = participant_one OR auth.uid() = participant_two
  )
  WITH CHECK (
    auth.uid() = participant_one OR auth.uid() = participant_two
  );

-- Messages policies
CREATE POLICY "Participants can read messages in their conversations" ON private_messages
  FOR SELECT USING (is_conversation_participant(conversation_id));

CREATE POLICY "Participants can send messages in their conversations" ON private_messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND is_conversation_participant(conversation_id)
  );

-- Only the recipient may mark messages as read (sender's own messages stay unread-flagged by them)
CREATE POLICY "Recipients can mark messages as read" ON private_messages
  FOR UPDATE USING (
    is_conversation_participant(conversation_id) AND auth.uid() <> sender_id
  )
  WITH CHECK (
    is_conversation_participant(conversation_id) AND auth.uid() <> sender_id
  );

-- Trigger: keep conversation updated_at fresh when a message is added
CREATE OR REPLACE FUNCTION touch_private_conversation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE private_conversations
  SET updated_at = now()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_private_conversation ON private_messages;
CREATE TRIGGER trg_touch_private_conversation
AFTER INSERT ON private_messages
FOR EACH ROW EXECUTE FUNCTION touch_private_conversation();
-- Lets a user read her own flagged_conversations rows, so the Doctor's
-- Report can surface recent red-flag chat concerns. The table stays
-- otherwise locked down (still no INSERT/UPDATE/DELETE policy for
-- clients — only the dr-niswah-chat edge function's service role writes
-- to it) — this is read-only, self-scoped access, not a general opening.

DROP POLICY IF EXISTS "Users can read their own flagged_conversations" ON flagged_conversations;
CREATE POLICY "Users can read their own flagged_conversations" ON flagged_conversations
  FOR SELECT USING (auth.uid() = user_id);

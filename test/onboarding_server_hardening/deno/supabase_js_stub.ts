// Offline stand-in for https://esm.sh/@supabase/supabase-js@2 (type-only use
// in ai_user_context.ts). Mapped in via import_map.json.
export type SupabaseClient = unknown;
export function createClient(): never {
  throw new Error('not available in offline hardening tests');
}

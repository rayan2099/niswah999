-- Pins the search_path of public.bleeding_local_today (added by
-- 20261029100000_bleeding_episode_corrections.sql), flagged by the
-- Supabase security advisor (lint 0011 function_search_path_mutable).
-- The body only uses pg_catalog functions; this changes no behavior.
-- Idempotent.
ALTER FUNCTION public.bleeding_local_today(integer) SET search_path TO 'public';

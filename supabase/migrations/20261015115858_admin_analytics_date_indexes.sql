-- Date-leading indexes for owner aggregate windows across all accounts.
-- Existing wellbeing indexes start with user_id and serve personal reports.
begin;
create index wellbeing_logs_analytics_date_idx on public.wellbeing_logs(log_date);
create index cycle_analytics_received_at_idx on public.cycle_analytics_snapshots(received_at);
commit;

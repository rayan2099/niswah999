-- Activation template, to run only after the inbox migration and worker have
-- been approved, applied and tested on the intended environment.
-- Required: pg_cron, pg_net, Supabase Vault. Store the worker URL and a random
-- >=32-character worker secret in Vault under the names below. The same secret
-- must be set as NOTIFICATION_WORKER_SECRET on the Edge Function.
-- This template contains no credential or automatic environment selection.
begin;
do $$ begin
  if not exists(select 1 from vault.decrypted_secrets where name='notification_worker_url') or
     not exists(select 1 from vault.decrypted_secrets where name='notification_worker_secret' and length(decrypted_secret)>=32) then
    raise exception 'Create notification_worker_url and notification_worker_secret in Vault before activation';
  end if;
end $$;
create or replace function notification_private.dispatch_worker()
returns void language plpgsql security definer set search_path='' as $$
declare worker_url text; worker_secret text;
begin
 select decrypted_secret into strict worker_url from vault.decrypted_secrets where name='notification_worker_url';
 select decrypted_secret into strict worker_secret from vault.decrypted_secrets where name='notification_worker_secret';
 if worker_url !~ '^https://[a-z0-9]{20}\.supabase\.co/functions/v1/notification-dispatch$'
    or length(worker_secret)<32 then raise exception 'Invalid notification worker configuration'; end if;
 perform net.http_post(url:=worker_url,headers:=jsonb_build_object('Content-Type','application/json',
   'Authorization','Bearer '||worker_secret),body:='{}'::jsonb,timeout_milliseconds:=60000);
end $$;
revoke all on function notification_private.dispatch_worker() from public,anon,authenticated;
grant execute on function notification_private.dispatch_worker() to service_role;
select cron.schedule('niswah-notification-dispatch','* * * * *','select notification_private.dispatch_worker();');
commit;

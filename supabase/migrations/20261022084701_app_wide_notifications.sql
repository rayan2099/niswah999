-- A durable, account-private activity inbox plus a leased push outbox.
-- All text shown on a locked phone is generated generically by the worker.
create schema if not exists notification_private;
revoke all on schema notification_private from public, anon, authenticated;
grant usage on schema notification_private to service_role;

create function notification_private.valid_timezone(zone text)
returns boolean language sql stable security invoker set search_path = '' as $$
 select exists(select 1 from pg_catalog.pg_timezone_names where name=zone); $$;
revoke all on function notification_private.valid_timezone(text) from public,anon;
grant usage on schema notification_private to authenticated;
grant execute on function notification_private.valid_timezone(text) to authenticated, service_role;

create function notification_private.has_live_session()
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from auth.sessions
   where id=nullif(auth.jwt()->>'session_id','')::uuid and user_id=auth.uid()
     and (not_after is null or not_after>now())); $$;
revoke all on function notification_private.has_live_session() from public,anon;
grant execute on function notification_private.has_live_session() to authenticated;

create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  messages boolean not null default true,
  comments boolean not null default true,
  likes boolean not null default false,
  quiet_enabled boolean not null default false,
  quiet_start integer not null default 1320 check (quiet_start between 0 and 1439),
  quiet_end integer not null default 480 check (quiet_end between 0 and 1439),
  timezone text not null default 'UTC' check(notification_private.valid_timezone(timezone)),
  locale text not null default 'ar' check (locale in ('ar','en')),
  check (quiet_start <> quiet_end)
);
alter table public.notification_preferences enable row level security;
grant select, insert, update on public.notification_preferences to authenticated;
create policy own_notification_preferences on public.notification_preferences to authenticated
  using (user_id = (select auth.uid()) and (select notification_private.has_live_session())) with check (user_id = (select auth.uid()) and (select notification_private.has_live_session()));

create table public.notification_inbox (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('privateMessage','communityComment','communityLike')),
  target_id uuid not null,
  source_id uuid not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (recipient_id, kind, source_id)
);
create unique index notification_daily_like_group on public.notification_inbox(recipient_id,target_id,((created_at at time zone 'UTC')::date)) where kind='communityLike';
create index notification_inbox_recipient_created on public.notification_inbox(recipient_id, created_at desc);
create index notification_inbox_group on public.notification_inbox(recipient_id,kind,target_id,created_at desc);
create index notification_inbox_unread on public.notification_inbox(recipient_id) where read_at is null;
alter table public.notification_inbox enable row level security;
grant select on public.notification_inbox to authenticated;
grant update (read_at) on public.notification_inbox to authenticated;
create policy read_own_notification_inbox on public.notification_inbox for select to authenticated
  using (recipient_id = (select auth.uid()) and (select notification_private.has_live_session()));
-- Read time is the server's, and a read event cannot be made unread again
-- (which would re-arm phone delivery from a device clock or a stale client).
create function notification_private.stamp_inbox_read()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 -- Database-owned activity (a newer like regrouping) may resurface an event.
 if current_user not in ('authenticated','anon') then return new; end if;
 if old.read_at is not null then new.read_at := old.read_at;
 elsif new.read_at is not null then new.read_at := now(); end if;
 return new;
end $$;
revoke all on function notification_private.stamp_inbox_read() from public,anon,authenticated;
create trigger notification_inbox_read_stamp before update of read_at on public.notification_inbox
  for each row execute function notification_private.stamp_inbox_read();
create policy mark_own_notification_read on public.notification_inbox for update to authenticated
  using (recipient_id = (select auth.uid()) and (select notification_private.has_live_session())) with check (recipient_id = (select auth.uid()) and (select notification_private.has_live_session()));

create table notification_private.devices (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references auth.sessions(id) on delete cascade,
  token text not null unique check (length(token) between 20 and 4096),
  platform text not null check (platform in ('android','ios')),
  updated_at timestamptz not null default now()
);
create index notification_devices_recipient on notification_private.devices(recipient_id);
create index notification_devices_session on notification_private.devices(session_id);
alter table notification_private.devices enable row level security;

create table notification_private.push_jobs (
  id uuid primary key default gen_random_uuid(),
  inbox_id uuid not null references public.notification_inbox(id) on delete cascade,
  device_id uuid not null references notification_private.devices(id) on delete cascade,
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  lease_id uuid,
  leased_until timestamptz,
  accepted_at timestamptz,
  suppressed_at timestamptz,
  unique(inbox_id,device_id)
);
create index notification_jobs_ready on notification_private.push_jobs(available_at)
  where accepted_at is null and suppressed_at is null and attempts < 5;
alter table notification_private.push_jobs enable row level security;
grant all on all tables in schema notification_private to service_role;
grant all on public.notification_inbox, public.notification_preferences to service_role;

-- These functions are not exposed by PostgREST. The narrow public wrappers
-- are SECURITY INVOKER; each private registration operation authenticates
-- the session and can only bind/unbind the caller's own device.
create function notification_private.register_device(p_token text, p_platform text)
returns void language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); s uuid;
begin
  if u is null then raise exception 'Authentication required' using errcode='42501'; end if;
  s := nullif(auth.jwt()->>'session_id','')::uuid;
  if not exists (select 1 from auth.sessions where id=s and user_id=u and (not_after is null or not_after>now())) then
    raise exception 'Active session required' using errcode='42501';
  end if;
  -- Limit token abuse; account switching updates the one globally unique
  -- token instead of duplicating recipients. Reinstalling issues a new
  -- installation ID without signing out, so at the limit the least recently
  -- registered device is retired rather than refusing the current phone.
  if not exists(select 1 from notification_private.devices where token=p_token and recipient_id=u) then
    delete from notification_private.devices where id in (
      select id from notification_private.devices where recipient_id=u
      order by updated_at desc, id offset 9);
  end if;
  insert into notification_private.devices(recipient_id, session_id, token, platform)
    values(u,s,p_token,p_platform)
    on conflict(token) do update set recipient_id=u,session_id=s,platform=p_platform,updated_at=now();
end $$;
create function notification_private.unregister_device(p_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  delete from notification_private.devices where token=p_token and recipient_id=auth.uid();
end $$;
revoke all on function notification_private.register_device(text,text),
  notification_private.unregister_device(text) from public,anon;
grant usage on schema notification_private to authenticated;
grant execute on function notification_private.register_device(text,text),
  notification_private.unregister_device(text) to authenticated;
create function public.register_notification_device(p_token text, p_platform text)
returns void language sql security invoker set search_path = '' as $$
 select notification_private.register_device(p_token,p_platform); $$;
create function public.unregister_notification_device(p_token text)
returns void language sql security invoker set search_path = '' as $$
 select notification_private.unregister_device(p_token); $$;
revoke all on function public.register_notification_device(text,text),public.unregister_notification_device(text) from public,anon;
grant execute on function public.register_notification_device(text,text),public.unregister_notification_device(text) to authenticated;

create function notification_private.queue_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient uuid; target uuid; k text; event_id uuid; hidden boolean;
begin
 -- Activity is secondary to the message, comment or like itself: an inbox
 -- failure is logged and never rolls back the person's own write.
 begin
  if tg_table_name = 'private_messages' then
    select case when participant_one=new.sender_id then participant_two else participant_one end
      into recipient from public.private_conversations
      where id=new.conversation_id and new.sender_id in (participant_one,participant_two);
    target := new.conversation_id; k := 'privateMessage';
  else
    select user_id, coalesce((to_jsonb(cp)->>'is_hidden')::boolean,false) into recipient,hidden from public.community_posts cp where id=new.post_id;
    if hidden then return new; end if;
    if tg_table_name='community_comments' and coalesce((to_jsonb(new)->>'is_hidden')::boolean,false) then return new; end if;
    if recipient=new.user_id then return new; end if;
    target := new.post_id;
    k := case when tg_table_name='community_comments' then 'communityComment' else 'communityLike' end;
    -- One like activity per post/day; comments/messages retain their event ids.
    -- A later like moves the group onto a like that still exists (an unliked
    -- source would otherwise silence the whole day) and marks it unread. Its
    -- phone alert is re-armed only if none was accepted yet today.
    if k='communityLike' then
      update public.notification_inbox set source_id=new.id, read_at=null
        where recipient_id=recipient and kind=k and target_id=target
          and created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'
        returning id into event_id;
      if event_id is not null then
        insert into notification_private.push_jobs as j(inbox_id,device_id)
          select event_id,id from notification_private.devices where recipient_id=recipient
          on conflict (inbox_id,device_id) do update set attempts=0, available_at=now(), suppressed_at=null
          where j.accepted_at is null and (j.leased_until is null or j.leased_until<now());
        return new;
      end if;
    end if;
  end if;
  if recipient is null then return new; end if;
  insert into public.notification_inbox(recipient_id,kind,target_id,source_id)
    values(recipient,k,target,new.id) on conflict do nothing returning id into event_id;
  if event_id is not null then
    insert into notification_private.push_jobs(inbox_id,device_id)
      select event_id,id from notification_private.devices where recipient_id=recipient
      on conflict do nothing;
  end if;
 exception when others then
  raise warning 'notification activity skipped for %: %', tg_table_name, sqlstate;
 end;
 return new;
end $$;
revoke all on function notification_private.queue_activity() from public,anon,authenticated;
create trigger notification_message_created after insert on public.private_messages
  for each row execute function notification_private.queue_activity();
create trigger notification_comment_created after insert on public.community_comments
  for each row execute function notification_private.queue_activity();
create trigger notification_like_created after insert on public.community_likes
  for each row execute function notification_private.queue_activity();

-- Authoritative eligibility is checked when claiming and again just before
-- sending. Reads, opt-outs, deleted/hidden content and revoked sessions cancel
-- old deliveries. Quiet hours defer; expired events are never sent later.
create function notification_private.push_eligible(event_id uuid, device uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
select exists (
 select 1 from public.notification_inbox i
 join notification_private.devices d on d.id=device and d.recipient_id=i.recipient_id
 join auth.sessions s on s.id=d.session_id and s.user_id=d.recipient_id and (s.not_after is null or s.not_after>now())
 left join public.notification_preferences p on p.user_id=i.recipient_id
 where i.id=event_id and i.read_at is null and i.created_at > now()-interval '24 hours'
 and case i.kind when 'privateMessage' then coalesce(p.messages,true)
   when 'communityComment' then coalesce(p.comments,true) else coalesce(p.likes,false) end
 and (not coalesce(p.quiet_enabled,false) or
   case when p.quiet_start < p.quiet_end then
     (extract(hour from now() at time zone coalesce(p.timezone,'UTC'))*60+
      extract(minute from now() at time zone coalesce(p.timezone,'UTC')))
       not between p.quiet_start and p.quiet_end-1
   else
     (extract(hour from now() at time zone coalesce(p.timezone,'UTC'))*60+
      extract(minute from now() at time zone coalesce(p.timezone,'UTC')))
       between p.quiet_end and p.quiet_start-1 end)
 and case when i.kind='privateMessage' then exists(
   select 1 from public.private_messages m join public.private_conversations c on c.id=m.conversation_id
   where m.id=i.source_id and not m.is_read and m.conversation_id=i.target_id
     and i.recipient_id in (c.participant_one,c.participant_two))
 else exists(select 1 from public.community_posts cp where cp.id=i.target_id and cp.user_id=i.recipient_id
   and not coalesce((to_jsonb(cp)->>'is_hidden')::boolean,false))
   and (i.kind<>'communityLike' or exists(select 1 from public.community_likes cl where cl.id=i.source_id))
   and (i.kind<>'communityComment' or exists(select 1 from public.community_comments cc
     where cc.id=i.source_id and not coalesce((to_jsonb(cc)->>'is_hidden')::boolean,false))) end
); $$;
revoke all on function notification_private.push_eligible(uuid,uuid) from public,anon,authenticated;
grant execute on function notification_private.push_eligible(uuid,uuid) to service_role;

create function public.claim_notification_push(batch_limit integer default 50)
returns table(job_id uuid, lease_id uuid, inbox_id uuid, recipient_id uuid, kind text,
 target_id uuid, device_id uuid, token text, locale text)
language plpgsql security invoker set search_path = '' as $$
begin
 -- Collapse unsent activity to the newest event per device/conversation or
 -- post. Superseded jobs are not misreported as provider-accepted.
 update notification_private.push_jobs j set suppressed_at=now()
 where j.id in (
   select old.id from notification_private.push_jobs old
   join public.notification_inbox oi on oi.id=old.inbox_id
   where old.accepted_at is null and old.suppressed_at is null
     and (old.leased_until is null or old.leased_until<now())
     and exists(select 1 from notification_private.push_jobs newer
       join public.notification_inbox ni on ni.id=newer.inbox_id
       where newer.device_id=old.device_id and ni.recipient_id=oi.recipient_id
       and ni.kind=oi.kind and ni.target_id=oi.target_id
       and (ni.created_at,ni.id)>(oi.created_at,oi.id))
   limit 500 for update of old skip locked
 );
 return query
 with picked as (
   select j.id from notification_private.push_jobs j
   where j.accepted_at is null and j.suppressed_at is null and j.attempts<5 and j.available_at<=now()
     and (j.leased_until is null or j.leased_until<now())
     and notification_private.push_eligible(j.inbox_id,j.device_id)
     and not exists(select 1 from notification_private.push_jobs recent
       join public.notification_inbox ri on ri.id=recent.inbox_id
       join public.notification_inbox candidate on candidate.id=j.inbox_id
       where recent.device_id=j.device_id and ri.kind=candidate.kind and ri.target_id=candidate.target_id
         and recent.accepted_at>now()-case when ri.kind='privateMessage' then interval '1 minute' else interval '5 minutes' end)
   order by j.available_at,j.id for update skip locked limit least(greatest(batch_limit,1),100)
 ), claimed as (
   update notification_private.push_jobs j set leased_until=now()+interval '2 minutes',
     lease_id=gen_random_uuid(), attempts=attempts+1 from picked where j.id=picked.id returning j.*
 ) select j.id,j.lease_id,i.id,i.recipient_id,i.kind,i.target_id,d.id,d.token,coalesce(p.locale,'ar')
   from claimed j join public.notification_inbox i on i.id=j.inbox_id
   join notification_private.devices d on d.id=j.device_id
   left join public.notification_preferences p on p.user_id=i.recipient_id;
end $$;
create function public.confirm_notification_push(p_job uuid,p_lease uuid)
returns boolean language sql security invoker set search_path = '' as $$
 select exists(select 1 from notification_private.push_jobs j where j.id=p_job and j.lease_id=p_lease
   and j.leased_until>now() and j.accepted_at is null and j.suppressed_at is null
   and notification_private.push_eligible(j.inbox_id,j.device_id)); $$;
create function public.finish_notification_push(p_job uuid,p_lease uuid,p_accepted boolean,p_invalid_token boolean default false)
returns void language plpgsql security invoker set search_path = '' as $$
declare device uuid;
begin
 update notification_private.push_jobs set accepted_at=case when p_accepted then now() else null end,
   available_at=now()+make_interval(secs=>least(3600,30*power(2,attempts)::integer)),
   leased_until=null,lease_id=null
   where id=p_job and lease_id=p_lease returning device_id into device;
 if p_invalid_token and device is not null then delete from notification_private.devices where id=device; end if;
end $$;
revoke all on function public.claim_notification_push(integer), public.confirm_notification_push(uuid,uuid),
 public.finish_notification_push(uuid,uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.claim_notification_push(integer),public.confirm_notification_push(uuid,uuid),
 public.finish_notification_push(uuid,uuid,boolean,boolean) to service_role;
-- The publication exists on Supabase; no changes to the protected realtime schema.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notification_inbox') then
     alter publication supabase_realtime add table public.notification_inbox;
   end if;
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='private_messages') then
     alter publication supabase_realtime add table public.private_messages;
   end if;
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='private_conversations') then
     alter publication supabase_realtime add table public.private_conversations;
   end if;
 end if;
end $$;

create function notification_private.read_message_activity()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.is_read and not old.is_read then
   update public.notification_inbox set read_at=coalesce(read_at,now()) where kind='privateMessage' and source_id=new.id;
 end if;
 return new;
end $$;
revoke all on function notification_private.read_message_activity() from public,anon,authenticated;
create trigger notification_message_read after update of is_read on public.private_messages
 for each row execute function notification_private.read_message_activity();

create function public.cleanup_notification_activity()
returns void language plpgsql security invoker set search_path='' as $$
begin
 delete from notification_private.push_jobs where id in (
   select j.id from notification_private.push_jobs j join public.notification_inbox i on i.id=j.inbox_id
   where i.created_at<now()-interval '24 hours' or i.read_at is not null
     or j.suppressed_at<now()-interval '1 day' or j.accepted_at<now()-interval '7 days'
   limit 1000);
 delete from public.notification_inbox where id in (select id from public.notification_inbox
   where created_at<now()-interval '90 days' limit 1000);
end $$;
revoke all on function public.cleanup_notification_activity() from public,anon,authenticated;
grant execute on function public.cleanup_notification_activity() to service_role;

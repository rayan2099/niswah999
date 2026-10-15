-- Operational monitoring: aggregate workflow milestones, content-free AI metrics,
-- and actionable incident follow-up. Apply only to staging until verified.
begin;
create table public.onboarding_milestones (
 user_id uuid not null references auth.users(id) on delete cascade,
 step text not null check(step in ('started','madhhab','marital','location','last_period','period_length','privacy','welcome','completed')),
 first_seen_at timestamptz not null default now(),
 primary key(user_id,step)
);
alter table public.onboarding_milestones enable row level security;
revoke all on public.onboarding_milestones from public,anon,authenticated;
-- Only the narrow RPC below writes milestones, with server-owned timestamps.
create function public.record_onboarding_milestone(p_step text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  raise exception 'Account required' using errcode='42501';
 end if;
 if p_step not in ('started','madhhab','marital','location','last_period','period_length','privacy','welcome','completed') or p_step is null then
  raise exception 'Unknown milestone' using errcode='22023';
 end if;
 if p_step='completed' and not exists(select 1 from public.users where id=auth.uid() and onboarding_completed) then
  raise exception 'Completion not saved' using errcode='22023';
 end if;
 insert into public.onboarding_milestones(user_id,step) values(auth.uid(),'started') on conflict do nothing;
 insert into public.onboarding_milestones(user_id,step) values(auth.uid(),p_step) on conflict do nothing;
end $$;
revoke all on function public.record_onboarding_milestone(text) from public,anon;
grant execute on function public.record_onboarding_milestone(text) to authenticated;

create table niswah_admin.ai_events (
 id uuid primary key default gen_random_uuid(),
 advisor text not null check(advisor in ('ai-assistant-chat','dr-niswah-chat','fiqh-advisor-chat','dream-interpreter-chat')),
 kind text not null check(kind in ('endpoint','model')),
 status integer not null check(status between 100 and 599),
 duration_ms integer not null check(duration_ms between 0 and 300000),
 model text check(length(model)<=100),
 input_tokens bigint check(input_tokens>=0),output_tokens bigint check(output_tokens>=0),
 created_at timestamptz not null default now()
);
create index ai_events_recent on niswah_admin.ai_events(created_at desc,advisor,kind);
alter table niswah_admin.ai_events enable row level security;
revoke all on niswah_admin.ai_events from public,anon,authenticated;
-- Only trusted Edge Functions with the existing server service key may ingest.
-- No arbitrary metadata field: raw prompts, replies and identifiers have no destination.
create function public.record_ai_operation(p_event jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from jsonb_object_keys(p_event) k where k not in ('advisor','kind','status','duration_ms','model','input_tokens','output_tokens')) then
  raise exception 'Unexpected metric field' using errcode='22023';
 end if;
 insert into niswah_admin.ai_events(advisor,kind,status,duration_ms,model,input_tokens,output_tokens)
 values(p_event->>'advisor',p_event->>'kind',(p_event->>'status')::integer,(p_event->>'duration_ms')::integer,
 p_event->>'model',(p_event->>'input_tokens')::bigint,(p_event->>'output_tokens')::bigint);
end $$;
revoke all on function public.record_ai_operation(jsonb) from public,anon,authenticated;
grant execute on function public.record_ai_operation(jsonb) to service_role;

create table niswah_admin.incidents (
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(trim(title)) between 5 and 160),
 source text not null default 'manual' check(source in ('manual','ai_errors','support_backlog','review_backlog','telemetry_stale')),
 status text not null default 'open' check(status in ('open','acknowledged','resolved')),
 assigned_to uuid references auth.users(id) on delete set null,
 due_at timestamptz not null default now()+interval '2 days',
 created_by uuid not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index one_active_incident_per_signal on niswah_admin.incidents(source) where source<>'manual' and status<>'resolved';
alter table niswah_admin.incidents enable row level security;
revoke all on niswah_admin.incidents from public,anon,authenticated;

create function niswah_admin.operations_data() returns jsonb language sql stable set search_path='' as $$
 with
 endpoint_stats as (
  select advisor,count(*) as requests,
   count(*) filter(where status>=500) as server_errors,
   count(*) filter(where status=429) as rate_limited,
   count(*) filter(where status between 400 and 499 and status<>429) as rejected,
   round((percentile_cont(.95) within group(order by duration_ms))::numeric) as p95_ms
  from niswah_admin.ai_events where kind='endpoint' and created_at>=now()-interval '7 days' group by advisor
 ), model_stats as (
  select advisor,count(*) as calls,count(*) filter(where status>=400) as failures,
   sum(input_tokens) as input_tokens,sum(output_tokens) as output_tokens,
   count(*) filter(where input_tokens is null or output_tokens is null) as usage_missing
  from niswah_admin.ai_events where kind='model' and created_at>=now()-interval '7 days' group by advisor
 ), latest as (
  select advisor,max(created_at) as last_seen_at from niswah_admin.ai_events group by advisor
 ), funnel as (
  select step,count(*) as reached from public.onboarding_milestones m join auth.users a on a.id=m.user_id
  where a.is_anonymous is not true group by step
 ), counts as (
  select
   (select count(*) from niswah_admin.tickets where status<>'resolved' and (priority='high' or created_at<now()-interval '48 hours')) as support_backlog,
   (select count(*) from public.knowledge_item_versions v where not exists(select 1 from niswah_admin.reviews r where r.version_id=v.id)) as review_backlog,
   (select count(*) from niswah_admin.ai_events where created_at>=now()-interval '1 hour' and status>=500 and kind='model') as ai_errors,
   (select max(created_at) from niswah_admin.ai_events) as ai_last_seen
 )
 select jsonb_build_object(
 'as_of',now(),
 'open_incidents',(select count(*) from niswah_admin.incidents where status<>'resolved'),
 'overdue_incidents',(select count(*) from niswah_admin.incidents where status<>'resolved' and due_at<now()),
 'incidents',(select coalesce(jsonb_agg(t),'[]') from (
   select i.*,s.email as assignee_email from niswah_admin.incidents i left join auth.users s on s.id=i.assigned_to
   order by case when i.status='resolved' then 1 else 0 end,i.due_at,i.id limit 100
  ) t),
 'assignees',(select coalesce(jsonb_agg(t),'[]') from (
   select s.user_id,a.email from niswah_admin.staff s join auth.users a on a.id=s.user_id
   where s.active and s.role in ('owner','operator') order by a.email
  ) t),
 'alerts',(select coalesce(jsonb_agg(t),'[]') from (
   select 'ai_errors' as key,'إخفاقات في توليد إجابات الذكاء الاصطناعي' as title,ai_errors as count,'high' as severity,'operations' as section
   from counts where ai_errors>=5
   union all select 'support_backlog','طلبات دعم عاجلة أو تجاوزت ٤٨ ساعة',support_backlog,'normal','support' from counts where support_backlog>0
   union all select 'review_backlog','نسخ معرفة بدون قرار مراجعة عبر اللوحة',review_backlog,'normal','knowledge' from counts where review_backlog>0
   union all select 'telemetry_stale','لم تصل بيانات AI منذ أكثر من ٢٤ ساعة',null,'normal','operations' from counts where ai_last_seen<now()-interval '24 hours'
  ) t),
 'funnel',jsonb_build_object(
   'state',case when exists(select 1 from funnel) then 'receiving' else 'not_connected' end,
   'since',(select min(first_seen_at) from public.onboarding_milestones m join auth.users a on a.id=m.user_id where a.is_anonymous is not true),
   'steps',(select jsonb_agg(jsonb_build_object('step',step,'reached',coalesce(f.reached,0)) order by ordinal) from
     unnest(array['started','madhhab','marital','location','last_period','period_length','privacy','welcome','completed']) with ordinality steps(step,ordinal)
     left join funnel f using(step))
 ),
 'ai',(select jsonb_agg(jsonb_build_object('advisor',a.advisor,'last_seen_at',l.last_seen_at,
   'state',case when l.last_seen_at is null then 'not_connected' when l.last_seen_at<now()-interval '24 hours' then 'stale' else 'receiving' end,
   'requests',e.requests,'server_errors',e.server_errors,'rate_limited',e.rate_limited,'rejected',e.rejected,'p95_ms',e.p95_ms,
   'model_calls',m.calls,'model_failures',m.failures,'input_tokens',m.input_tokens,'output_tokens',m.output_tokens,'usage_missing',m.usage_missing))
   from unnest(array['ai-assistant-chat','dr-niswah-chat','fiqh-advisor-chat','dream-interpreter-chat']) a(advisor)
   left join endpoint_stats e using(advisor) left join model_stats m using(advisor) left join latest l using(advisor)),
 'unconnected',jsonb_build_array('crash_reporting','otp_email_delivery','billing','citation_quality')
 );
$$;
revoke all on function niswah_admin.operations_data() from public,anon,authenticated;

create or replace function public.niswah_admin_api(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; statistics jsonb; info jsonb; target uuid; assignee uuid;
begin
 if (p_action='list' and p_input->>'section'='operations') or p_action in ('create_incident','update_incident') then
  -- Reuse the original private guard for membership + live-session checks.
  info:=niswah_admin.niswah_admin_api('session');
  if auth.jwt()->>'aal' is distinct from 'aal2' or info->>'role' not in ('owner','operator') then
   raise exception 'Permission denied' using errcode='42501';
  end if;
  if p_action='list' then
   insert into niswah_admin.audit(actor_id,action) values(auth.uid(),'read.operations');
   return jsonb_build_object('data',niswah_admin.operations_data());
  end if;
  assignee:=nullif(p_input->>'assigned_to','')::uuid;
  if assignee is not null and not exists(select 1 from niswah_admin.staff where user_id=assignee and active and role in ('owner','operator')) then
   raise exception 'Invalid operational assignee' using errcode='22023';
  end if;
  if p_action='create_incident' then
   insert into niswah_admin.incidents(title,source,assigned_to,due_at,created_by)
    values(p_input->>'title',coalesce(p_input->>'source','manual'),assignee,coalesce((p_input->>'due_at')::timestamptz,now()+interval '2 days'),auth.uid()) returning id into target;
  else
   target:=(p_input->>'id')::uuid;
   update niswah_admin.incidents set status=p_input->>'status',assigned_to=assignee,due_at=(p_input->>'due_at')::timestamptz,updated_at=now() where id=target;
   if not found then raise exception 'Incident not found';end if;
  end if;
  insert into niswah_admin.audit(actor_id,action,target_id,details) values(auth.uid(),p_action,target::text,
   jsonb_build_object('assigned_to',assignee,'status',coalesce(p_input->>'status','open'),'due_at',p_input->>'due_at'));
  return jsonb_build_object('id',target);
 end if;
 result:=niswah_admin.niswah_admin_api(p_action,p_input);
 if p_action='list' and coalesce(p_input->>'section','overview')='overview' then
  statistics:=niswah_admin.user_statistics();
  result:=jsonb_set(result,'{data,users}',statistics->'total');
  result:=jsonb_set(result,'{data,new_users_7d}',statistics->'new_7d');
  result:=jsonb_set(result,'{data,onboarded}',statistics->'onboarded');
  if exists(select 1 from niswah_admin.staff where user_id=auth.uid() and role='owner' and active) then
   result:=jsonb_set(result,'{data,statistics}',statistics);
  end if;
  -- Summary has only aggregate signals, no ticket bodies or private content.
  result:=jsonb_set(result,'{data,attention}',jsonb_build_object(
   'alerts',niswah_admin.operations_data()->'alerts',
   'open_incidents',(select count(*) from niswah_admin.incidents where status<>'resolved'),
   'overdue_incidents',(select count(*) from niswah_admin.incidents where status<>'resolved' and due_at<now())
  ));
 end if;
 return result;
end $$;
revoke all on function public.niswah_admin_api(text,jsonb) from public,anon;
grant execute on function public.niswah_admin_api(text,jsonb) to authenticated;
commit;

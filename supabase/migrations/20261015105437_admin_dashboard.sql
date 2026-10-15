-- Admin V1: isolated staff authority; no grants through public.users.role.
-- Apply to staging first. No bootstrap staff member is created by this migration.
begin;
create schema if not exists niswah_admin;
revoke all on schema niswah_admin from public, anon, authenticated;
create table niswah_admin.staff (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check (role in ('owner','support','moderator','editor','medical_reviewer','fiqh_reviewer','operator')),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table niswah_admin.audit (
 id bigint generated always as identity primary key,
 actor_id uuid not null, action text not null, target_id text,
 details jsonb not null default '{}', created_at timestamptz not null default now()
);
create table niswah_admin.tickets (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users(id) on delete set null,
 subject text not null check (length(subject) between 3 and 160),
 status text not null default 'open' check(status in ('open','in_progress','resolved')),
 priority text not null default 'normal' check(priority in ('normal','high')),
 created_by uuid not null, updated_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create table niswah_admin.reviews (
 id uuid primary key default gen_random_uuid(),
 version_id uuid not null references public.knowledge_item_versions(id) on delete restrict,
 reviewer_id uuid not null,
 decision text not null check(decision in ('approved','changes_requested','rejected')),
 note text not null check(length(note) between 10 and 3000),
 created_at timestamptz not null default now()
);
create index on niswah_admin.reviews(version_id,created_at desc);
create table niswah_admin.drafts (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 3 and 160),
 body text not null check(length(body) between 10 and 20000),
 language text not null check(language in ('ar','en')),
 domain text not null check(domain in ('HEALTH','FIQH','NISWAH_PRODUCT')),
 created_by uuid not null, created_at timestamptz not null default now()
);
-- Defense in depth: no API grants/policies on private tables.
alter table niswah_admin.staff enable row level security;
alter table niswah_admin.audit enable row level security;
alter table niswah_admin.tickets enable row level security;
alter table niswah_admin.reviews enable row level security;
alter table niswah_admin.drafts enable row level security;
revoke all on all tables in schema niswah_admin from public, anon, authenticated;

alter table public.community_posts add column if not exists is_hidden boolean not null default false;
alter table public.community_comments add column if not exists is_hidden boolean not null default false;
-- RESTRICTIVE policies combine with existing SELECT permissions; they grant nothing themselves.
create policy admin_visible_posts on public.community_posts as restrictive for select to anon, authenticated using (not is_hidden);
create policy admin_visible_comments on public.community_comments as restrictive for select to anon, authenticated
 using (not is_hidden and exists(select 1 from public.community_posts p where p.id=post_id));
-- End users cannot set the moderation column, even on their own content.
create function niswah_admin.protect_moderation() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user not in ('postgres','service_role') then
  if (TG_OP='INSERT' and new.is_hidden) or (TG_OP='UPDATE' and new.is_hidden is distinct from old.is_hidden) then
   raise exception 'Moderation is staff controlled' using errcode='42501';
  end if;
 end if;
 return new;
end $$;
create trigger admin_post_moderation before insert or update on public.community_posts for each row execute function niswah_admin.protect_moderation();
create trigger admin_comment_moderation before insert or update on public.community_comments for each row execute function niswah_admin.protect_moderation();

-- The only exposed admin entry point. Fixed operations, explicit selects, no arbitrary SQL.
-- SECURITY DEFINER is intentional: cross-user operations cannot use user-owned RLS.
-- Every operation checks a private membership and a live session; data requires AAL2.
create function public.niswah_admin_api(p_action text, p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid := auth.uid(); staff_role text; result jsonb; target uuid;
 section text := coalesce(p_input->>'section','overview');
 q text := left(coalesce(p_input->>'query',''),160);
 page_number integer := greatest(0,least(coalesce((p_input->>'page')::integer,0),100000));
 row_offset integer; permission text; note text; kb_domain text;
begin
 if actor is null or not exists(select 1 from auth.sessions s where s.user_id=actor
  and s.id::text=auth.jwt()->>'session_id' and (s.not_after is null or s.not_after>now())) then
  raise exception 'Session invalid' using errcode='42501';
 end if;
 select role into staff_role from niswah_admin.staff where user_id=actor and active;
 if staff_role is null then raise exception 'Staff access required' using errcode='42501'; end if;
 if p_action='session' then return jsonb_build_object('role',staff_role,'user_id',actor); end if;
 if auth.jwt()->>'aal' is distinct from 'aal2' then raise exception 'MFA required' using errcode='42501'; end if;
 permission := case
  when p_action='list' then section
  when p_action in ('create_ticket','update_ticket') then 'support'
  when p_action='moderate' then 'community'
  when p_action='create_draft' then 'content'
  when p_action='review' then 'knowledge'
  when p_action='set_staff' then 'staff'
  else '' end;
 if staff_role<>'owner' and not (
  (staff_role='support' and permission in ('users','support')) or
  (staff_role='moderator' and permission='community') or
  (staff_role='editor' and permission='content') or
  (staff_role in ('medical_reviewer','fiqh_reviewer') and permission='knowledge') or
  (staff_role='operator' and permission='overview')
 ) then raise exception 'Permission denied' using errcode='42501'; end if;
 row_offset := page_number*25;
 if p_action='list' then
  case section
  when 'overview' then
   select jsonb_build_object(
    'users',(select count(*) from auth.users where is_anonymous is not true),
    'new_users_7d',(select count(*) from auth.users where created_at>=now()-interval '7 days' and is_anonymous is not true),
    'onboarded',(select count(*) from public.users where onboarding_completed),
    'posts',(select count(*) from public.community_posts where not is_hidden),
    'open_tickets',(select count(*) from niswah_admin.tickets where status<>'resolved'),
    'knowledge_versions',(select count(*) from public.knowledge_item_versions),
    'review_decisions',(select count(*) from niswah_admin.reviews),
    'signups', (select coalesce(jsonb_agg(t order by t.day),'[]') from (
      select d::date as day, count(u.id) as count from generate_series(current_date-13,current_date,interval '1 day') d
      left join auth.users u on u.created_at>=d and u.created_at<d+interval '1 day' and u.is_anonymous is not true group by d
    ) t), 'as_of',now()) into result;
  when 'users' then
   select coalesce(jsonb_agg(t),'[]') into result from (
    select a.id,a.email,a.phone,a.created_at,a.last_sign_in_at,
      (a.email_confirmed_at is not null or a.phone_confirmed_at is not null) as verified,
      coalesce(u.onboarding_completed,false) as onboarding_completed
    from auth.users a left join public.users u on u.id=a.id
    where a.is_anonymous is not true and (q='' or a.id::text=q or a.email ilike '%'||q||'%' or a.phone ilike '%'||q||'%')
    order by a.created_at desc,a.id limit 25 offset row_offset
   ) t;
  when 'community' then
   if coalesce(p_input->>'kind','post')='comment' then
    select coalesce(jsonb_agg(t),'[]') into result from (
     select id,post_id,content,is_hidden,created_at from public.community_comments
     where q='' or content ilike '%'||q||'%' order by created_at desc,id limit 25 offset row_offset
    ) t;
   else
    select coalesce(jsonb_agg(t),'[]') into result from (
     select id,title,content,category,is_anonymous,is_hidden,created_at from public.community_posts
     where q='' or title ilike '%'||q||'%' or content ilike '%'||q||'%'
     order by created_at desc,id limit 25 offset row_offset
    ) t;
   end if;
  when 'support' then
   select coalesce(jsonb_agg(t),'[]') into result from (
    select id,user_id,subject,status,priority,created_at,updated_at from niswah_admin.tickets
    where q='' or subject ilike '%'||q||'%' order by updated_at desc,id limit 25 offset row_offset
   ) t;
  when 'knowledge' then
   select coalesce(jsonb_agg(t),'[]') into result from (
    select v.id,k.knowledge_key,k.domain,k.topic,k.madhhab,k.publication_state,v.version,v.language,
      v.canonical_statement,v.qualification_note,v.evidence_state,v.production_eligible,v.evidence_snapshot_commit,
      (select coalesce(jsonb_agg(jsonb_build_object('title',s.title,'reference',s.url_or_reference,'locator',l.locator)),'[]')
       from public.knowledge_item_sources l join public.knowledge_sources s on s.id=l.source_id where l.knowledge_item_version_id=v.id) as sources,
      (select coalesce(jsonb_agg(r order by r.created_at desc),'[]') from (
       select decision,note,reviewer_id,created_at from niswah_admin.reviews where version_id=v.id
      ) r) as reviews
    from public.knowledge_item_versions v join public.knowledge_items k on k.id=v.knowledge_item_id
    where (staff_role in ('owner') or (staff_role='medical_reviewer' and k.domain in ('HEALTH','SAFETY_ESCALATION')) or
     (staff_role='fiqh_reviewer' and k.domain='FIQH'))
    and (q='' or k.knowledge_key ilike '%'||q||'%' or k.topic ilike '%'||q||'%')
    order by k.knowledge_key,v.version desc,v.id limit 25 offset row_offset
   ) t;
  when 'content' then
   select coalesce(jsonb_agg(t),'[]') into result from (
    select * from niswah_admin.drafts where q='' or title ilike '%'||q||'%' order by created_at desc,id limit 25 offset row_offset
   ) t;
  when 'staff' then
   select coalesce(jsonb_agg(t),'[]') into result from (
    select s.user_id,a.email,s.role,s.active,s.created_at from niswah_admin.staff s join auth.users a on a.id=s.user_id
    order by s.created_at,s.user_id limit 25 offset row_offset
   ) t;
  when 'audit' then
   select coalesce(jsonb_agg(t),'[]') into result from (
    select id,actor_id,action,target_id,details,created_at from niswah_admin.audit
    order by id desc limit 25 offset row_offset
   ) t;
  else raise exception 'Unknown section' using errcode='22023';
  end case;
  -- Audit each page viewed without logging search terms, emails or content.
  insert into niswah_admin.audit(actor_id,action,details) values(actor,'read.'||section,jsonb_build_object('page',page_number));
  return jsonb_build_object('data',result,'page',page_number);
 elsif p_action='create_ticket' then
  insert into niswah_admin.tickets(user_id,subject,priority,created_by)
   values(nullif(p_input->>'user_id','')::uuid,p_input->>'subject',coalesce(p_input->>'priority','normal'),actor) returning id into target;
 elsif p_action='update_ticket' then
  target:=(p_input->>'id')::uuid;
  update niswah_admin.tickets set status=p_input->>'status',updated_at=now() where id=target;
  if not found then raise exception 'Ticket not found'; end if;
 elsif p_action='create_draft' then
  insert into niswah_admin.drafts(title,body,language,domain,created_by)
   values(p_input->>'title',p_input->>'body',p_input->>'language',p_input->>'domain',actor) returning id into target;
 elsif p_action='moderate' then
  target:=(p_input->>'id')::uuid;
  note:=p_input->>'note';
  if note is null or length(trim(note))<5 or length(note)>500 then raise exception 'Reason required'; end if;
  if jsonb_typeof(p_input->'hidden') is distinct from 'boolean' then raise exception 'Hidden must be boolean'; end if;
  if p_input->>'kind'='post' then
   update public.community_posts set is_hidden=(p_input->>'hidden')::boolean where id=target;
  elsif p_input->>'kind'='comment' then
   update public.community_comments set is_hidden=(p_input->>'hidden')::boolean where id=target;
  else raise exception 'Unknown moderation kind'; end if;
  if not found then raise exception 'Content not found'; end if;
 elsif p_action='review' then
  target:=(p_input->>'id')::uuid;
  select k.domain into kb_domain from public.knowledge_item_versions v join public.knowledge_items k on k.id=v.knowledge_item_id where v.id=target;
  -- Being the owner does not confer medical/scholarly reviewer qualifications.
  if not ((staff_role='medical_reviewer' and kb_domain in ('HEALTH','SAFETY_ESCALATION')) or
          (staff_role='fiqh_reviewer' and kb_domain='FIQH')) then raise exception 'Qualified reviewer role required' using errcode='42501'; end if;
  insert into niswah_admin.reviews(version_id,reviewer_id,decision,note)
   values(target,actor,p_input->>'decision',p_input->>'note');
 elsif p_action='set_staff' then
  -- Serialize role changes so concurrent requests cannot remove all owners.
  lock table niswah_admin.staff in share row exclusive mode;
  select id into target from auth.users where lower(email)=lower(trim(p_input->>'email')) and email_confirmed_at is not null;
  if target is null then raise exception 'Verified account not found'; end if;
  insert into niswah_admin.staff(user_id,role,active) values(target,p_input->>'role',(p_input->>'active')::boolean)
   on conflict(user_id) do update set role=excluded.role,active=excluded.active;
  if not exists(select 1 from niswah_admin.staff where role='owner' and active) then raise exception 'Keep at least one active owner'; end if;
 else raise exception 'Unknown action' using errcode='22023';
 end if;
 insert into niswah_admin.audit(actor_id,action,target_id,details) values(actor,p_action,target::text,
  case when p_action='moderate' then jsonb_build_object('hidden',p_input->'hidden','kind',p_input->>'kind','reason',note)
       when p_action='set_staff' then jsonb_build_object('role',p_input->>'role','active',p_input->'active')
       when p_action='review' then jsonb_build_object('decision',p_input->>'decision')
       when p_action='update_ticket' then jsonb_build_object('status',p_input->>'status') else '{}'::jsonb end);
 return jsonb_build_object('id',target);
end $$;
revoke all on all functions in schema niswah_admin from public,anon,authenticated;
revoke all on function public.niswah_admin_api(text,jsonb) from public,anon;
grant execute on function public.niswah_admin_api(text,jsonb) to authenticated;
comment on function public.niswah_admin_api is 'Private staff membership + live session + AAL2 required; explicit minimal projections; medical/fiqh decisions never change KB publication eligibility.';
commit;

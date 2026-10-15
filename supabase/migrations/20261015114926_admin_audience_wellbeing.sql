begin;
alter table public.wellbeing_logs add column sleepy boolean;
comment on column public.wellbeing_logs.sleepy is 'Optional explicit daily answer; NULL is unanswered, never inferred from energy or sleep quality.';
-- Latest coarse app-engine snapshot only. Never accept notes, dates of periods,
-- symptoms, coordinates, account IDs, or a client-controlled receipt timestamp.
create table public.cycle_analytics_snapshots (
 user_id uuid primary key references auth.users(id) on delete cascade,
 fiqh_state text not null check(fiqh_state in ('haid','tahara','needsAdvisory','madhhabUnresolved','unknown')),
 bleeding boolean,
 ovulation_estimate boolean,
 pre_period_estimate boolean,
 received_at timestamptz not null default now()
);
alter table public.cycle_analytics_snapshots enable row level security;
revoke all on public.cycle_analytics_snapshots from public,anon,authenticated;
create function public.record_cycle_analytics(p_snapshot jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and is_anonymous is not true) then
  raise exception 'Permission denied' using errcode='42501';
 end if;
 if jsonb_typeof(p_snapshot) is distinct from 'object' or
    p_snapshot - array['fiqh_state','bleeding','ovulation_estimate','pre_period_estimate'] <> '{}'::jsonb or
    coalesce(p_snapshot->>'fiqh_state','') not in ('haid','tahara','needsAdvisory','madhhabUnresolved','unknown') or
    exists(select 1 from jsonb_each(p_snapshot) e where e.key<>'fiqh_state' and jsonb_typeof(e.value) not in ('boolean','null')) or
    ((p_snapshot->>'fiqh_state' in ('haid','needsAdvisory','madhhabUnresolved')) and (p_snapshot->>'bleeding')::boolean is distinct from true) or
    (p_snapshot->>'fiqh_state'='tahara' and (p_snapshot->>'bleeding')::boolean is distinct from false) then
  raise exception 'Invalid cycle snapshot' using errcode='22023';
 end if;
 insert into public.cycle_analytics_snapshots(user_id,fiqh_state,bleeding,ovulation_estimate,pre_period_estimate)
 values(auth.uid(),p_snapshot->>'fiqh_state',(p_snapshot->>'bleeding')::boolean,
  (p_snapshot->>'ovulation_estimate')::boolean,(p_snapshot->>'pre_period_estimate')::boolean)
 on conflict(user_id) do update set fiqh_state=excluded.fiqh_state,bleeding=excluded.bleeding,
  ovulation_estimate=excluded.ovulation_estimate,pre_period_estimate=excluded.pre_period_estimate,received_at=now();
end $$;
revoke all on function public.record_cycle_analytics(jsonb) from public,anon;
grant execute on function public.record_cycle_analytics(jsonb) to authenticated;

create function niswah_admin.audience_data() returns jsonb language sql stable set search_path='' as $$
 with accounts as (
  select a.id,u.madhhab,u.madhhab_selection_state,
    coalesce(nullif(trim(u.prayer_country),''),'unknown') as country
  from auth.users a left join public.users u on u.id=a.id where a.is_anonymous is not true
 ), fresh as (
  select s.* from public.cycle_analytics_snapshots s join accounts a on a.id=s.user_id
  where s.received_at>=now()-interval '24 hours' and s.received_at<=now()
 ), days as (
  select ((now() at time zone 'Asia/Riyadh')::date-i) as day from generate_series(0,29) i
 ), wellbeing as (
  select w.user_id,w.log_date,w.mood,w.energy,w.sleep,w.sleepy from public.wellbeing_logs w join accounts a on a.id=w.user_id
  where w.log_date between (now() at time zone 'Asia/Riyadh')::date-29 and (now() at time zone 'Asia/Riyadh')::date
 ), daily as (
  select d.day,count(w.user_id) as reports,
   count(*) filter(where mood between 4 and 5) as happy,
   count(*) filter(where mood between 1 and 2) as down,
   count(*) filter(where mood=3) as neutral,
   count(*) filter(where energy between 1 and 2) as low_energy,
   count(*) filter(where sleep between 1 and 2) as poor_sleep,
   count(*) filter(where sleepy is true) as sleepy,
   count(*) filter(where sleepy is not null) as sleepy_reports,
   round(avg(mood) filter(where mood between 1 and 5),2) as mood_avg,
   round(avg(energy) filter(where energy between 1 and 5),2) as energy_avg,
   round(avg(sleep) filter(where sleep between 1 and 5),2) as sleep_avg,
   count(*) filter(where mood between 1 and 5) as mood_reports
  from days d left join wellbeing w on w.log_date=d.day group by d.day
 ), countries as (
  select country,count(*) as users from accounts where country<>'unknown' group by country
 ), top_countries as (select * from countries order by users desc,country limit 12)
 select jsonb_build_object(
  'as_of',now(),'date',(now() at time zone 'Asia/Riyadh')::date,'total',(select count(*) from accounts),
  'countries',jsonb_build_object(
   'rows',(select coalesce(jsonb_agg(t order by users desc,country),'[]') from top_countries t),
   'other',(select coalesce(sum(users),0) from countries where country not in(select country from top_countries)),
   'unknown',(select count(*) from accounts where country='unknown')),
  'madhhab',(select jsonb_build_object(
   'hanafi',count(*) filter(where madhhab_selection_state='selected' and lower(madhhab)='hanafi'),
   'maliki',count(*) filter(where madhhab_selection_state='selected' and lower(madhhab)='maliki'),
   'shafii',count(*) filter(where madhhab_selection_state='selected' and lower(madhhab)='shafii'),
   'hanbali',count(*) filter(where madhhab_selection_state='selected' and lower(madhhab)='hanbali'),
   'unknown',count(*) filter(where madhhab_selection_state='unknown'),
   'unset',count(*) filter(where madhhab_selection_state is distinct from 'unknown' and
     (madhhab_selection_state is distinct from 'selected' or madhhab is null or lower(madhhab) not in ('hanafi','maliki','shafii','hanbali')))
  ) from accounts),
  'cycle',(select jsonb_build_object(
   'fresh',count(*),'missing',(select count(*) from accounts)-count(*),
   'bleeding',count(*) filter(where bleeding is true),
   'no_bleeding',count(*) filter(where bleeding is false),
   'bleeding_unknown',(select count(*) from accounts)-count(*) filter(where bleeding is not null),
   'haid',count(*) filter(where fiqh_state='haid'),
   'tahara',count(*) filter(where fiqh_state='tahara'),
   'needs_advisory',count(*) filter(where fiqh_state='needsAdvisory'),
   'madhhab_unresolved',count(*) filter(where fiqh_state='madhhabUnresolved'),
   'unknown',(select count(*) from accounts)-count(*) filter(where fiqh_state<>'unknown'),
   'ovulation',count(*) filter(where ovulation_estimate is true),
   'pre_period',count(*) filter(where pre_period_estimate is true),
   'prediction_coverage',count(*) filter(where ovulation_estimate is not null and pre_period_estimate is not null)
  ) from fresh),
  'today',(select to_jsonb(d) from daily d order by day desc limit 1),
  'wellbeing_users_7d',(select count(distinct user_id) from wellbeing where log_date>=(now() at time zone 'Asia/Riyadh')::date-6),
  'wellbeing_users_30d',(select count(distinct user_id) from wellbeing),
  'trend',(select jsonb_agg(to_jsonb(d) order by day) from daily d)
 );
$$;
revoke all on function niswah_admin.audience_data() from public,anon,authenticated;
-- Preserve the operations facade and all its existing guards/actions.
alter function public.niswah_admin_api(text,jsonb) rename to operations_api;
alter function public.operations_api(text,jsonb) set schema niswah_admin;
revoke all on function niswah_admin.operations_api(text,jsonb) from public,anon,authenticated;
create function public.niswah_admin_api(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare info jsonb;
begin
 if p_action='list' and p_input->>'section'='analytics' then
  info:=niswah_admin.niswah_admin_api('session');
  if auth.jwt()->>'aal' is distinct from 'aal2' or info->>'role' is distinct from 'owner' then
   raise exception 'Permission denied' using errcode='42501';
  end if;
  insert into niswah_admin.audit(actor_id,action) values(auth.uid(),'read.analytics');
  return jsonb_build_object('data',niswah_admin.audience_data());
 end if;
 return niswah_admin.operations_api(p_action,p_input);
end $$;
revoke all on function public.niswah_admin_api(text,jsonb) from public,anon;
grant execute on function public.niswah_admin_api(text,jsonb) to authenticated;
commit;

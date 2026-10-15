-- Self-reported demographic answers. No default: missing is not "not married".
-- Account-owned data; never used for authorization or inferred from health data.
begin;
create table public.user_demographics (
 user_id uuid primary key references auth.users(id) on delete cascade,
 is_married boolean not null,
 updated_at timestamptz not null default now()
);
alter table public.user_demographics enable row level security;
revoke all on public.user_demographics from public,anon,authenticated;
grant select,insert,update on public.user_demographics to authenticated;
create policy demographics_select_own on public.user_demographics for select to authenticated using ((select auth.uid())=user_id);
create policy demographics_insert_own on public.user_demographics for insert to authenticated with check ((select auth.uid())=user_id);
create policy demographics_update_own on public.user_demographics for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create trigger demographics_updated_at before update on public.user_demographics for each row execute function public.set_updated_at();

-- Private aggregate helper. It cannot be called directly through the Data API.
create function niswah_admin.user_statistics() returns jsonb language sql stable set search_path='' as $$
 with accounts as (
  select a.id,a.created_at,a.last_sign_in_at,
    (a.email_confirmed_at is not null or a.phone_confirmed_at is not null) as verified,
    coalesce(u.onboarding_completed,false) as onboarded,u.language,u.birth_year,d.is_married,
    case when u.birth_year between 1900 and extract(year from now() at time zone 'Asia/Riyadh')
         then extract(year from now() at time zone 'Asia/Riyadh')::integer-u.birth_year else null end as approximate_age
  from auth.users a left join public.users u on u.id=a.id left join public.user_demographics d on d.user_id=a.id
  where a.is_anonymous is not true
 )
 select jsonb_build_object(
  'total',count(*),
  'new_today',count(*) filter(where created_at >= date_trunc('day',now() at time zone 'Asia/Riyadh') at time zone 'Asia/Riyadh'),
  'new_7d',count(*) filter(where created_at>=now()-interval '7 days'),
  'new_30d',count(*) filter(where created_at>=now()-interval '30 days'),
  'verified',count(*) filter(where verified),
  'unverified',count(*) filter(where not verified),
  'onboarded',count(*) filter(where onboarded),
  'incomplete',count(*) filter(where not onboarded),
  'signed_in_7d',count(*) filter(where last_sign_in_at>=now()-interval '7 days'),
  'signed_in_30d',count(*) filter(where last_sign_in_at>=now()-interval '30 days'),
  'marital',jsonb_build_object(
    'married',count(*) filter(where is_married is true),
    'not_married',count(*) filter(where is_married is false),
    'unknown',count(*) filter(where is_married is null)),
  'age',jsonb_build_object(
    'under_18',count(*) filter(where approximate_age<18),
    '18_24',count(*) filter(where approximate_age between 18 and 24),
    '25_34',count(*) filter(where approximate_age between 25 and 34),
    '35_44',count(*) filter(where approximate_age between 35 and 44),
    '45_plus',count(*) filter(where approximate_age>=45),
    'unknown',count(*) filter(where approximate_age is null)),
  'language',jsonb_build_object(
    'ar',count(*) filter(where language='ar'),
    'en',count(*) filter(where language='en'),
    'unknown',count(*) filter(where language is null or language not in ('ar','en')))
 ) from accounts;
$$;
revoke all on function niswah_admin.user_statistics() from public,anon,authenticated;

-- Preserve the tested authorization boundary in the private schema; the public
-- facade delegates first, then attaches owner-only demographic aggregates.
alter function public.niswah_admin_api(text,jsonb) set schema niswah_admin;
revoke all on function niswah_admin.niswah_admin_api(text,jsonb) from public,anon,authenticated;
create function public.niswah_admin_api(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; statistics jsonb;
begin
 result:=niswah_admin.niswah_admin_api(p_action,p_input);
 if p_action='list' and coalesce(p_input->>'section','overview')='overview' then
  statistics:=niswah_admin.user_statistics();
  -- All headline counts use the same non-anonymous auth-account population.
  result:=jsonb_set(result,'{data,users}',statistics->'total');
  result:=jsonb_set(result,'{data,new_users_7d}',statistics->'new_7d');
  result:=jsonb_set(result,'{data,onboarded}',statistics->'onboarded');
  if exists(select 1 from niswah_admin.staff where user_id=auth.uid() and role='owner' and active) then
   result:=jsonb_set(result,'{data,statistics}',statistics);
  end if;
 end if;
 return result;
end $$;
revoke all on function public.niswah_admin_api(text,jsonb) from public,anon;
grant execute on function public.niswah_admin_api(text,jsonb) to authenticated;
comment on function public.niswah_admin_api is 'Delegates to private staff/live-session/AAL2 guard; demographic aggregates are owner-only. No individual health or marital data returned.';
commit;

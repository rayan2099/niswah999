-- Screenshot check-in fields: full score distributions and note participation.
-- Preserve existing owner/session/MFA facade; never return note content.
begin;
alter function niswah_admin.audience_data() rename to audience_summary_data;
create function niswah_admin.audience_data() returns jsonb language sql stable set search_path='' as $$
 with reports as (
  select w.mood,w.energy,w.sleep,
    nullif(btrim(w.notes),'') is not null as has_note
  from public.wellbeing_logs w join auth.users a on a.id=w.user_id
  where a.is_anonymous is not true and w.log_date=(now() at time zone 'Asia/Riyadh')::date
 ), ratings as (
  select key,score,count(*) as users from reports r
  cross join lateral (values ('mood',r.mood),('energy',r.energy),('sleep',r.sleep)) v(key,score)
  where score between 1 and 5 group by key,score
 ), distributions as (
  select dimension,jsonb_build_object(
   'rows',(select jsonb_agg(jsonb_build_object('score',s.score,'users',coalesce(r.users,0)) order by s.score)
     from generate_series(1,5) s(score) left join ratings r on r.key=dimension and r.score=s.score),
   'unknown',(select count(*) from reports)-(select coalesce(sum(users),0) from ratings where key=dimension)
  ) as distribution from unnest(array['mood','energy','sleep']) d(dimension)
 )
 select niswah_admin.audience_summary_data() || jsonb_build_object('checkin_details',jsonb_build_object(
   'ratings',(select jsonb_object_agg(dimension,distribution) from distributions),
   'with_notes',(select count(*) from reports where has_note),
   'without_notes',(select count(*) from reports where not has_note)
 ));
$$;
revoke all on function niswah_admin.audience_summary_data() from public,anon,authenticated;
revoke all on function niswah_admin.audience_data() from public,anon,authenticated;
commit;

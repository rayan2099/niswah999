-- Run on staging. All synthetic users, responses, and audit writes roll back.
begin;
create temporary table admin_stats_before as select niswah_admin.user_statistics() as stats;
grant select on admin_stats_before to authenticated;
insert into auth.users(id,email,email_confirmed_at,is_anonymous,last_sign_in_at) values
 ('b1000000-0000-0000-0000-000000000001','stats-owner@invalid.example',now(),false,now()),
 ('b1000000-0000-0000-0000-000000000002','stats-operator@invalid.example',null,false,null),
 ('b1000000-0000-0000-0000-000000000003','stats-no@invalid.example',now(),false,null),
 ('b1000000-0000-0000-0000-000000000004','stats-unknown@invalid.example',null,false,null),
 ('b1000000-0000-0000-0000-000000000005',null,null,true,null);
update auth.users set created_at=now() where id::text like 'b1000000-0000-0000-0000-%';
insert into auth.sessions(id,user_id,aal) values
 ('b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','aal2'),
 ('b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002','aal2'),
 ('b1000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000003','aal2');
insert into niswah_admin.staff(user_id,role) values
 ('b1000000-0000-0000-0000-000000000001','owner'),
 ('b1000000-0000-0000-0000-000000000002','operator');
update public.users set birth_year=extract(year from now() at time zone 'Asia/Riyadh')::int-25,language='en',onboarding_completed=true
 where id='b1000000-0000-0000-0000-000000000001';
update public.users set birth_year=null,language='ar',onboarding_completed=false
 where id in ('b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000004');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","session_id":"b1000000-0000-0000-0000-000000000001"}',true);
insert into public.user_demographics(user_id,is_married) values('b1000000-0000-0000-0000-000000000001',true);
do $$ declare denied boolean:=false;begin
 begin insert into public.user_demographics(user_id,is_married) values('b1000000-0000-0000-0000-000000000004',false);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: wrote another account answer';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2","session_id":"b1000000-0000-0000-0000-000000000003"}',true);
insert into public.user_demographics(user_id,is_married) values('b1000000-0000-0000-0000-000000000003',false);
do $$ begin
 if (select count(*) from public.user_demographics)<>1 then raise exception 'FAIL: demographic rows not private';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","session_id":"b1000000-0000-0000-0000-000000000001"}',true);
do $$
declare before jsonb; overview jsonb; s jsonb; sum_value bigint;
begin
 select stats into before from admin_stats_before;
 overview:=public.niswah_admin_api('list','{"section":"overview"}')->'data';s:=overview->'statistics';
 if (s->>'total')::int<>(before->>'total')::int+4 then raise exception 'FAIL: anonymous excluded';end if;
 if (s#>>'{marital,married}')::int<>(before#>>'{marital,married}')::int+1 then raise exception 'FAIL: married count';end if;
 if (s#>>'{marital,not_married}')::int<>(before#>>'{marital,not_married}')::int+1 then raise exception 'FAIL: explicit false missing';end if;
 if (s#>>'{marital,unknown}')::int<>(before#>>'{marital,unknown}')::int+2 then raise exception 'FAIL: unknown counted as no';end if;
 if (s#>>'{age,25_34}')::int<>(before#>>'{age,25_34}')::int+1 then raise exception 'FAIL: age boundaries';end if;
 if (s#>>'{age,unknown}')::int<>(before#>>'{age,unknown}')::int+3 then raise exception 'FAIL: missing age';end if;
 if (s#>>'{language,en}')::int<>(before#>>'{language,en}')::int+1 then raise exception 'FAIL: language count';end if;
 if (s->>'new_today')::int<>(before->>'new_today')::int+4 then raise exception 'FAIL: today count';end if;
 if (s->>'verified')::int<>(before->>'verified')::int+2 then raise exception 'FAIL: verified count';end if;
 if (s->>'signed_in_7d')::int<>(before->>'signed_in_7d')::int+1 then raise exception 'FAIL: sign-in count';end if;
 foreach sum_value in array array[
  (select sum(value::text::bigint) from jsonb_each(s->'marital')),
  (select sum(value::text::bigint) from jsonb_each(s->'age')),
  (select sum(value::text::bigint) from jsonb_each(s->'language'))
 ] loop
  if sum_value<>(s->>'total')::bigint then raise exception 'FAIL: denominator mismatch';end if;
 end loop;
 if overview->'users' is distinct from s->'total' or overview->'onboarded' is distinct from s->'onboarded' then raise exception 'FAIL: headline denominator';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2","session_id":"b1000000-0000-0000-0000-000000000002"}',true);
do $$ begin
 if (public.niswah_admin_api('list','{"section":"overview"}')->'data') ? 'statistics' then raise exception 'FAIL: operator sees demographics';end if;
end $$;
rollback;
select 'PASS: explicit yes/no/unknown; private answers; aggregate partitions; anonymous exclusion; owner-only demographics; counts and age bounds' as admin_statistics_tests;

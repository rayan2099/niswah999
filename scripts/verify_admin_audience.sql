-- Staging only. Synthetic fixtures and audit changes are rolled back.
begin;
create temporary table audience_before as select niswah_admin.audience_data() as data;
grant select on audience_before to authenticated;
insert into auth.users(id,email,is_anonymous) values
 ('b3000000-0000-0000-0000-000000000001','audience-owner@invalid.example',false),
 ('b3000000-0000-0000-0000-000000000002','audience-operator@invalid.example',false),
 ('b3000000-0000-0000-0000-000000000003','audience-no-report@invalid.example',false),
 ('b3000000-0000-0000-0000-000000000004',null,true);
insert into auth.sessions(id,user_id,aal) values
 ('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001','aal2'),
 ('b3000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000002','aal2'),
 ('b3000000-0000-0000-0000-000000000003','b3000000-0000-0000-0000-000000000003','aal2');
insert into niswah_admin.staff(user_id,role) values
 ('b3000000-0000-0000-0000-000000000001','owner'),
 ('b3000000-0000-0000-0000-000000000002','operator');
update public.users set madhhab_selection_state='selected',madhhab='HANAFI',prayer_country='SA' where id='b3000000-0000-0000-0000-000000000001';
update public.users set madhhab_selection_state='unknown',madhhab=null,prayer_country=null where id='b3000000-0000-0000-0000-000000000002';
update public.users set madhhab_selection_state='unset',madhhab=null,prayer_country=null where id='b3000000-0000-0000-0000-000000000003';
insert into public.wellbeing_logs(user_id,log_date,mood,energy,sleep,sleepy,notes) values
 ('b3000000-0000-0000-0000-000000000001',(now() at time zone 'Asia/Riyadh')::date,5,2,1,true,'SYNTHETIC_PRIVATE_NOTE'),
 ('b3000000-0000-0000-0000-000000000002',(now() at time zone 'Asia/Riyadh')::date,1,5,5,null,'SYNTHETIC_PRIVATE_NOTE'),
 ('b3000000-0000-0000-0000-000000000001',(now() at time zone 'Asia/Riyadh')::date-1,3,3,3,false,null),
 ('b3000000-0000-0000-0000-000000000004',(now() at time zone 'Asia/Riyadh')::date,5,5,5,true,null);
insert into public.cycle_analytics_snapshots(user_id,fiqh_state,bleeding,ovulation_estimate,pre_period_estimate,received_at) values
 ('b3000000-0000-0000-0000-000000000002','tahara',false,false,true,now()-interval '25 hours'),
 ('b3000000-0000-0000-0000-000000000004','tahara',false,true,false,now());
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b3000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","session_id":"b3000000-0000-0000-0000-000000000001"}',true);
select public.record_cycle_analytics('{"fiqh_state":"haid","bleeding":true,"ovulation_estimate":null,"pre_period_estimate":null}');
do $$ declare denied boolean:=false; begin
 begin perform public.record_cycle_analytics('{"fiqh_state":"tahara","bleeding":true}'); exception when invalid_parameter_value then denied:=true; end;
 if not denied then raise exception 'FAIL contradictory observation accepted';end if;
 denied:=false;
 begin perform public.record_cycle_analytics('{"fiqh_state":"unknown","notes":"private"}'); exception when invalid_parameter_value then denied:=true; end;
 if not denied then raise exception 'FAIL extra payload keys accepted';end if;
 denied:=false;
 begin perform public.record_cycle_analytics('{"fiqh_state":"unknown","received_at":"2099-01-01"}'); exception when invalid_parameter_value then denied:=true; end;
 if not denied then raise exception 'FAIL client timestamp accepted';end if;
 denied:=false;
 begin perform 1 from public.cycle_analytics_snapshots; exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL direct access allowed';end if;
end $$;
do $$ declare b jsonb; d jsonb; sum_value bigint; begin
 select data into b from audience_before;
 d:=public.niswah_admin_api('list','{"section":"analytics"}')->'data';
 if (d->>'total')::int<>(b->>'total')::int+3 then raise exception 'FAIL anonymous account denominator';end if;
 if (d#>>'{today,reports}')::int<>(b#>>'{today,reports}')::int+2 then raise exception 'FAIL wellbeing reports';end if;
 if (d#>>'{today,happy}')::int<>(b#>>'{today,happy}')::int+1 or (d#>>'{today,down}')::int<>(b#>>'{today,down}')::int+1 then raise exception 'FAIL mood categories';end if;
 if (d#>>'{today,sleepy_reports}')::int<>(b#>>'{today,sleepy_reports}')::int+1 then raise exception 'FAIL unanswered sleepy inferred';end if;
 if (d#>>'{wellbeing_users_7d}')::int<>(b#>>'{wellbeing_users_7d}')::int+2 then raise exception 'FAIL user-day double counting';end if;
 if (d#>>'{cycle,fresh}')::int<>(b#>>'{cycle,fresh}')::int+1 or (d#>>'{cycle,missing}')::int<>(b#>>'{cycle,missing}')::int+2 then raise exception 'FAIL stale/anonymous snapshot';end if;
 if (d#>>'{cycle,haid}')::int<>(b#>>'{cycle,haid}')::int+1 or (d#>>'{cycle,tahara}')::int<>(b#>>'{cycle,tahara}')::int then raise exception 'FAIL made up purity';end if;
 if (d#>>'{cycle,prediction_coverage}')::int<>(b#>>'{cycle,prediction_coverage}')::int then raise exception 'FAIL unknown prediction counted';end if;
 if (d#>>'{madhhab,hanafi}')::int<>(b#>>'{madhhab,hanafi}')::int+1 or (d#>>'{madhhab,unknown}')::int<>(b#>>'{madhhab,unknown}')::int+1 or (d#>>'{madhhab,unset}')::int<>(b#>>'{madhhab,unset}')::int+1 then raise exception 'FAIL madhhab authority';end if;
 if (d#>>'{checkin_details,with_notes}')::int<>(b#>>'{checkin_details,with_notes}')::int+2 then raise exception 'FAIL note participation';end if;
 if (d#>>'{checkin_details,without_notes}')::int<>(b#>>'{checkin_details,without_notes}')::int then raise exception 'FAIL anonymous/old note counted';end if;
 if (d#>>'{checkin_details,ratings,mood,rows,4,users}')::int<>(b#>>'{checkin_details,ratings,mood,rows,4,users}')::int+1 then raise exception 'FAIL full score distribution';end if;
 if jsonb_array_length(d#>'{checkin_details,ratings,energy,rows}')<>5 then raise exception 'FAIL missing score buckets';end if;
 if (select sum((value->>'users')::int) from jsonb_array_elements(d#>'{checkin_details,ratings,sleep,rows}'))+(d#>>'{checkin_details,ratings,sleep,unknown}')::int<>(d#>>'{today,reports}')::int then raise exception 'FAIL check-in denominator';end if;
 if jsonb_array_length(d->'trend')<>30 then raise exception 'FAIL missing day buckets';end if;
 foreach sum_value in array array[
   (select sum(value::text::bigint) from jsonb_each(d->'madhhab')),
   (d#>>'{cycle,haid}')::bigint+(d#>>'{cycle,tahara}')::bigint+(d#>>'{cycle,needs_advisory}')::bigint+(d#>>'{cycle,madhhab_unresolved}')::bigint+(d#>>'{cycle,unknown}')::bigint,
   (select coalesce(sum((value->>'users')::bigint),0) from jsonb_array_elements(d#>'{countries,rows}'))+(d#>>'{countries,other}')::bigint+(d#>>'{countries,unknown}')::bigint
 ] loop
  if sum_value<>(d->>'total')::bigint then raise exception 'FAIL partition denominator';end if;
 end loop;
 if d::text like '%SYNTHETIC_PRIVATE_NOTE%' or d::text like '%b3000000-%' or d::text like '%invalid.example%' then raise exception 'FAIL identifying content returned';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"b3000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1","session_id":"b3000000-0000-0000-0000-000000000001"}',true);
do $$ declare denied boolean:=false;begin
 begin perform public.niswah_admin_api('list','{"section":"analytics"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL MFA bypass';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"b3000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2","session_id":"b3000000-0000-0000-0000-000000000002"}',true);
do $$ declare denied boolean:=false;begin
 begin perform public.niswah_admin_api('list','{"section":"analytics"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL operator access';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"b3000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2","session_id":"b3000000-0000-0000-0000-000000000003"}',true);
do $$ declare denied boolean:=false;begin
 begin perform public.niswah_admin_api('list','{"section":"analytics"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL nonstaff access';end if;
end $$;
rollback;
select 'PASS: owner-only MFA; private snapshots; unknown/stale/anonymous exclusion; truthful denominators; unique participation; no identifying output' as audience_tests;

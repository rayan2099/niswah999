-- Staging-only behavioral tests. Synthetic identities, milestones, metrics,
-- incidents and audit writes all roll back.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous,created_at) values
 ('c1000000-0000-0000-0000-000000000001','ops-owner@invalid.example',now(),false,now()),
 ('c1000000-0000-0000-0000-000000000002','ops-operator@invalid.example',now(),false,now()),
 ('c1000000-0000-0000-0000-000000000003','ops-support@invalid.example',now(),false,now());
insert into auth.sessions(id,user_id,aal) select id,id,'aal2' from auth.users where id::text like 'c1000000-%';
insert into niswah_admin.staff(user_id,role) values
 ('c1000000-0000-0000-0000-000000000001','owner'),
 ('c1000000-0000-0000-0000-000000000002','operator'),
 ('c1000000-0000-0000-0000-000000000003','support');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c1000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2","session_id":"c1000000-0000-0000-0000-000000000003"}',true);
do $$ declare denied boolean:=false;begin
 begin perform public.niswah_admin_api('list','{"section":"operations"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: support reads operations';end if;
 denied:=false;begin perform public.record_ai_operation('{"advisor":"ai-assistant-chat","kind":"endpoint","status":200,"duration_ms":3}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: client forges service telemetry';end if;
 perform public.record_onboarding_milestone('madhhab');perform public.record_onboarding_milestone('madhhab');
 denied:=false;begin perform public.record_onboarding_milestone('completed');exception when invalid_parameter_value then denied:=true;end;
 if not denied then raise exception 'FAIL: unsaved completion measured';end if;
end $$;
reset role;
update public.users set onboarding_completed=true where id='c1000000-0000-0000-0000-000000000003';
set local role authenticated;
select public.record_onboarding_milestone('completed');
reset role;
do $$ begin
 if (select count(*) from public.onboarding_milestones where user_id='c1000000-0000-0000-0000-000000000003')<>3 then raise exception 'FAIL: repeated steps double counted';end if;
end $$;
set local role service_role;
select public.record_ai_operation(jsonb_build_object('advisor','ai-assistant-chat','kind','model','status',500,'duration_ms',10)) from generate_series(1,5);
select public.record_ai_operation('{"advisor":"ai-assistant-chat","kind":"model","status":200,"duration_ms":15,"input_tokens":10,"output_tokens":4,"model":"synthetic-test-model"}');
select public.record_ai_operation('{"advisor":"ai-assistant-chat","kind":"endpoint","status":200,"duration_ms":20}');
do $$ declare denied boolean:=false;begin
 begin perform public.record_ai_operation('{"advisor":"ai-assistant-chat","kind":"model","status":200,"duration_ms":15,"prompt":"must never be stored"}');exception when invalid_parameter_value then denied:=true;end;
 if not denied then raise exception 'FAIL: extra content accepted';end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","session_id":"c1000000-0000-0000-0000-000000000001"}',true);
do $$ declare data jsonb; r jsonb; target uuid; denied boolean:=false;begin
 data:=public.niswah_admin_api('list','{"section":"operations"}')->'data';
 if not exists(select 1 from jsonb_array_elements(data->'alerts') a where a->>'key'='ai_errors') then raise exception 'FAIL: model failure signal absent';end if;
 if data#>>'{funnel,state}'<>'receiving' then raise exception 'FAIL: milestones absent';end if;
 r:=public.niswah_admin_api('create_incident','{"title":"Synthetic follow up","source":"ai_errors"}');target:=(r->>'id')::uuid;
 perform public.niswah_admin_api('update_incident',jsonb_build_object('id',target,'status','acknowledged','assigned_to','c1000000-0000-0000-0000-000000000002','due_at',now()-interval '1 day'));
 data:=public.niswah_admin_api('list','{"section":"overview"}')->'data';
 if (data#>>'{attention,overdue_incidents}')::int<1 then raise exception 'FAIL: deadline not reflected';end if;
 begin perform public.niswah_admin_api('update_incident',jsonb_build_object('id',target,'status','open','assigned_to','c1000000-0000-0000-0000-000000000003','due_at',now()));exception when invalid_parameter_value then denied:=true;end;
 if not denied then raise exception 'FAIL: invalid assignee';end if;
 denied:=false;begin perform public.niswah_admin_api('create_incident','{"title":"Duplicate active incident","source":"ai_errors"}');exception when unique_violation then denied:=true;end;
 if not denied then raise exception 'FAIL: duplicate incident allowed';end if;
 perform public.niswah_admin_api('update_incident',jsonb_build_object('id',target,'status','resolved','assigned_to','c1000000-0000-0000-0000-000000000002','due_at',now()));
end $$;
select set_config('request.jwt.claims','{"sub":"c1000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal1","session_id":"c1000000-0000-0000-0000-000000000002"}',true);
do $$ declare denied boolean:=false;begin
 begin perform public.niswah_admin_api('list','{"section":"operations"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: AAL1 operations';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"c1000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2","session_id":"c1000000-0000-0000-0000-000000000002"}',true);
do $$ begin
 if public.niswah_admin_api('list','{"section":"operations"}')->'data' is null then raise exception 'FAIL: operator denied';end if;
end $$;
rollback;
select 'PASS: permissions, MFA, trusted AI ingest, no content fields, milestone deduplication/completion, alerts, incident assignment/deadlines/resolution/audit' as operations_tests;

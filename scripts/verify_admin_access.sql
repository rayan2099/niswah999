-- Staging-only behavior test. Synthetic fixtures and every mutation roll back.
begin;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 ('a1000000-0000-0000-0000-000000000001','admin-test-user@invalid.example',now(),'{}'),
 ('a1000000-0000-0000-0000-000000000002','admin-test-support@invalid.example',now(),'{}'),
 ('a1000000-0000-0000-0000-000000000003','admin-test-owner@invalid.example',now(),'{}'),
 ('a1000000-0000-0000-0000-000000000004','admin-test-editor@invalid.example',now(),'{}'),
 ('a1000000-0000-0000-0000-000000000005','admin-test-medical@invalid.example',now(),'{}'),
 ('a1000000-0000-0000-0000-000000000006','admin-test-fiqh@invalid.example',now(),'{}'),
 ('a1000000-0000-0000-0000-000000000007','admin-test-mod@invalid.example',now(),'{}');
insert into auth.sessions(id,user_id,created_at,updated_at,aal)
 select id,id,now(),now(),'aal2' from auth.users where email like 'admin-test-%@invalid.example';
insert into niswah_admin.staff(user_id,role) values
 ('a1000000-0000-0000-0000-000000000002','support'),
 ('a1000000-0000-0000-0000-000000000003','owner'),
 ('a1000000-0000-0000-0000-000000000004','editor'),
 ('a1000000-0000-0000-0000-000000000005','medical_reviewer'),
 ('a1000000-0000-0000-0000-000000000006','fiqh_reviewer'),
 ('a1000000-0000-0000-0000-000000000007','moderator');
insert into public.community_posts(id,user_id,author_name,title,content,category)
 values('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','Synthetic','Synthetic post','Synthetic moderation content','general');
insert into public.knowledge_items(id,knowledge_key,domain) values
 ('a3000000-0000-0000-0000-000000000001','ADMIN-TEST-HEALTH','HEALTH'),
 ('a3000000-0000-0000-0000-000000000002','ADMIN-TEST-FIQH','FIQH');
insert into public.knowledge_item_versions(id,knowledge_item_id,version,language,canonical_statement,evidence_state,evidence_snapshot_commit)
 values('a4000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',1,'en','Synthetic health statement','PRIMARY_SOURCE_VERIFIED',repeat('a',40)),
 ('a4000000-0000-0000-0000-000000000002','a3000000-0000-0000-0000-000000000002',1,'en','Synthetic fiqh statement','PRIMARY_SOURCE_VERIFIED',repeat('a',40));
-- Even changing the legacy public role cannot confer dashboard authority.
update public.users set role='admin' where id='a1000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare r jsonb; ticket uuid; denied boolean; claim jsonb;
begin
 claim:=jsonb_build_object('sub','a1000000-0000-0000-0000-000000000001','role','authenticated','aal','aal2','session_id','a1000000-0000-0000-0000-000000000001','user_metadata',jsonb_build_object('role','owner'));
 perform set_config('request.jwt.claims',claim::text,true);
 denied:=false; begin perform public.niswah_admin_api('session'); exception when insufficient_privilege then denied:=true; end;
 if not denied then raise exception 'FAIL: legacy/forged role grants admin'; end if;
 claim:=jsonb_build_object('sub','a1000000-0000-0000-0000-000000000002','role','authenticated','aal','aal1','session_id','a1000000-0000-0000-0000-000000000002');
 perform set_config('request.jwt.claims',claim::text,true);
 r:=public.niswah_admin_api('session');
 if r->>'role'<>'support' then raise exception 'FAIL: valid membership not found'; end if;
 denied:=false; begin perform public.niswah_admin_api('list','{"section":"users"}'); exception when insufficient_privilege then denied:=true; end;
 if not denied then raise exception 'FAIL: AAL1 reads admin data'; end if;
 perform set_config('request.jwt.claims',(claim||'{"aal":"aal2"}')::text,true);
 r:=public.niswah_admin_api('list','{"section":"users","query":"admin-test-user@invalid.example"}');
 if jsonb_array_length(r->'data')<>1 or (r->'data'->0) ?| array['pregnant','conditions','madhhab','avg_cycle_length','raw_user_meta_data'] then raise exception 'FAIL: user projection'; end if;
 denied:=false; begin perform public.niswah_admin_api('list','{"section":"community"}'); exception when insufficient_privilege then denied:=true; end;
 if not denied then raise exception 'FAIL: support reads community'; end if;
 r:=public.niswah_admin_api('create_ticket','{"subject":"Synthetic support request"}'); ticket:=(r->>'id')::uuid;
 perform public.niswah_admin_api('update_ticket',jsonb_build_object('id',ticket,'status','resolved'));
 perform set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2","session_id":"a1000000-0000-0000-0000-000000000003"}',true);
 denied:=false;begin perform public.niswah_admin_api('review','{"id":"a4000000-0000-0000-0000-000000000001","decision":"approved","note":"Synthetic owner approval"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: owner claims reviewer authority'; end if;
 denied:=false;begin perform public.niswah_admin_api('set_staff','{"email":"admin-test-owner@invalid.example","role":"support","active":true}');exception when raise_exception then denied:=true;end;
 if not denied then raise exception 'FAIL: removed last owner'; end if;
 perform set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000005","role":"authenticated","aal":"aal2","session_id":"a1000000-0000-0000-0000-000000000005"}',true);
 denied:=false;begin perform public.niswah_admin_api('review','{"id":"a4000000-0000-0000-0000-000000000002","decision":"approved","note":"Synthetic cross domain approval"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: cross domain review'; end if;
 perform public.niswah_admin_api('review','{"id":"a4000000-0000-0000-0000-000000000001","decision":"approved","note":"Synthetic qualified approval"}');
 perform set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000007","role":"authenticated","aal":"aal2","session_id":"a1000000-0000-0000-0000-000000000007"}',true);
 perform public.niswah_admin_api('moderate','{"id":"a2000000-0000-0000-0000-000000000001","kind":"post","hidden":true,"note":"Synthetic moderation reason"}');
 if exists(select 1 from public.community_posts where id='a2000000-0000-0000-0000-000000000001') then raise exception 'FAIL: hidden post remains visible';end if;
 perform set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","session_id":"a1000000-0000-0000-0000-000000000001"}',true);
 denied:=false;begin insert into public.community_posts(user_id,author_name,title,content,category,is_hidden) values('a1000000-0000-0000-0000-000000000001','Synthetic','Synthetic','Synthetic contents','general',true);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: user controls moderation flag';end if;
end $$;
reset role;
do $$ begin
 if (select production_eligible from public.knowledge_item_versions where id='a4000000-0000-0000-0000-000000000001') then raise exception 'FAIL: approval changes eligibility';end if;
 if not exists(select 1 from niswah_admin.audit where action='moderate' and actor_id='a1000000-0000-0000-0000-000000000007') then raise exception 'FAIL: missing audit';end if;
end $$;
update niswah_admin.staff set active=false where user_id='a1000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2","session_id":"a1000000-0000-0000-0000-000000000002"}',true);
do $$ declare denied boolean:=false; begin
 begin perform public.niswah_admin_api('session');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: inactive staff retained access';end if;
end $$;
reset role;
delete from auth.sessions where id='a1000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2","session_id":"a1000000-0000-0000-0000-000000000003"}',true);
do $$ declare denied boolean:=false; begin
 begin perform public.niswah_admin_api('list','{"section":"overview"}');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL: revoked session retained access';end if;
end $$;
rollback;
select 'PASS: nonstaff, forged role, MFA, minimal projection, cross-role, tickets, last owner, qualified review, moderation, audit, revocation' as admin_access_tests;

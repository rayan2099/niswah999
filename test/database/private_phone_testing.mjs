// Run with Node and @electric-sql/pglite installed; no live services involved.
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite({extensions:{pgcrypto}});
await db.exec(`create role anon; create role authenticated; create schema auth; create schema extensions;
create extension pgcrypto with schema extensions;
create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz, is_anonymous boolean, phone text);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.test.uid',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('iss',current_setting('request.test.iss',true))$$;
grant usage on schema auth to authenticated; grant execute on function auth.uid(), auth.jwt() to authenticated;`);
await db.exec(fs.readFileSync(new URL('../../supabase/migrations/20261030210000_private_phone_testing.sql', import.meta.url),'utf8'));
const A='11111111-1111-4111-8111-111111111111', B='22222222-2222-4222-8222-222222222222';
const staging='https://ovgvevzrcefloitgcsia.supabase.co/auth/v1';
await db.query('insert into auth.users values($1,$2,now(),false,null),($3,$4,null,false,null)',[A,'a@example.test',B,'b@example.test']);
let count=0;
async function check(name,fn){await fn();count++;console.log(`PASS ${name}`);}
async function user(id,iss=staging){await db.exec('reset role');await db.query("select set_config('request.test.uid',$1,false),set_config('request.test.iss',$2,false)",[id,iss]);await db.exec('set role authenticated');}
async function admin(sql,params=[]){await db.exec('reset role');return db.query(sql,params);}
async function start(phone='+966500000001'){return (await db.query('select public.start_private_phone_test($1) s',[phone])).rows[0].s;}
async function finish(code){return (await db.query('select public.complete_private_phone_test($1) s',[code])).rows[0].s;}
await user(A);
await check('default denies unapproved tester',async()=>assert.equal((await start()).error,'not_allowed'));
await admin('insert into public.private_phone_test_access values($1,true),($2,true)',[A,B]);
await user(B);
await check('unconfirmed email denied',async()=>assert.equal((await start()).error,'not_allowed'));
await user(A,'https://jkmjobvxfrmuwafczvtw.supabase.co/auth/v1');
await check('production issuer denied even if allowlisted',async()=>assert.equal((await start()).error,'not_allowed'));
await user(A);
await check('invalid phone rejected',async()=>assert.equal((await start('0500000001')).error,'invalid_phone'));
let issued;
await check('approved tester gets six-digit test code',async()=>{issued=await start();assert.match(issued.test_code,/^[0-9]{6}$/);assert.equal(issued.phone_verified,false);});
await check('resend cooldown enforced',async()=>assert.equal((await start()).error,'cooldown'));
await check('direct state read denied',async()=>assert.rejects(db.query('select * from public.private_phone_test_state'),/permission denied/));
await check('direct allowlist mutation denied',async()=>assert.rejects(db.query('update public.private_phone_test_access set enabled=true'),/permission denied/));
await check('wrong code rejected',async()=>assert.equal((await finish('bad')).error,'invalid_code'));
await check('correct code completes without verification',async()=>{const r=await finish(issued.test_code);assert.equal(r.completed,true);assert.equal(r.phone_verified,false);});
await check('consumed code cannot replay',async()=>assert.equal((await finish(issued.test_code)).error,'expired'));
await admin('update auth.users set email_confirmed_at=now() where id=$1',[B]);await user(B);
await check('other account cannot consume A code',async()=>assert.equal((await finish(issued.test_code)).error,'expired'));
await admin("update public.private_phone_test_state set issued_at=now()-interval '61 seconds'");await user(A);issued=await start();
await check('five attempts lock code',async()=>{for(let i=0;i<5;i++)assert.equal((await finish('bad')).error,'invalid_code');assert.equal((await finish(issued.test_code)).error,'expired');});
await admin("update public.private_phone_test_state set issued_at=now()-interval '61 seconds'");await user(A);issued=await start();
await admin("update public.private_phone_test_state set expires_at=now()-interval '1 second'");await user(A);
await check('expired code denied',async()=>assert.equal((await finish(issued.test_code)).error,'expired'));
await admin('update public.private_phone_test_access set enabled=false where user_id=$1',[A]);await user(A);
await check('revocation blocks in-flight completion',async()=>assert.equal((await finish(issued.test_code)).error,'not_allowed'));
await db.exec('reset role;set role anon');
await check('anonymous RPC denied',async()=>assert.rejects(db.query("select public.start_private_phone_test('+966500000001')"),/permission denied/));
await admin('select 1');
await check('auth phone never modified',async()=>assert.ok((await db.query('select phone from auth.users')).rows.every(x=>x.phone===null)));
await check('unverified invariant enforced',async()=>assert.rejects(db.query('update public.private_phone_test_state set phone_verified=true'),/check constraint/));
await admin('delete from auth.users');
await check('account deletion cascades test data and access',async()=>{for(const table of ['private_phone_test_access','private_phone_test_state'])assert.equal((await db.query(`select count(*)::int n from public.${table}`)).rows[0].n,0);});
await db.close();console.log(`${count} database checks passed`);

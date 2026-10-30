import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create table auth.users(id uuid primary key, phone text);
`);
await db.exec(fs.readFileSync(new URL('../../supabase/migrations/20261030204723_early_phone_access.sql',import.meta.url),'utf8'));
const hash=n=>n.toString(16).padStart(64,'0');
const phone=n=>'9665'+n.toString().padStart(8,'0');
async function reserve(n){return (await db.query('select public.reserve_early_phone($1,$2) as r',[hash(n),phone(n)])).rows[0].r;}
let count=0;
async function check(name,fn){await fn();count++;console.log('PASS '+name);}
await db.exec('set role service_role');
await check('registration off by default',async()=>assert.equal((await reserve(1)).error,'closed'));
await db.exec('reset role;update public.early_phone_capacity set enabled=true;set role service_role');
await check('invalid hash cannot allocate',async()=>assert.equal((await db.query("select public.reserve_early_phone('bad','966500000001') r")).rows[0].r.error,'invalid_request'));
await check('first allocation stays unverified',async()=>assert.equal((await reserve(1)).phone_verified,false));
await check('retry does not consume capacity or change alias',async()=>{const a=await reserve(1),b=await reserve(1);assert.equal(a.alias,b.alias);assert.equal((await db.query('select allocated from public.early_phone_capacity')).rows[0].allocated,1);});
await db.exec("reset role;insert into auth.users values('11111111-1111-4111-8111-111111111111','966500009999');set role service_role");
await check('existing real phone cannot be claimed',async()=>assert.equal((await reserve(9999)).error,'unavailable'));
await check('exactly 1000 reservations allowed',async()=>{for(let n=2;n<=1000;n++)assert.ok((await reserve(n)).alias);assert.equal((await reserve(1001)).error,'full');});
await check('existing account reservation usable at full capacity',async()=>assert.ok((await reserve(1)).alias));
await check('unverified invariant cannot be changed',async()=>assert.rejects(db.query('update public.early_phone_accounts set phone_verified=true'),/check constraint/));
await check('ten attempts then rate limited',async()=>{for(let n=0;n<10;n++)assert.equal((await db.query('select public.allow_early_phone_attempt($1) ok',[hash(1)])).rows[0].ok,true);assert.equal((await db.query('select public.allow_early_phone_attempt($1) ok',[hash(1)])).rows[0].ok,false);});
await db.exec("update public.early_phone_attempts set window_start=now()-interval '16 minutes'");
await check('attempt window expires',async()=>assert.equal((await db.query('select public.allow_early_phone_attempt($1) ok',[hash(1)])).rows[0].ok,true));
for(const role of ['anon','authenticated']) {
 await db.exec('reset role;set role '+role);
 await check(role+' cannot allocate or inspect state',async()=>{await assert.rejects(reserve(1),/permission denied/);await assert.rejects(db.query('select * from public.early_phone_accounts'),/permission denied/);await assert.rejects(db.query('update public.early_phone_capacity set enabled=true'),/permission denied/);});
}
await db.exec('reset role');
await db.query("update public.early_phone_accounts set user_id='11111111-1111-4111-8111-111111111111' where identifier_hash=$1",[hash(1)]);
await db.exec('delete from auth.users');
await check('deletion removes mapping and attempt state',async()=>{assert.equal((await db.query('select count(*) n from public.early_phone_accounts where identifier_hash=$1',[hash(1)])).rows[0].n,0);assert.equal((await db.query('select count(*) n from public.early_phone_attempts where identifier_hash=$1',[hash(1)])).rows[0].n,0);});
await db.exec('set role service_role');
await check('deletion cannot reopen lifetime capacity',async()=>assert.equal((await reserve(1001)).error,'full'));
await db.exec('update public.early_phone_capacity set enabled=false');
await check('closing enrollment leaves existing slots intact',async()=>assert.ok((await reserve(2)).alias));
console.log(`${count} database checks passed. No live services used.`);
await db.close();

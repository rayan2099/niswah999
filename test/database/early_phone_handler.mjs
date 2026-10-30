import assert from 'node:assert/strict';
import {makeHandler,normalizePhone,hashPhone} from '../../supabase/functions/early-phone-access/handler.js';
const env={SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'secret-for-test',EARLY_PHONE_HMAC_KEY:'synthetic-hmac-key-for-testing-only-1234'};
const alias='11111111-1111-4111-8111-111111111111',id='22222222-2222-4222-8222-222222222222';
const session={refresh_token:'synthetic-refresh',access_token:'synthetic-access',user:{id}};
let count=0;
async function check(name,fn){await fn();count++;console.log('PASS '+name);}
const input={action:'signup',phone:'+966500000001',password:'correct-password'};
const request=(body=input,method='POST')=>new Request('https://example.test',{method,...(method==='POST'?{body:JSON.stringify(body)}:{})});
function harness(opts={}) {
 const calls=[];
 const transport=async(url,init)=>{
  const body=init.body?JSON.parse(init.body):undefined;calls.push({url,method:init.method,body});
  let data=null,status=200;
  if(url.includes('allow_early_phone_attempt'))data=opts.limited?false:true;
  else if(url.includes('reserve_early_phone'))data=opts.reserve??{alias,user_id:null,phone_verified:false};
  else if(url.includes('/rest/v1/early_phone_accounts')){
   if(init.method==='PATCH'){status=204;}else data=opts.slot?[opts.slot]:[];
  } else if(url.endsWith('/admin/users')){status=opts.createStatus??200;data={id};}
  else if(url.includes('/token?')){status=opts.badPassword?400:200;data=opts.badPassword?{error:'invalid_grant'}:session;}
  else throw Error('unexpected request '+url);
  return new Response(status===204?null:JSON.stringify(data),{status});
 };
 return {calls,handler:makeHandler(env,transport)};
}
await check('Saudi normalization including Arabic digits',()=>{assert.equal(normalizePhone('+966 ٠٥٠ ٠٠٠ ٠٠٠١'),'966500000001');assert.equal(normalizePhone('00966500000001'),'966500000001');assert.equal(normalizePhone('bad'),null);});
await check('HMAC stable, canonical and not raw phone',async()=>{assert.equal(await hashPhone(normalizePhone('+966 500000001'),env.EARLY_PHONE_HMAC_KEY),await hashPhone('966500000001',env.EARLY_PHONE_HMAC_KEY));assert.notEqual(await hashPhone('966500000001',env.EARLY_PHONE_HMAC_KEY),await hashPhone('966500000001','different-key'));});
await check('missing configuration fails closed before network',async()=>{const h=makeHandler({},()=>{throw Error('must not call');});assert.equal((await h(request())).status,503);});
await check('unsupported HTTP method rejected',async()=>assert.equal((await harness().handler(request(null,'GET'))).status,405));
await check('preflight does not allocate',async()=>{const h=harness();assert.equal((await h.handler(request(null,'OPTIONS'))).status,204);assert.equal(h.calls.length,0);});
await check('short password and invalid phone rejected',async()=>{for(const body of [{...input,password:'short'},{...input,phone:'x'}]){const h=harness();assert.equal((await h.handler(request(body))).status,400);assert.equal(h.calls.length,0);}});
await check('successful signup returns session, no SMS and never confirms supplied phone',async()=>{const h=harness();const r=await h.handler(request());assert.equal(r.status,200);assert.deepEqual(await r.json(),session);const create=h.calls.find(x=>x.url.endsWith('/admin/users'));assert.equal(create.body.phone,undefined);assert.equal(create.body.phone_confirm,undefined);assert.equal(create.body.app_metadata.phone_verified,false);assert.equal(create.body.app_metadata.email_verified,false);assert.match(create.body.email,/@early\.niswah\.invalid$/);assert.ok(h.calls.every(x=>!x.url.includes('otp')));assert.equal(h.calls.filter(x=>x.method==='PATCH').length,1);assert.equal(r.headers.get('cache-control'),'no-store');});
await check('existing early account logs in after capacity closes without allocation',async()=>{const h=harness({slot:{alias,user_id:id}});assert.equal((await h.handler(request({...input,action:'login'}))).status,200);assert.ok(h.calls.every(x=>!x.url.includes('reserve_early_phone')&&!x.url.includes('/admin/users')));});
await check('signup retry cannot overwrite existing password',async()=>{const h=harness({slot:{alias,user_id:id},badPassword:true});assert.equal((await h.handler(request())).status,401);assert.ok(h.calls.every(x=>!x.url.includes('/admin/users')&&x.method!=='PATCH'));});
await check('duplicate in-flight creation does not reset password',async()=>{const h=harness({slot:{alias,user_id:null},createStatus:422,badPassword:true});assert.equal((await h.handler(request())).status,401);assert.ok(h.calls.every(x=>x.method!=='PUT'&&x.method!=='PATCH'));});
await check('retry recovers session after earlier create succeeded',async()=>{const h=harness({slot:{alias,user_id:null},createStatus:422});assert.equal((await h.handler(request())).status,200);});
await check('full cohort blocks new signup before Auth create',async()=>{const h=harness({reserve:{error:'full'}});const r=await h.handler(request());assert.equal(r.status,409);assert.equal((await r.json()).error,'cohort_full');assert.ok(h.calls.every(x=>!x.url.includes('/admin/users')));});
await check('default closed blocks signup',async()=>{const h=harness({reserve:{error:'closed'}});assert.equal((await h.handler(request())).status,403);});
await check('rate limit happens before lookup or create',async()=>{const h=harness({limited:true});assert.equal((await h.handler(request())).status,429);assert.equal(h.calls.length,1);});
await check('legacy phone login uses password, cannot enroll or link',async()=>{const h=harness();assert.equal((await h.handler(request({...input,action:'login'}))).status,200);const token=h.calls.find(x=>x.url.includes('/token?'));assert.equal(token.body.phone,'966500000001');assert.equal(token.body.password,input.password);assert.ok(h.calls.every(x=>!x.url.includes('/admin/users')&&!x.url.includes('reserve_early_phone')));});
await check('session with different account ID fails closed',async()=>{const h=harness({slot:{alias,user_id:'another-id'}});assert.equal((await h.handler(request({...input,action:'login'}))).status,503);});
await check('provider errors never return a successful session',async()=>{const h=makeHandler(env,()=>{throw Error('synthetic transport failure');});const r=await h(request());assert.equal(r.status,503);assert.equal((await r.json()).refresh_token,undefined);});
await check('unknown recovery and linking actions are rejected',async()=>{for(const action of ['reset','link','verify'])assert.equal((await harness().handler(request({...input,action}))).status,400);});
await check('legacy login still accepts an existing shorter password',async()=>{const h=harness();assert.equal((await h.handler(request({...input,action:'login',password:'legacy'}))).status,200);});
console.log(`${count} handler checks passed. Mock transport only; no live Auth evidence.`);

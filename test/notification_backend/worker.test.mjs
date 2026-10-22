import {test} from 'node:test';
import assert from 'node:assert/strict';
import {messageFor, invalidRegistration, dispatch, secretMatches, batchSize} from '../../supabase/functions/notification-dispatch/worker.ts';
const job={job_id:'j',lease_id:'l',inbox_id:'i',recipient_id:'u',kind:'privateMessage',target_id:'conversation',device_id:'d',token:'secret-device-token',locale:'en'};
test('push contains generic copy, opaque routing and conversation collapse; no private body',()=>{
 const m=messageFor(job).message;
 assert.equal(m.fid,job.token);assert.equal('token' in m,false);
 assert.equal(m.notification.body,'You have a new message in Niswah.');
 assert.equal(m.data.destination,'conversation');assert.equal(m.data.userId,'u');
 assert.equal(m.android.collapse_key,'privateMessage');
 assert.equal(m.android.notification.visibility,'PRIVATE');
 assert.equal(messageFor({...job,locale:'ar'}).message.notification.title,'نِسواه');
 assert.throws(()=>messageFor({...job,kind:'unknown'}));
});
test('only explicit UNREGISTERED response revokes token, not bad payload or provider failure',()=>{
 assert.equal(invalidRegistration(404,{error:{details:[{errorCode:'UNREGISTERED'}]}}),true);
 assert.equal(invalidRegistration(400,{error:{details:[{errorCode:'INVALID_ARGUMENT'}]}}),false);
 assert.equal(invalidRegistration(503,null),false);
});
test('worker authenticates dedicated long secret and rejects missing, short and mismatching values',()=>{
 const key='x'.repeat(64);
 assert.equal(secretMatches(key,key),true);
 assert.equal(secretMatches('',key),false);assert.equal(secretMatches('short','short'),false);
 assert.equal(secretMatches('y'.repeat(64),key),false);
});
test('stale claims are skipped; only accepted sends are recorded accepted',async()=>{
 const finishes=[];let sent=0;
 const result=await dispatch({claim:async()=>[job,{...job,job_id:'stale'},{...job,job_id:'fail'}],
  current:async j=>j.job_id!=='stale',send:async j=>{sent++;return {accepted:j.job_id!=='fail',invalidToken:false};},
  finish:async(j,a,i)=>{finishes.push([j.job_id,a,i]);}});
 assert.deepEqual(result,{claimed:3,accepted:1,skipped:1,failed:1,deferred:0});assert.equal(sent,2);
 assert.ok(finishes.some(f=>f[0]==='stale'&&!f[1]));assert.ok(finishes.some(f=>f[0]==='fail'&&!f[1]));
});
test('provider exception leaves lease retryable and never invents acceptance',async()=>{
 let finished=false;
 const result=await dispatch({claim:async()=>[job],current:async()=>true,
  send:async()=>{throw Error('provider down');},finish:async()=>{finished=true;}});
 assert.equal(result.failed,1);assert.equal(result.accepted,0);assert.equal(finished,false);
});
test('copy names only the activity kind, on the activity channel, and expires on both platforms',()=>{
 const at=Date.UTC(2030,0,1);
 const comment=messageFor({...job,kind:'communityComment',locale:'ar'},at).message;
 assert.equal(comment.notification.body,'تعليق جديد على منشوركِ.');
 assert.equal(messageFor({...job,kind:'communityLike'},at).message.notification.body,'New activity on your post.');
 for (const kind of ['privateMessage','communityComment','communityLike']) {
  const m=messageFor({...job,kind},at).message;
  assert.equal(m.android.notification.channel_id,'niswah_activity');
  assert.equal(m.android.ttl,'3600s');
  assert.equal(m.apns.headers['apns-expiration'],String(at/1000+3600));
  assert.doesNotMatch(JSON.stringify(m.notification),/conversation|secret-device-token/);
 }
});
test('a full batch drains in further rounds; a short batch or the time budget stops claiming',async()=>{
 const batch=n=>Array.from({length:n},(_,i)=>({...job,job_id:'j'+i}));
 const pages=[batch(batchSize),batch(batchSize),batch(3),batch(batchSize)];let claims=0;
 const deps={claim:async()=>pages[claims++]??[],current:async()=>true,
  send:async()=>({accepted:true,invalidToken:false}),finish:async()=>{}};
 const result=await dispatch(deps);
 assert.equal(claims,3);assert.equal(result.claimed,2*batchSize+3);assert.equal(result.accepted,result.claimed);
 let clock=0,rounds=0;
 const timed=await dispatch({...deps,claim:async()=>{rounds++;clock+=30000;return batch(batchSize);}},{now:()=>clock});
 assert.equal(rounds,2);assert.equal(timed.claimed,2*batchSize);
 clock=0;
 const late=await dispatch({...deps,claim:async()=>{clock=60000;return batch(10);}},{now:()=>clock});
 assert.deepEqual([late.claimed,late.accepted,late.deferred],[10,0,10]);
});

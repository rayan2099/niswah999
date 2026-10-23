import {test} from 'node:test';
import assert from 'node:assert/strict';
import {messageFor, invalidRegistration, dispatch, secretMatches} from '../../supabase/functions/notification-dispatch/worker.ts';
const job={job_id:'j',lease_id:'l',inbox_id:'i',recipient_id:'u',kind:'privateMessage',target_id:'conversation',device_id:'d',token:'secret-device-token',locale:'en'};
test('push contains generic copy, opaque routing and conversation collapse; no private body',()=>{
 const m=messageFor(job).message;
 assert.equal(m.fid,job.token);assert.equal('token' in m,false);
 assert.equal(m.notification.body,'You have a new update in Niswah.');
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
 assert.deepEqual(result,{claimed:3,accepted:1,skipped:1,failed:1});assert.equal(sent,2);
 assert.ok(finishes.some(f=>f[0]==='stale'&&!f[1]));assert.ok(finishes.some(f=>f[0]==='fail'&&!f[1]));
});
test('provider exception leaves lease retryable and never invents acceptance',async()=>{
 let finished=false;
 const result=await dispatch({claim:async()=>[job],current:async()=>true,
  send:async()=>{throw Error('provider down');},finish:async()=>{finished=true;}});
 assert.equal(result.failed,1);assert.equal(result.accepted,0);assert.equal(finished,false);
});

import {createClient} from 'npm:@supabase/supabase-js@2.49.1';
import {batchSize, dispatch, invalidRegistration, messageFor, secretMatches} from './worker.ts';

type ServiceAccount = {client_email: string; private_key: string; project_id: string};
let cachedToken: {value: string; expires: number} | undefined;
const encode = (value: Uint8Array) => btoa(String.fromCharCode(...value)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
async function accessToken(account: ServiceAccount) {
  if (cachedToken && cachedToken.expires > Date.now()+60000) return cachedToken.value;
  const issued = Math.floor(Date.now()/1000);
  const enc = (v: unknown) => encode(new TextEncoder().encode(JSON.stringify(v)));
  const unsigned = `${enc({alg:'RS256',typ:'JWT'})}.${enc({iss:account.client_email,
    scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:issued,exp:issued+3600})}`;
  const der = Uint8Array.from(atob(account.private_key.replace(/-----[^-]+-----|\s/g,'')), c=>c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8',der,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(unsigned));
  const result = await fetch('https://oauth2.googleapis.com/token',{method:'POST',
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${unsigned}.${encode(new Uint8Array(signature))}`}),
    signal:AbortSignal.timeout(10000)});
  if (!result.ok) throw new Error('Push provider authentication failed');
  const token = await result.json();
  if (typeof token.access_token !== 'string') throw new Error('Invalid push provider response');
  cachedToken = {value:token.access_token,expires:Date.now()+Math.min(Number(token.expires_in)||300,3600)*1000};
  return cachedToken.value;
}
Deno.serve(async request => {
  const secret = Deno.env.get('NOTIFICATION_WORKER_SECRET') ?? '';
  if (request.method !== 'POST' || !secretMatches(request.headers.get('authorization')?.replace(/^Bearer /,'') ?? '',secret)) {
    return new Response('Unauthorized',{status:401});
  }
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!raw) return new Response('Push provider not configured',{status:503});
  try {
    const account = JSON.parse(raw) as ServiceAccount;
    if (!account.project_id || !/^[a-z0-9-]+$/.test(account.project_id) || !account.client_email || !account.private_key) {
      throw new Error('Invalid push provider configuration');
    }
    // Do not claim work until the provider is configured and authentication succeeds.
    const token = await accessToken(account);
    const db = createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      {auth:{persistSession:false,autoRefreshToken:false}});
    const rpc = async (name: string, args: Record<string,unknown>) => {
      const result = await db.rpc(name,args);
      if (result.error) throw new Error('Notification queue operation failed');
      return result.data;
    };
    await rpc('cleanup_notification_activity',{});
    const counts = await dispatch({
      claim: () => rpc('claim_notification_push',{batch_limit:batchSize}),
      current: job => rpc('confirm_notification_push',{p_job:job.job_id,p_lease:job.lease_id}),
      send: async job => {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,{
          method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
          body:JSON.stringify(messageFor(job)),signal:AbortSignal.timeout(10000)});
        const payload = await response.json().catch(()=>null);
        return {accepted:response.ok,invalidToken:invalidRegistration(response.status,payload)};
      },
      finish: (job,accepted,invalid) => rpc('finish_notification_push',{
        p_job:job.job_id,p_lease:job.lease_id,p_accepted:accepted,p_invalid_token:invalid}).then(()=>{}),
    });
    return Response.json(counts);
  } catch {
    // Never echo device tokens, service-account JSON, user identifiers or provider bodies.
    return new Response('Notification dispatch unavailable',{status:503});
  }
});

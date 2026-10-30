// No credentials, phone numbers, request bodies or sessions are logged.
const headers = {
  'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (status, body) => new Response(JSON.stringify(body), {status, headers});
export function normalizePhone(value) {
  if (typeof value !== 'string') return null;
  const digits = value.replace(/[٠-٩]/g, c => String(c.charCodeAt(0)-1632))
    .replace(/[۰-۹]/g, c => String(c.charCodeAt(0)-1776));
  if (!/^\+?[\d ()-]+$/.test(digits)) return null;
  let phone = digits.replace(/[^0-9]/g, '');
  if (phone.startsWith('00966')) phone = phone.slice(2);
  if (phone.startsWith('96605')) phone = '966'+phone.slice(4);
  return /^[1-9][0-9]{7,14}$/.test(phone) ? phone : null;
}
export async function hashPhone(phone, secret) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    {name:'HMAC',hash:'SHA-256'},false,['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,
    new TextEncoder().encode(phone))), b=>b.toString(16).padStart(2,'0')).join('');
}
export function makeHandler(env, transport=fetch) {
  const url=env.SUPABASE_URL, service=env.SUPABASE_SERVICE_ROLE_KEY;
  const api=async(path, body, method='POST')=>{
    const response=await transport(url+path, {
      method, headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},
      ...(body===undefined?{}:{body:JSON.stringify(body)}), signal:AbortSignal.timeout(15000),
    });
    const data=response.status===204?null:await response.json();
    return {ok:response.ok,data};
  };
  return async req=>{
    if(req.method==='OPTIONS') return new Response(null,{status:204,headers});
    if(req.method!=='POST') return reply(405,{error:'method_not_allowed'});
    if(!url || !service || !env.EARLY_PHONE_HMAC_KEY || env.EARLY_PHONE_HMAC_KEY.length<32)
      return reply(503,{error:'unavailable'});
    try {
      const text=await req.text();
      if(text.length>4096) return reply(400,{error:'invalid_request'});
      const input=JSON.parse(text), phone=normalizePhone(input.phone);
      if(!phone || !['signup','login'].includes(input.action) || typeof input.password!=='string' ||
        input.password.length<(input.action==='signup'?8:1) || input.password.length>128)
        return reply(400,{error:'invalid_request'});
      const hash=await hashPhone(phone,env.EARLY_PHONE_HMAC_KEY);
      const limit=await api('/rest/v1/rpc/allow_early_phone_attempt',{p_hash:hash});
      if(!limit.ok) return reply(503,{error:'unavailable'});
      if(limit.data!==true) return reply(429,{error:'rate_limited'});
      let lookup=await api(`/rest/v1/early_phone_accounts?identifier_hash=eq.${hash}&select=alias,user_id`,undefined,'GET');
      if(!lookup.ok) return reply(503,{error:'unavailable'});
      let slot=lookup.data[0];
      if(!slot && input.action==='signup') {
        const reserved=await api('/rest/v1/rpc/reserve_early_phone',{p_hash:hash,p_phone:phone});
        if(!reserved.ok) return reply(503,{error:'unavailable'});
        if(reserved.data.error) return reply(reserved.data.error==='full'?409:403,
          {error:reserved.data.error==='full'?'cohort_full':'signup_unavailable'});
        slot=reserved.data;
      }
      // Existing real phone accounts still authenticate through GoTrue with their password.
      if(!slot) {
        const login=await api('/auth/v1/token?grant_type=password',{phone,password:input.password});
        return login.ok?reply(200,login.data):reply(401,{error:'invalid_credentials'});
      }
      const email=`${slot.alias}@early.niswah.invalid`;
      if(input.action==='signup' && !slot.user_id) {
        // Internal random alias only: no user-supplied mailbox/phone is confirmed.
        // Duplicate/in-flight creates never update the existing password.
        await api('/auth/v1/admin/users',{
          email,password:input.password,email_confirm:true,
          app_metadata:{auth_method:'early_phone_password',phone_verified:false,email_verified:false},
          user_metadata:{full_name:typeof input.display_name==='string'?input.display_name.slice(0,50):''},
        });
      }
      const login=await api('/auth/v1/token?grant_type=password',{email,password:input.password});
      if(!login.ok) return reply(401,{error:'invalid_credentials'});
      const id=login.data.user?.id;
      if(!id || (slot.user_id && slot.user_id!==id)) return reply(503,{error:'unavailable'});
      if(!slot.user_id) {
        const bound=await api(`/rest/v1/early_phone_accounts?identifier_hash=eq.${hash}&user_id=is.null`,{user_id:id},'PATCH');
        if(!bound.ok) return reply(503,{error:'unavailable'});
      }
      return reply(200,login.data);
    } catch {
      return reply(503,{error:'unavailable'});
    }
  };
}

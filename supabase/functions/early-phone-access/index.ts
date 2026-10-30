import { makeHandler } from './handler.js';
Deno.serve(makeHandler({
  SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  EARLY_PHONE_HMAC_KEY: Deno.env.get('EARLY_PHONE_HMAC_KEY'),
}));

-- Lifetime cap applies to this phone/password cohort, not existing email/SMS users.
create table public.early_phone_capacity (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  allocated integer not null default 0 check (allocated between 0 and 1000)
);
insert into public.early_phone_capacity(singleton) values(true);
create table public.early_phone_accounts (
  identifier_hash text primary key check(identifier_hash ~ '^[0-9a-f]{64}$'),
  alias uuid not null unique default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  phone_verified boolean not null default false check(not phone_verified)
);
create table public.early_phone_attempts (
  identifier_hash text primary key,
  window_start timestamptz not null default now(),
  attempts integer not null default 1
);
alter table public.early_phone_capacity enable row level security;
alter table public.early_phone_accounts enable row level security;
alter table public.early_phone_attempts enable row level security;
revoke all on public.early_phone_capacity, public.early_phone_accounts, public.early_phone_attempts from public, anon, authenticated;
grant all on public.early_phone_capacity, public.early_phone_accounts, public.early_phone_attempts to service_role;

-- Invoker needs only the phone column to protect existing Auth identities.
grant usage on schema auth to service_role;
grant select(phone) on auth.users to service_role;
create index early_phone_attempts_expiry on public.early_phone_attempts(window_start);

-- Service-only pre-auth operation. Never grant this RPC to a client role.
create function public.reserve_early_phone(p_hash text, p_phone text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare slot public.early_phone_accounts; capacity public.early_phone_capacity;
begin
  if p_hash !~ '^[0-9a-f]{64}$' or p_phone !~ '^[1-9][0-9]{7,14}$' then
    return jsonb_build_object('error','invalid_request');
  end if;
  -- All allocations serialize on a single row; duplicates never consume a slot.
  select * into capacity from public.early_phone_capacity where singleton for update;
  if not found then return jsonb_build_object('error','closed'); end if;
  select * into slot from public.early_phone_accounts where identifier_hash=p_hash;
  if found then return to_jsonb(slot); end if;
  if not capacity.enabled then return jsonb_build_object('error','closed'); end if;
  -- Do not claim a number already attached to a real Auth account.
  if exists(select 1 from auth.users where phone=p_phone or phone='+'||p_phone) then
    return jsonb_build_object('error','unavailable');
  end if;
  if capacity.allocated >= 1000 then return jsonb_build_object('error','full'); end if;
  insert into public.early_phone_accounts(identifier_hash) values(p_hash) returning * into slot;
  update public.early_phone_capacity set allocated=allocated+1 where singleton;
  return to_jsonb(slot);
end $$;
revoke all on function public.reserve_early_phone(text,text) from public, anon, authenticated;
grant execute on function public.reserve_early_phone(text,text) to service_role;

create function public.allow_early_phone_attempt(p_hash text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare n integer;
begin
  if p_hash !~ '^[0-9a-f]{64}$' then return false; end if;
  delete from public.early_phone_attempts where window_start < now()-interval '24 hours';
  insert into public.early_phone_attempts(identifier_hash) values(p_hash)
  on conflict(identifier_hash) do update set
    attempts=case when early_phone_attempts.window_start < now()-interval '15 minutes' then 1 else early_phone_attempts.attempts+1 end,
    window_start=case when early_phone_attempts.window_start < now()-interval '15 minutes' then now() else early_phone_attempts.window_start end
  returning attempts into n;
  return n <= 10;
end $$;
revoke all on function public.allow_early_phone_attempt(text) from public, anon, authenticated;
grant execute on function public.allow_early_phone_attempt(text) to service_role;

-- Deletion removes identifier/rate-limit state without reopening a lifetime slot.
create function public.cleanup_early_phone_attempts() returns trigger language plpgsql
security definer set search_path = '' as $$
begin
  delete from public.early_phone_attempts where identifier_hash=old.identifier_hash;
  return old;
end $$;
revoke all on function public.cleanup_early_phone_attempts() from public, anon, authenticated;
create trigger cleanup_early_phone_attempts after delete on public.early_phone_accounts
for each row execute function public.cleanup_early_phone_attempts();

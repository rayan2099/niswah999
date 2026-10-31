-- Private staging rehearsal only. Never changes auth.users.phone or confirmations.
begin;
create table public.private_phone_test_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false
);
create table public.private_phone_test_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  phone_verified boolean not null default false check (phone_verified = false),
  code_hash text,
  expires_at timestamptz,
  issued_at timestamptz not null,
  attempts integer not null default 0 check (attempts between 0 and 5),
  completed_at timestamptz
);
alter table public.private_phone_test_access enable row level security;
alter table public.private_phone_test_state enable row level security;
revoke all on public.private_phone_test_access, public.private_phone_test_state from public, anon, authenticated;

create function public.private_phone_test_allowed() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    auth.jwt()->>'iss' = 'https://ovgvevzrcefloitgcsia.supabase.co/auth/v1'
    and exists (select 1 from public.private_phone_test_access a
      join auth.users u on u.id = a.user_id
      where a.user_id = auth.uid() and a.enabled
        and u.email_confirmed_at is not null and u.email is not null
        and not coalesce(u.is_anonymous, false)), false);
$$;

create function public.start_private_phone_test(p_phone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_code text; v_state public.private_phone_test_state; v_now timestamptz := clock_timestamp();
begin
  if not public.private_phone_test_allowed() then
    return jsonb_build_object('error', 'not_allowed');
  end if;
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('error', 'invalid_phone');
  end if;
  -- Serialize issuance even before the first row exists.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 9021));
  select * into v_state from public.private_phone_test_state where user_id = auth.uid() for update;
  if found and v_state.issued_at > v_now - interval '60 seconds' then
    return jsonb_build_object('error', 'cooldown');
  end if;
  v_code := lpad((('x' || encode(extensions.gen_random_bytes(3), 'hex'))::bit(24)::bigint % 1000000)::text, 6, '0');
  insert into public.private_phone_test_state(user_id, phone, issued_at, code_hash, expires_at)
    values(auth.uid(), p_phone, v_now, encode(extensions.digest(v_code, 'sha256'), 'hex'), v_now + interval '5 minutes')
    on conflict(user_id) do update set phone = excluded.phone, issued_at = excluded.issued_at,
      code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0, completed_at = null;
  return jsonb_build_object('test_code', v_code, 'phone_verified', false);
end;
$$;

create function public.complete_private_phone_test(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_state public.private_phone_test_state;
begin
  if not public.private_phone_test_allowed() then
    return jsonb_build_object('error', 'not_allowed');
  end if;
  select * into v_state from public.private_phone_test_state where user_id = auth.uid() for update;
  if not found or v_state.code_hash is null or v_state.expires_at <= clock_timestamp() or v_state.attempts >= 5 then
    return jsonb_build_object('error', 'expired');
  end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' or encode(extensions.digest(p_code, 'sha256'), 'hex') <> v_state.code_hash then
    update public.private_phone_test_state set attempts = attempts + 1 where user_id = auth.uid();
    return jsonb_build_object('error', 'invalid_code');
  end if;
  update public.private_phone_test_state set completed_at = clock_timestamp(), code_hash = null, expires_at = null where user_id = auth.uid();
  return jsonb_build_object('completed', true, 'phone_verified', false);
end;
$$;
revoke all on function public.private_phone_test_allowed(), public.start_private_phone_test(text), public.complete_private_phone_test(text) from public, anon, authenticated;
grant execute on function public.private_phone_test_allowed(), public.start_private_phone_test(text), public.complete_private_phone_test(text) to authenticated;
commit;

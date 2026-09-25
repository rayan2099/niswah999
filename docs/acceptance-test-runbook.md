# Acceptance-test runbook

How to run the autonomous persona / acceptance suite safely and
reproducibly. Personas create real accounts and write real rows, so the
first rule is that they may **never** run against production.

## The production kill switch

The harness refuses to run unless the backend is explicitly approved for
testing. It looks only at the **host of the effective Supabase URL**
(`SUPABASE_URL`, falling back to `VITE_SUPABASE_URL`). `APP_ENV` is never
consulted — a bundled `.env` says `development` even in a
production-pointed build, so it proves nothing.

| Backend host | Verdict |
|---|---|
| `localhost`, `127.0.0.1`, `::1` | allowed |
| `10.0.2.2` (Android emulator's alias for the host's loopback) | allowed |
| a host in `TestBackendGate.approvedTestHosts` (exact match) | allowed |
| production project host (denylist — wins over every allowlist) | **refused** |
| any other `*.supabase.co/.in/.net` host | **refused** (could be production) |
| empty, missing, malformed, no scheme, non-http(s), URL with userinfo | **refused** |
| lookalikes (`localhost.evil.com`, `127.0.0.1.nip.io`), `0.0.0.0`, any other host | **refused** |

`approvedTestHosts` is **empty by default** and is a version-controlled
constant in `lib/core/config/test_backend_gate.dart`. Approving a hosted
staging project is a reviewed code change (add its exact host, mirror it
in `scripts/assert_test_backend.py`, and add a vector to
`test/fixtures/backend_gate_vectors.json`). There is deliberately **no**
flag, define or environment variable that widens or disables the gate.

### Where it is enforced (defense in depth)

1. **Host, before anything is built** —
   `python3 scripts/assert_test_backend.py [--env-file .env]` exits **3**
   with `BLOCKED` when the backend is not approved. It is the first step
   of `scripts/run_persona_local.sh`, `scripts/run_persona_f_offline.sh`
   and `.github/workflows/acceptance.yml`.
2. **App, before Supabase/Sentry initialize** — a build made with
   `--dart-define=ACCEPTANCE_TEST=true` runs the gate in `main()` right
   after config load. A refusal shows a `BLOCKED: acceptance run refused`
   screen and returns: no Supabase client, no Sentry, no network call, no
   account, no write. Normal (non-acceptance) builds are unaffected.
3. **Persona harness, before any action** — every persona's first line is
   `if (!await h.guardBackend('<id>')) return;`. It refuses (reports a
   `BLOCKED` result, which the verifier fails on) if the build lacks the
   acceptance define or the backend is not approved. `Flows.boot()` and
   `Flows.signUpWithEmail()` additionally throw if the guard was never
   passed, so a persona that forgot it still cannot reach signup.

`ACCEPTANCE_TEST=true` can only make the app **stricter**; a build without
it makes every persona refuse. The gate is fail-closed: an unreadable or
never-loaded environment is a refusal.

Logs and results show only the safe `host[:port]` identifier — never a
key or secret.

### Tests

- `flutter test test/test_backend_gate_test.dart` — Dart classifier.
- `python3 scripts/test_assert_test_backend.py` — host checker (also
  asserts no secret is ever printed).
- Both consume `test/fixtures/backend_gate_vectors.json` so they cannot
  drift. Covered: localhost allowed; approved test backend allowed;
  production refused (incl. mixed case, and even if wrongly allowlisted);
  empty/unknown/malformed refused; production URL with a misleading
  `APP_ENV=development` refused.

## Running a persona locally

1. Provision the disposable backend: `bash scripts/provision_local_test_backend.sh`.
2. Point `.env` at it (`SUPABASE_URL=http://127.0.0.1:54321` + the local anon
   key). **Back up the real `.env` first and restore it afterwards.**
3. `scripts/run_persona_local.sh <simulator-udid> integration_test/pB_first_episode_test.dart`

Never call `flutter drive` for a persona by hand.

## Deterministic notification clock matrix

`scripts/run_notification_clock_matrix.sh [repeats]` runs the notification
continuity suite under seven machine time zones (UTC, +3, +5:30,
+10:30/+11, +14, -8, -11). Every scenario pins the single controlled clock
(`AppClock.now`, which `BleedingEpisodeRepositoryImpl.localToday` and the
notification coordinator both read) across the reminder-lead-time and
day boundaries.

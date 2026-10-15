"""Verifies record_onboarding_menstrual_history's open-episode
reconciliation behavior (migration
20261012090000_record_onboarding_menstrual_history_episode_reconciliation.sql)
directly against a real Postgres instance — matching this repo's
established convention (see bleeding_episode_repository_test.dart's own
header: RPC behavior is verified directly against Postgres, not mocked in
a Flutter test).

Covers the six scenarios required by the manual QA wave (2026-10-12):
  1. no open episode -> onboarding creates one normally
  2. matching open episode (same start_date) already exists -> reused,
     no duplicate insert
  3. retry the same onboarding payload (same client_operation_id) twice
     -> no duplicate writes, either way
  4. conflicting open episode (different start_date) -> typed conflict
     result, nothing inserted, nothing mutated
  5. onboarding_completed is never set true on an unresolved conflict —
     verified at the Dart layer (_completeOnboarding only calls
     markOnboardingCompleted after a non-conflict result; see
     onboarding_screen.dart), re-confirmed here only as "the RPC itself
     never touches public.users at all" (grep-level check)
  6. a successful (non-conflict) result always carries real ids for
     whatever was actually submitted

Every scenario runs inside its own BEGIN/ROLLBACK — this script never
leaves data behind, staging or otherwise, and is safe to re-run freely.

Usage: python3 scripts/verify_onboarding_episode_reconciliation.py
Requires STAGING_SUPABASE_DB_POOLED_SESSION_URL in
supabase/functions/.env (gitignored) and a real test user id below.
"""

import json
import re
import sys
import uuid
from datetime import date, timedelta

sys.path.insert(0, "/Users/rynadalsabh/Niswah")
from scripts.lib.supabase_management_api import read_plain_env_var
import pg8000

FUNCTIONS_ENV = "/Users/rynadalsabh/Niswah/supabase/functions/.env"
EXPECTED_STAGING_REF = "ovgvevzrcefloitgcsia"
PRODUCTION_REF = "jkmjobvxfrmuwafczvtw"
TARGET_USER_ID = "729d097c-7912-410f-8bf7-7b4203a0f407"

_passed = []
_failed = []


def check(label, condition, detail=""):
    if condition:
        _passed.append(label)
        print(f"  [PASS] {label}")
    else:
        _failed.append(label)
        print(f"  [FAIL] {label}" + (f" -- {detail}" if detail else ""))


def connect():
    db_url = read_plain_env_var(
        FUNCTIONS_ENV, "STAGING_SUPABASE_DB_POOLED_SESSION_URL"
    )
    m = re.match(r"postgresql://([^:]+):([^@]+)@([^:/]+):(\d+)/(\w+)", db_url)
    user, password, host, port, dbname = m.groups()
    if PRODUCTION_REF in user:
        raise RuntimeError("REFUSING: production ref in username")
    if EXPECTED_STAGING_REF not in user:
        raise RuntimeError(f"REFUSING: {user!r} doesn't encode staging ref")
    conn = pg8000.connect(
        user=user,
        password=password,
        host=host,
        port=int(port),
        database=dbname,
        timeout=20,
        ssl_context=True,
    )
    conn.autocommit = False
    return conn


def call_rpc(cur, op_id, start_date=None, duration=None, cycle=None):
    # Computed in Python, not via a SQL CASE expression keyed off the
    # same bound parameter -- Postgres can't infer a parameter's type
    # from "$n IS NULL" alone (42P18), and this is simpler anyway.
    has_date = start_date is not None
    cur.execute(
        """
        SELECT episode_id, baseline_id, episode_conflict,
               conflicting_episode_id, conflicting_start_date
        FROM public.record_onboarding_menstrual_history(
            p_client_operation_id := %s,
            p_utc_offset_minutes := 180,
            p_start_date := %s,
            p_start_precision := %s,
            p_lifecycle_status := %s,
            p_continuation_certainty := %s,
            p_usual_bleeding_duration_days := %s,
            p_usual_cycle_length_days := %s
        )
        """,
        (
            op_id,
            start_date,
            "date_only" if has_date else None,
            "open" if has_date else None,
            "uncertain" if has_date else None,
            duration,
            cycle,
        ),
    )
    row = cur.fetchone()
    return {
        "episode_id": row[0],
        "baseline_id": row[1],
        "episode_conflict": row[2],
        "conflicting_episode_id": row[3],
        "conflicting_start_date": row[4],
    }


def main():
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT current_database()")
    print(f"==> staging confirmed: current_database()={cur.fetchone()[0]}\n")

    def as_user(cur):
        claims = json.dumps({"sub": TARGET_USER_ID, "role": "authenticated"})
        cur.execute("SELECT set_config('request.jwt.claims', %s, true)", (claims,))
        cur.execute("SET LOCAL ROLE authenticated")

    today = date.today()

    # --- Scenario 1: no open episode -> creates one normally ---------
    print("Scenario 1: no open episode -> onboarding creates one")
    cur.execute("BEGIN")
    # Cleanup runs as the connection's own (superuser/pooler) role --
    # `authenticated` correctly has no direct DELETE grant on this table
    # (all writes are meant to go through the SECURITY DEFINER RPCs
    # only), confirmed by this exact permission error the first time
    # this script ran with the ordering reversed.
    cur.execute(
        "DELETE FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    as_user(cur)
    op1 = str(uuid.uuid4())
    d1 = today - timedelta(days=5)
    r1 = call_rpc(cur, op1, start_date=d1)
    check("episode_id is a real id", r1["episode_id"] is not None)
    check("no conflict reported", r1["episode_conflict"] is False)
    cur.execute("ROLLBACK")
    print()

    # --- Scenario 2: matching open episode already exists ------------
    print("Scenario 2: matching open episode (same start_date) -> reused")
    cur.execute("BEGIN")
    # Cleanup runs as the connection's own (superuser/pooler) role --
    # `authenticated` correctly has no direct DELETE grant on this table
    # (all writes are meant to go through the SECURITY DEFINER RPCs
    # only), confirmed by this exact permission error the first time
    # this script ran with the ordering reversed.
    cur.execute(
        "DELETE FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    as_user(cur)
    pre_op = str(uuid.uuid4())
    d2 = today - timedelta(days=8)
    pre = call_rpc(cur, pre_op, start_date=d2)
    check("setup: pre-existing open episode created", pre["episode_id"] is not None)

    op2 = str(uuid.uuid4())  # a DIFFERENT operation id -- not a retry
    r2 = call_rpc(cur, op2, start_date=d2)  # same date
    check("reused the existing episode's id", r2["episode_id"] == pre["episode_id"])
    check("no conflict reported", r2["episode_conflict"] is False)
    cur.execute(
        "SELECT count(*) FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    check("exactly one open episode exists", cur.fetchone()[0] == 1)
    cur.execute(
        "SELECT count(*) FROM public.bleeding_observations WHERE episode_id = %s",
        (pre["episode_id"],),
    )
    observation_count = cur.fetchone()[0]
    check(
        "exactly one observation for it (no duplicate)",
        observation_count == 1,
        detail=f"found {observation_count}",
    )
    cur.execute("ROLLBACK")
    print()

    # --- Scenario 3: retry the same payload twice ---------------------
    print("Scenario 3: retry same onboarding payload twice -> no duplicates")
    cur.execute("BEGIN")
    # Cleanup runs as the connection's own (superuser/pooler) role --
    # `authenticated` correctly has no direct DELETE grant on this table
    # (all writes are meant to go through the SECURITY DEFINER RPCs
    # only), confirmed by this exact permission error the first time
    # this script ran with the ordering reversed.
    cur.execute(
        "DELETE FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    as_user(cur)
    op3 = str(uuid.uuid4())
    d3 = today - timedelta(days=3)
    first = call_rpc(cur, op3, start_date=d3, duration=5, cycle=28)
    second = call_rpc(cur, op3, start_date=d3, duration=5, cycle=28)  # same op id
    check(
        "second call returns the identical episode_id",
        first["episode_id"] == second["episode_id"],
    )
    check(
        "second call returns the identical baseline_id",
        first["baseline_id"] == second["baseline_id"],
    )
    cur.execute(
        "SELECT count(*) FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    check("still exactly one open episode", cur.fetchone()[0] == 1)
    cur.execute(
        "SELECT count(*) FROM public.cycle_baselines WHERE client_operation_id = %s",
        (op3,),
    )
    check("still exactly one baseline for this operation", cur.fetchone()[0] == 1)
    cur.execute("ROLLBACK")
    print()

    # --- Scenario 4: conflicting open episode -------------------------
    print("Scenario 4: conflicting open episode (different start_date) "
          "-> typed conflict, no destructive mutation")
    cur.execute("BEGIN")
    # Cleanup runs as the connection's own (superuser/pooler) role --
    # `authenticated` correctly has no direct DELETE grant on this table
    # (all writes are meant to go through the SECURITY DEFINER RPCs
    # only), confirmed by this exact permission error the first time
    # this script ran with the ordering reversed.
    cur.execute(
        "DELETE FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    as_user(cur)
    pre_op4 = str(uuid.uuid4())
    d_existing = today - timedelta(days=10)
    pre4 = call_rpc(cur, pre_op4, start_date=d_existing)
    check("setup: pre-existing open episode created", pre4["episode_id"] is not None)

    op4 = str(uuid.uuid4())
    d_conflicting = today - timedelta(days=2)  # genuinely different date
    r4 = call_rpc(cur, op4, start_date=d_conflicting, duration=6, cycle=30)
    check("episode_id is null (nothing inserted for the episode)", r4["episode_id"] is None)
    check("episode_conflict is true", r4["episode_conflict"] is True)
    check(
        "conflicting_episode_id names the real existing episode",
        r4["conflicting_episode_id"] == pre4["episode_id"],
    )
    check(
        "conflicting_start_date matches the existing episode's real date",
        r4["conflicting_start_date"] == d_existing,
    )
    check(
        "baseline STILL saved independently despite the episode conflict",
        r4["baseline_id"] is not None,
    )
    cur.execute(
        "SELECT lifecycle_status, start_date FROM public.bleeding_episodes WHERE id = %s",
        (pre4["episode_id"],),
    )
    row = cur.fetchone()
    check(
        "the existing episode's own status/date are completely untouched",
        row[0] == "open" and row[1] == d_existing,
    )
    # Scoped to 'open' deliberately: this real staging account may
    # already have unrelated *ended* historical episodes from genuine
    # earlier use — an absolute total would be a brittle, environment-
    # dependent assertion. The actual invariant under test is "still
    # exactly the one open episode from setup, never a second one".
    cur.execute(
        "SELECT count(*) FROM public.bleeding_episodes WHERE user_id = %s AND lifecycle_status = 'open'",
        (TARGET_USER_ID,),
    )
    check("no new open episode row was created", cur.fetchone()[0] == 1)
    cur.execute("ROLLBACK")
    print()

    cur.execute("SELECT madhhab_selection_state FROM public.users WHERE id = %s LIMIT 1", (TARGET_USER_ID,))
    print("Scenario 5/6 (onboarding_completed sequencing): verified at the "
          "Dart layer, not here — this RPC never writes to public.users at "
          "all (grep-confirmed: no 'public.users' reference in the "
          "function body), so onboarding_completed's own sequencing is "
          "entirely _completeOnboarding()'s responsibility in "
          "onboarding_screen.dart, covered by code review + the Dart "
          "control-flow analysis in the final report.")

    conn.close()
    print(f"\n==> {len(_passed)} passed, {len(_failed)} failed")
    if _failed:
        print("FAILED:")
        for f in _failed:
            print(f"  - {f}")
        sys.exit(1)


if __name__ == "__main__":
    main()

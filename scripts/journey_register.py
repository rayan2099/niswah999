#!/usr/bin/env python3
"""Builds docs/journeys/NISWAH_JOURNEY_COVERAGE.csv.

The 300 app-wide journeys (trigger and required outcome) are read verbatim
from docs/NISWAH_APP_WIDE_300_ACCEPTANCE_JOURNEYS.md; this script never
rewrites them. The per-journey assessment lives in ASSESSMENT below and is
merged by NJ id. The build fails if any of the 300 ids is missing,
duplicated or unassessed in the data, if a status is unknown, or if a row
claims automated evidence (or VERIFIED) without naming it.

Evidence dimensions are recorded separately, as the register requires:
automated, staging integration, signed iPhone, signed Android, specialist.
A row is VERIFIED only when every dimension it needs has passed. A row
whose automated assertion passes but which still needs another dimension
stays IMPLEMENTED — UNVERIFIED, and is counted under "automated outcome
demonstrated".

  python3 scripts/journey_register.py          # write the CSV
  python3 scripts/journey_register.py --check  # fail if stale
"""
from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_MD = ROOT / "docs/NISWAH_APP_WIDE_300_ACCEPTANCE_JOURNEYS.md"
CSV_OUT = ROOT / "docs/journeys/NISWAH_JOURNEY_COVERAGE.csv"

STATUS = {
    "NA": "NOT ASSESSED",
    "IR": "IMPLEMENTATION REQUIRED",
    "IU": "IMPLEMENTED — UNVERIFIED",
    "V": "VERIFIED",
    "BX": "BLOCKED — EXTERNAL EVIDENCE REQUIRED",
    "OOS": "OUT OF SCOPE — EXPLICIT DECISION",
}
SCOPE = {
    "IN": "Included (feature ships in the current app)",
    "COND": "Conditional (feature exists; launch scope to be confirmed by rayan)",
    "NONE": "Not implemented; launch-scope decision required (rayan)",
    "DEFER": "Deferred by product decision 2026-10-29 (qadha after tracking)",
    "OPS": "Operations / release process (not app code)",
}
# Evidence dimension values.
DIM = {
    "P": "PASS",
    "PP": "PARTIAL",
    "-": "NOT APPLICABLE",
    "NR": "REQUIRED — NOT RUN",
    "BX": "BLOCKED — NEEDS EXTERNAL INPUT",
    "N": "NONE",
}
SEVERITY = {"C": "Critical", "H": "High", "M": "Medium", "L": "Low"}

# Code locations, expanded in the CSV.
L = {
    "SIGNIN": "lib/features/auth/presentation/screens/sign_in_screen.dart",
    "AUTHREPO": "lib/features/auth/data/repositories/auth_repository_impl.dart",
    "RECOVERY": "lib/features/auth/presentation/screens/password_recovery_screen.dart",
    "AUTHCTL": "lib/core/auth/auth_controller.dart",
    "MAIN": "lib/main.dart",
    "LEGAL": "lib/features/legal/",
    "ONB": "lib/features/onboarding/presentation/screens/onboarding_screen.dart",
    "MADHHAB": "lib/core/preferences/madhhab_controller.dart",
    "LOCALE": "lib/core/localization/app_locale_controller.dart",
    "TRACK": "lib/features/cycle_tracking/",
    "CAL": "lib/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart",
    "DASH": "lib/features/dashboard/presentation/screens/dashboard_screen.dart",
    "INSIGHTS": "lib/features/insights/",
    "CALC": "lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart",
    "FIQH": "lib/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart",
    "ENGINE": "lib/features/cycle_tracking/domain/services/cycle_status_engine.dart",
    "PREG": "lib/features/pregnancy_profile/",
    "AI": "lib/features/ai_assistant/ lib/features/ai_advisor/ supabase/functions/",
    "NOTIF": "lib/features/notifications/",
    "PRAYER": "lib/features/prayer_tracking/",
    "EXPORT": "lib/features/legal/domain/data_export_builder.dart",
    "DELETE": "lib/features/auth/domain/account_deletion_orchestrator.dart",
    "PBOS": "lib/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart",
    "STORE": "lib/core/storage/secure_local_store.dart",
    "COMM": "lib/features/community/",
    "MSG": "lib/features/private_messaging/",
    "WELL": "lib/features/wellbeing/",
    "REPORTS": "lib/features/doctor_report/ lib/features/fiqh_report/ lib/features/husband_report/",
    "MIG": "supabase/migrations/",
    "CI": ".github/workflows/",
}

# Test shorthands.
T = {
    "signup": "test/auth/signup_email_guidance_test.dart",
    "consent": "test/sign_in_consent_gating_test.dart",
    "routing": "test/auth_onboarding_routing_test.dart",
    "gate": "test/auth_gate_test.dart",
    "recovery": "test/password_recovery_screen_test.dart",
    "authctl": "test/services/auth_controller_test.dart",
    "acct": "test/cycle_repository_account_switch_regression_test.dart",
    "notifacct": "test/notification_account_transition_test.dart",
    "chatacct": "test/notification_chat_account_safety_test.dart",
    "prefs": "test/user_scoped_preferences_test.dart",
    "securestore": "test/secure_local_store_test.dart",
    "thread": "test/pending_operation_userid_threading_test.dart",
    "delres": "test/account_deletion_resilience_test.dart",
    "delops": "test/logging_sync_hardening/account_deletion_pending_ops_test.dart",
    "export": "test/data_export_resilience_test.dart",
    "boundary": "test/account_isolation/account_boundary_test.dart",
    "draft": "test/account_isolation/entry_draft_after_session_end_test.dart",
    "onbui": "test/onboarding_ui_test.dart",
    "onbans": "test/onboarding_server_hardening/onboarding_answers_test.dart",
    "onbsql": "test/onboarding_server_hardening/sql/02_onboarding_rpc_duplicates_and_overlaps.sql",
    "onberr": "test/onboarding_completion_error_test.dart",
    "madhhabres": "test/madhhab_resolution_test.dart",
    "locale": "test/localization_ui_test.dart",
    "rtl": "test/sign_in_rtl_test.dart",
    "a11y": "test/accessibility_semantics_test.dart",
    "textscale": "test/accessibility_text_scaling_test.dart",
    "calendar": "test/canonical_calendar_screen_test.dart",
    "startsheet": "test/start_bleeding_sheet_test.dart",
    "correction": "test/correction_sheet_test.dart",
    "episodeedit": "test/period_tracking/episode_edit_test.dart",
    "obsrm": "test/period_tracking/observation_remove_test.dart",
    "endunk": "test/period_tracking/end_unknown_test.dart",
    "episql": "test/security/bleeding_episode_corrections.sql",
    "obsrmsql": "test/security/bleeding_observation_removal.sql",
    "endunksql": "test/security/bleeding_episode_end_unknown.sql",
    "rpcsql": "test/logging_sync_hardening/sql/canonical_rpc_regression.sql",
    "concurrency": "test/period_tracking_concurrency_test.dart",
    "pending": "test/pending_bleeding_operation_store_test.dart",
    "reconcile": "test/logging_sync_hardening/reconcile_pending_operations_test.dart",
    "failures": "test/logging_sync_hardening/bleeding_sheet_failure_outcomes_test.dart",
    "idem": "test/cycle_local_sync_idempotency_test.dart",
    "estimate": "test/cycle_prediction_estimate_test.dart",
    "calcsvc": "test/cycle_calculation_service_test.dart",
    "nextperiod": "test/screens_hardening/next_period_cross_screen_test.dart",
    "midnight": "test/screens_hardening/dashboard_stale_summary_after_midnight_test.dart",
    "dst": "test/screens_hardening/dst_day_counts_test.dart",
    "caldst": "test/screens_hardening/calendar_dst_and_empty_test.dart",
    "late": "test/screens_hardening/dashboard_late_period_ring_test.dart",
    "resumed": "test/resumed_bleeding/resumed_bleeding_prediction_test.dart",
    "nodata": "test/period_tracking/prediction_no_data_test.dart",
    "noqadha": "test/period_tracking/no_qadha_from_predictions_test.dart",
    "fiqhhard": "test/fiqh_hardening/fiqh_engine_hardening_test.dart",
    "fiqhprops": "test/round2_properties/fiqh_properties_test.dart",
    "aifiqh": "test/fiqh_hardening/ai_client_fiqh_state_test.dart",
    "madhhabchange": "test/madhhab_change_confirmation_test.dart",
    "rulesetver": "test/madhhab_ruleset_version_test.dart",
    "redflag": "test/dr_niswah_red_flag_dual_state_test.dart",
    "aicite": "test/ai_backend_citation_contract_test.dart",
    "aimal": "test/ai_malformed_response_test.dart",
    "aipersist": "test/ai_chat_persistence_resilience_test.dart",
    "notifsched": "test/services/notification_scheduler_test.dart",
    "notifperm": "test/notification_ios_permissions_test.dart",
    "notifblocked": "test/notification_settings_blocked_notice_test.dart",
    "notifnav": "test/app_wide_notification_navigation_test.dart",
    "notiftz": "test/notification_timezone_test.dart",
    "notifrel": "test/notification_reliability_test.dart",
    "notifhist": "test/notification_cycle_reminder_history_test.dart",
    "pregnotif": "test/pregnancy_notifications_hardening/notification_copy_and_feed_test.dart",
    "prayerloc": "test/prayer_location_device_test.dart",
    "prayerint": "test/prayer_time_integrity_test.dart",
    "commidem": "test/community_repository_idempotency_test.dart",
    "msgrt": "test/private_messaging_realtime_test.dart",
    "msg": "test/private_messaging_test.dart",
    "rlssql": "test/security/tracking_rls_initplan_and_fk_indexes.sql",
    "anonsql": "test/security/revoke_anon_security_definer_execute.sql",
    "userssql": "test/security/users_privileged_columns_guard.sql",
    "errclass": "test/error_classification_test.dart",
    "sentry": "test/app_error_reporter_sentry_test.dart",
    "netfail": "test/network_failure_test.dart",
    "wellsplit": "test/wellbeing_period_split_test.dart",
    "discard": "test/period_tracking/episode_edit_test.dart (PT-178 tests)",
}

# One line per journey:
# id | scope | status | automated | staging | iPhone | Android | specialist |
#   severity | PT links | locations | evidence | gap / next action
# Dimension values: P, PP, -, NR, BX, N (see DIM).
ASSESSMENT = r"""
NJ-001|IN|IU|N|-|NR|NR|-|M|-|ONB MAIN|-|First screen exists; comprehension needs a usability check and device run.
NJ-002|IN|IU|PP|-|NR|NR|BX|H|-|SIGNIN LEGAL|{consent} (policy screen opens before signup)|Policy reachable pre-signup is tested; accuracy of its content needs owner/legal sign-off.
NJ-003|IN|IU|P|-|NR|NR|-|H|-|SIGNIN|{signup} (destination shown, request wording)|Open PR feat/signup-email-guidance; device run with a real inbox pending.
NJ-004|IN|IU|P|-|NR|NR|-|H|-|SIGNIN|{signup} (Arabic «البريد غير المرغوب فيه (Spam)» wording, no delivery claim)|Open PR feat/signup-email-guidance; device run pending.
NJ-005|IN|IU|P|-|NR|NR|-|H|-|SIGNIN|{signup} ("Wrong email? Change it" keeps her input)|Open PR feat/signup-email-guidance. The abandoned unconfirmed account is left to Auth's own cleanup.
NJ-006|IN|IU|P|PP|NR|NR|-|M|-|SIGNIN AUTHREPO|{signup} (Auth rate-limit wait honoured; nothing claimed sent)|Expired-link recovery relies on Auth's error page; needs a device run of an expired link.
NJ-007|IN|IU|N|-|NR|NR|-|M|-|MAIN AUTHCTL|-|Deep link niswah://login-callback; cross-device confirmation needs a device run.
NJ-008|IN|IU|PP|-|NR|NR|-|M|-|SIGNIN|{signup} (neutral "already has an account" wording)|Supabase hides existing accounts; wording now neutral. Device run pending.
NJ-009|IN|IU|P|-|NR|NR|-|H|-|MAIN AUTHCTL ONB|{routing} (confirmed user resumes onboarding or dashboard from server state)|Device run pending.
NJ-010|IN|IU|P|-|NR|NR|-|M|-|SIGNIN AUTHREPO|{signup} (wrong credentials and rate limit worded in Arabic/English; Auth's wait shown)|Draft PR #63. Lockout policy itself is Supabase's; device run pending.
NJ-011|IN|IU|P|PP|NR|NR|-|H|-|RECOVERY|{recovery} (updates once and finishes)|Real reset email and link on device not yet run.
NJ-012|IN|IU|PP|-|NR|NR|-|M|-|RECOVERY|{recovery} (server rejection does not finish)|Expired/reused link UX needs a device run.
NJ-013|IN|IU|P|-|NR|NR|-|H|-|AUTHCTL TRACK|{draft} (day-log input kept for its account, offered back, never to another); {boundary}|Draft PR #66 (day-log sheet only) and #65. Start-bleeding and correction sheets have no draft; device run pending.
NJ-014|IN|IU|P|-|NR|NR|-|C|PT-152 PT-153|AUTHCTL STORE NOTIF|{acct}; {prefs}; {notifacct}; {chatacct}|AI context and drafts on switch not covered by one test; device A→B run pending (gate A15).
NJ-015|IN|IU|PP|-|NR|NR|-|H|PT-001|ONB|{onbans}; {onbui}|Dashboard consistency after onboarding not asserted end to end.
NJ-016|IN|IU|PP|-|NR|NR|-|H|PT-004|ONB CALC|{onbans}|No-history path saves nothing invented; prediction "unavailable" proven in {nodata}.
NJ-017|IN|IU|P|NR|NR|NR|-|H|PT-002|ONB TRACK MIG|{onbans} (R2-ONB-3 / PT-002); {endunksql}; {endunk}|Migration 20261029130000 not yet on staging.
NJ-018|IN|IR|N|-|NR|NR|BX|H|PT-003|ONB TRACK|-|No approximate-date precision; prediction policy needs clinical input (PT-003).
NJ-019|IN|IU|P|-|NR|NR|-|H|PT-101|MADHHAB|{madhhabres}|Device run pending.
NJ-020|IN|IU|PP|-|NR|NR|-|M|-|ONB|{onbans} (changed answer gets a fresh operation id)|Resume after kill not asserted.
NJ-021|IN|IU|PP|-|NR|NR|-|M|-|ONB LOCALE|{locale}|Onboarding answers across a language switch not asserted.
NJ-022|IN|IU|PP|-|NR|NR|-|H|-|NOTIF PRAYER|{notifblocked}; {prayerloc}|Repeated-prompt behaviour needs device evidence (gate A9, A22).
NJ-023|IN|IU|PP|-|NR|NR|-|H|PT-031|DASH CAL|{calendar}|Not-recorded vs no-bleeding on Today needs an explicit assertion.
NJ-024|IN|IU|PP|-|NR|NR|-|H|PT-061|DASH CAL INSIGHTS|{nextperiod}|Cross-screen observation consistency partly covered.
NJ-025|IN|IU|PP|-|NR|NR|-|M|PT-016|TRACK WELL|test/round2_hardening/symptoms_on_bleeding_days_test.dart|Notes/mood save paths not all asserted.
NJ-026|IN|IU|PP|-|NR|NR|-|H|PT-026|TRACK NOTIF|{failures}|Reminder refresh after stop not asserted together.
NJ-027|IN|IU|P|P|NR|NR|-|H|PT-027|TRACK MIG|{episodeedit} (PT-027); {episql} section 5|Device run pending.
NJ-028|IN|IU|P|PP|NR|NR|-|H|PT-051 PT-052 PT-055|TRACK MIG|{episodeedit}; {obsrm}; {episql}; {obsrmsql}|Migration 20261029120000 is on staging; its behaviour script not confirmed run there.
NJ-029|IN|IU|PP|-|NR|NR|BX|H|PT-036|CALC FIQH|{resumed}|Fiqh treatment of resumed bleeding awaits scholar review.
NJ-030|IN|IU|P|-|NR|NR|-|H|PT-071|CALC DASH|{late}|Device run pending.
NJ-031|IN|IU|PP|-|NR|NR|-|M|PT-079|INSIGHTS CALC|{nodata}|"Explain calculations" not asserted.
NJ-032|COND|IU|PP|-|NR|NR|BX|M|-|PREG|test/services/pregnancy_status_engine_test.dart; {pregnotif}|Pregnancy scope and wording need clinical/scholar review.
NJ-033|IN|IU|PP|-|NR|NR|BX|M|-|AI|{aicite}|Separation is prompt-level; specialist review of answers pending (gate 4).
NJ-034|IN|IU|PP|-|NR|NR|BX|M|-|AI FIQH|{aifiqh}|Clarifying questions not asserted; scholar review pending.
NJ-035|IN|BX|PP|-|NR|NR|BX|C|PT-091|AI|{redflag}|Red-flag rule fires on any "bleeding" mention; threshold and wording need clinician approval.
NJ-036|IN|IR|N|-|NR|NR|-|M|-|AI|-|No dialect/voice date clarification before changes (AI cannot change records today).
NJ-037|IN|IU|N|-|-|-|-|M|-|AI|-|AI has no record-mutation tools, so no unconfirmed change is possible; preview flow not built.
NJ-038|IN|IU|PP|-|NR|NR|-|M|-|AI|{aimal}; {aipersist}|Limitation disclosure wording not asserted.
NJ-039|DEFER|BX|N|-|-|-|-|L|PT-111|-|-|Qadha ledger deferred by product decision; not implemented.
NJ-040|DEFER|BX|N|-|-|-|-|L|PT-113|-|-|Qadha ledger deferred.
NJ-041|DEFER|BX|N|-|-|-|-|L|PT-114|-|-|Qadha ledger deferred.
NJ-042|DEFER|BX|N|-|-|-|-|L|PT-115|-|-|Qadha ledger deferred.
NJ-043|DEFER|BX|P|-|-|-|-|M|PT-112|TRACK|{noqadha} (no qadha code path from predictions)|Automation intentionally absent; ledger deferred.
NJ-044|DEFER|BX|N|-|-|-|-|L|PT-116|-|-|Qadha ledger deferred.
NJ-045|IN|IU|PP|-|NR|NR|-|H|PT-078 PT-164|NOTIF|{notifsched}; {notifhist}|Recalculation after deletes untested for reminders (PT-078/PT-164).
NJ-046|IN|IU|P|-|NR|NR|-|H|-|NOTIF|{pregnotif} (generic lock-screen copy)|Device lock-screen check pending (gate A14).
NJ-047|IN|IU|PP|-|NR|NR|-|C|PT-152|NOTIF MAIN|{notifnav}; {chatacct}|Signed-out tap and other-account tap need device evidence.
NJ-048|IN|IU|PP|-|NR|NR|-|M|PT-180|NOTIF|{notiftz}|Reminder timezone policy not written down.
NJ-049|NONE|BX|N|-|-|-|-|M|-|-|-|No subscriptions in the app; launch-scope decision needed.
NJ-050|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases in the app; launch-scope decision needed.
NJ-051|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases in the app.
NJ-052|NONE|BX|N|-|-|-|-|M|-|-|-|No subscriptions in the app.
NJ-053|IN|IU|P|-|NR|NR|BX|H|-|EXPORT LEGAL|{export}|Export is resilient and scoped; support contact wording needs owner review.
NJ-054|IN|IU|P|PP|NR|NR|-|C|PT-156|DELETE PBOS|{delres}; {delops}|Staging cascade confirmed earlier (34 tables); device run pending (gate A16).
NJ-055|IN|IU|P|-|NR|NR|-|C|PT-141|PBOS TRACK|{pending}; {reconcile}|Real offline→restart→reconnect needs a device run (gate A17/A18).
NJ-056|IN|IU|P|P|NR|NR|-|H|PT-060 PT-148|TRACK MIG|{episodeedit} (NW409); {episql} section 8|Device run pending.
NJ-057|IN|IU|P|-|NR|NR|-|C|PT-144|PBOS TRACK|{reconcile}; {idem}|Device run pending.
NJ-058|IN|IU|PP|-|NR|NR|-|H|-|MAIN|{a11y}; {textscale}; {rtl}|Screen reader and reduced motion need device evidence (gate A19).
NJ-059|IN|IU|PP|-|NR|NR|-|H|-|STORE PBOS|{securestore} (legacy data survives migration)|Upgrade with pending writes on a device not run.
NJ-060|OPS|BX|-|-|NR|NR|-|C|PT-200|-|-|Signed-device runs (gate 5) owned by rayan/QA.
NJ-061|IN|IU|P|-|NR|NR|-|M|-|SIGNIN|{signup} (trim + lower-case; shown back)|Open PR feat/signup-email-guidance.
NJ-062|IN|IU|P|-|NR|NR|-|M|-|SIGNIN|{signup} (suggested, applied only on tap)|Open PR feat/signup-email-guidance.
NJ-063|IN|IU|N|-|NR|NR|-|M|-|SIGNIN|-|Input kept on failure (network path); server rejection shows Auth's raw text.
NJ-064|IN|IU|N|-|NR|NR|-|M|-|AUTHREPO|-|Auth de-duplicates by email; lost-response recovery not tested.
NJ-065|IN|IU|P|-|NR|NR|-|M|-|SIGNIN|{signup} (cooldown; one request per tap window)|Open PR feat/signup-email-guidance.
NJ-066|IN|IU|P|-|NR|NR|-|M|-|SIGNIN|{signup} (no delivery-time promise)|Open PR feat/signup-email-guidance.
NJ-067|IN|IU|N|-|NR|NR|-|M|-|AUTHCTL|-|Token validity handled by Auth; app message for a stale link not tested.
NJ-068|IN|IU|N|-|NR|NR|-|M|-|MAIN|-|Malformed link handling and token redaction in diagnostics not tested.
NJ-069|IN|IU|P|-|NR|NR|-|M|-|SIGNIN AUTHCTL|{signup} (sign-in event closes the waiting sheet once; refresh and repeats ignored)|Draft PR #63; device run with a real link pending.
NJ-070|IN|IU|P|-|NR|NR|-|M|-|SIGNIN|{signup} ("I've confirmed: sign in" route)|Open PR feat/signup-email-guidance.
NJ-071|IN|IU|PP|-|NR|NR|-|C|PT-153|TRACK|{acct}; {boundary} (screens over home close on sign-out or switch)|Same-user-ID-again (A→B→A) delayed tracking response not fully tested; see PR #62 and draft PR #65.
NJ-072|IN|IU|P|-|NR|NR|-|C|PT-152|PBOS|{acct} (signed-out save stays pending); {thread}|Device run pending.
NJ-073|IN|IU|N|-|NR|NR|-|M|-|AUTHCTL|-|Session invalidation policy after reset elsewhere not documented.
NJ-074|IN|IU|P|-|NR|NR|-|H|-|RECOVERY AUTHCTL|{recovery} (names the account being changed); {boundary}|Draft PR #65: save refused if the session changed account after the form opened. Device run pending.
NJ-075|NONE|BX|N|-|-|-|-|L|-|-|-|No biometric lock in the app; scope decision needed.
NJ-076|IN|IU|PP|-|NR|NR|-|H|-|AUTHCTL|{authctl}|Resume revalidation not asserted.
NJ-077|IN|IU|N|-|NR|NR|-|M|-|AUTHCTL|-|Duplicate callback handling not tested.
NJ-078|IN|IU|N|-|NR|NR|-|H|-|AUTHCTL STORE|-|Refresh failure path not tested.
NJ-079|IN|IU|PP|-|NR|NR|-|M|-|RECOVERY|{recovery} (clears pushed screens)|Back during recovery not asserted.
NJ-080|IN|IU|P|-|NR|NR|-|M|-|SIGNIN AUTHREPO|{signup} (user_banned shown as suspended)|Draft PR #63. No in-app appeal or support contact is defined yet.
NJ-081|IN|BX|N|-|-|-|BX|M|-|MAIN|-|Sentry crash reporting has no opt-out; whether it counts as optional analytics is a policy decision.
NJ-082|IN|BX|N|-|-|-|BX|M|-|LEGAL|-|Consent is not versioned; needs a policy decision.
NJ-083|IN|IU|PP|-|NR|NR|-|M|-|ONB|{onbans} (R2-ONB-4)|Back navigation partly covered.
NJ-084|IN|IU|PP|-|NR|NR|-|H|-|ONB PBOS|{onberr}|Kill during save relies on the pending operation; not asserted after restart.
NJ-085|IN|IU|PP|-|NR|NR|-|M|PT-005|ONB|{onbans} (R2-ONB-7)|Partly covered.
NJ-086|IN|IU|PP|-|NR|NR|-|M|-|ONB|{onbans} (R2-ONB-4 clears end after start change)|Partly covered.
NJ-087|IN|IU|P|-|NR|NR|-|M|-|ONB|{onbans} (R2-ONB-5 skip saves nothing)|Device run pending.
NJ-088|IN|IU|PP|-|NR|NR|-|M|-|LOCALE|{locale}|Partly covered.
NJ-089|NONE|BX|-|-|-|-|-|L|-|-|-|No calendar display preference exists; the Hijri month is shown beside the Gregorian label. Scope decision needed before building one.
NJ-090|IN|IU|PP|-|NR|NR|-|M|-|NOTIF|{notifperm}|Resume refresh needs device evidence.
NJ-091|IN|IU|P|-|NR|NR|-|H|PT-020|TRACK|{concurrency}; {idem}|Device run pending.
NJ-092|IN|IU|P|-|NR|NR|-|H|PT-009|TRACK MIG|{rpcsql} (future dates rejected server-side)|Device clock-wrong run pending.
NJ-093|IN|IU|P|P|NR|NR|-|H|PT-054|TRACK MIG|{episodeedit} (PT-054); {episql} section 3|Device run pending.
NJ-094|IN|IR|N|-|NR|NR|-|M|PT-015|TRACK|-|Observation time capture is not implemented (PT-015); date-only stays date-only.
NJ-095|IN|IR|N|-|NR|NR|-|M|PT-017|TRACK|-|Depends on time capture (PT-017).
NJ-096|IN|IU|PP|-|NR|NR|-|M|-|TRACK|{midnight}|Partly covered.
NJ-097|IN|IU|PP|-|NR|NR|-|M|PT-019|TRACK|{calendar}|Daily timeline readability not asserted.
NJ-098|IN|IU|N|-|NR|NR|-|M|-|TRACK|-|Not asserted.
NJ-099|IN|IU|P|PP|NR|NR|-|H|PT-055|TRACK MIG|{obsrm}; {obsrmsql} (start/end protected; rest unchanged)|120000 on staging; behaviour script not confirmed run.
NJ-100|IN|IU|P|PP|NR|NR|-|H|PT-060|TRACK MIG|{obsrmsql} (stale token NW409)|Device run pending.
NJ-101|IN|IR|N|-|-|-|-|M|PT-045|-|-|Split not implemented (PT-045).
NJ-102|IN|IR|N|-|-|-|-|M|PT-046|-|-|Merge not implemented (PT-046).
NJ-103|IN|IR|N|-|-|-|-|L|PT-045|-|-|Depends on split/merge.
NJ-104|IN|IR|N|-|-|-|-|M|PT-045|-|-|Depends on split/merge.
NJ-105|IN|IU|PP|-|-|-|-|M|-|TRACK|test/logging_sync_hardening/legacy_log_provenance_test.dart|Contradictory legacy boundaries partly covered.
NJ-106|IN|IU|PP|-|NR|NR|-|M|PT-064|CAL|{caldst}|Year boundary not explicitly asserted.
NJ-107|NONE|BX|-|-|-|-|-|L|-|-|-|No history search or filter exists. Scope decision needed.
NJ-108|IN|IU|N|-|NR|NR|-|M|-|TRACK|-|Not asserted.
NJ-109|IN|IU|P|P|NR|NR|-|M|PT-057|TRACK MIG|{episql} (replay returns the same revision); {obsrmsql} section 1|Device run pending.
NJ-110|IN|IU|N|-|NR|NR|-|L|-|TRACK|-|Undo is snackbar-only; no retention window message.
NJ-111|IN|IU|PP|-|NR|NR|-|H|PT-061|CAL|{calendar}|Accessible distinction needs screen-reader evidence.
NJ-112|IN|IU|PP|-|NR|NR|-|H|PT-031|CAL|{calendar}|Partly covered.
NJ-113|IN|IU|N|-|NR|NR|-|M|-|DASH|-|Not asserted.
NJ-114|IN|IU|N|-|NR|NR|-|M|-|INSIGHTS|-|Not asserted.
NJ-115|NONE|BX|-|-|-|-|-|L|-|-|-|Insights charts have no point drill-down. Scope decision needed.
NJ-116|IN|IU|P|-|NR|NR|-|M|PT-079|INSIGHTS|{nodata}|Device run pending.
NJ-117|IN|IU|PP|-|NR|NR|BX|M|PT-070|CALC|{calcsvc}|Eligibility rules need clinical review.
NJ-118|IN|IU|PP|-|NR|NR|-|L|-|CAL|test/calendar_days_test.dart|Leap day not explicitly asserted.
NJ-119|IN|IU|PP|-|NR|NR|-|M|-|CAL|test/calendar_legend_live_language_switch_test.dart|Selected-day announcements need device evidence.
NJ-120|IN|IU|P|-|NR|NR|-|M|-|DASH|{midnight}|Device run pending.
NJ-121|IN|IU|P|-|NR|NR|-|H|PT-079|CALC INSIGHTS|{nodata}|Device run pending.
NJ-122|IN|IR|N|-|-|-|-|M|-|CALC|-|No prediction version metadata stored.
NJ-123|IN|IR|N|-|-|-|-|M|-|CALC|-|No prediction evaluation snapshots exist.
NJ-124|IN|IU|PP|-|NR|NR|-|M|PT-072|CALC NOTIF|{estimate}|Reminder retirement not asserted together.
NJ-125|IN|IU|P|-|NR|NR|-|M|PT-071|CALC|{late}|Device run pending.
NJ-126|IN|IR|N|-|-|-|BX|M|PT-003|CALC|-|No approximate precision yet (PT-003).
NJ-127|NONE|BX|-|-|-|-|-|M|-|-|-|No data import exists. Scope decision needed.
NJ-128|NONE|BX|-|-|-|-|-|M|-|-|-|No setting to turn predictions off. Scope decision needed.
NJ-129|OPS|BX|N|-|-|-|-|M|-|-|-|No prediction feature flag; operations decision.
NJ-130|OPS|BX|N|-|-|-|BX|M|-|-|-|Accuracy measurement planned post-pilot (gate 4); no claims made.
NJ-131|IN|BX|PP|-|-|-|BX|C|PT-091|AI FIQH|{redflag}|Clinical rules unreviewed (gate 4).
NJ-132|COND|BX|N|-|-|-|BX|H|-|PREG|-|Pregnancy wording needs clinical review.
NJ-133|COND|IU|PP|-|NR|NR|BX|M|-|PREG|test/services/pregnancy_status_engine_test.dart|Needs review.
NJ-134|NONE|BX|N|-|-|-|-|L|-|-|-|No medication/contraception input; scope decision.
NJ-135|IN|BX|PP|-|-|-|BX|C|PT-091|AI|{redflag}|Escalation in notes not implemented; chat red flag unreviewed.
NJ-136|OPS|BX|N|-|-|-|BX|H|-|-|-|No remote content withdrawal mechanism.
NJ-137|IN|BX|N|-|-|-|BX|M|-|-|-|Translation review status not tracked.
NJ-138|IN|BX|N|-|NR|NR|BX|M|-|-|-|Needs a specialist-approved acknowledgment policy for repeated safety notices before building.
NJ-139|IN|IU|PP|-|-|-|BX|M|-|AI|{aicite}|Capability-limit wording needs clinician approval.
NJ-140|OPS|BX|N|-|-|-|BX|L|-|-|-|No guidance caching policy.
NJ-141|IN|IU|P|-|NR|NR|BX|H|PT-102|MADHHAB FIQH|{madhhabchange}; test/services/multi_madhhab_engine_test.dart|Rule values unreviewed by scholar.
NJ-142|IN|IU|P|-|NR|NR|-|H|PT-101|MADHHAB|{madhhabres}|Device run pending.
NJ-143|IN|BX|PP|-|-|-|BX|H|PT-104|FIQH|{fiqhhard}|Scholar review of boundaries pending.
NJ-144|IN|BX|PP|-|-|-|BX|H|PT-036|FIQH|{resumed}|Scholar review pending.
NJ-145|IN|IU|P|-|-|-|BX|H|PT-002|FIQH|{endunk} (no ruling while end unknown)|Wording approval pending.
NJ-146|IN|IU|PP|-|-|-|BX|M|-|FIQH|{rulesetver}|Rule changes need scholar sign-off.
NJ-147|OPS|IR|N|-|-|-|-|H|PT-196|FIQH|-|No remote fiqh kill switch (PT-196).
NJ-148|IN|IR|N|-|-|-|BX|M|PT-199|FIQH|-|No report/challenge flow (PT-199).
NJ-149|IN|BX|N|-|-|-|BX|M|PT-197|FIQH|-|Discrepancy detection not built (PT-197).
NJ-150|DEFER|BX|N|-|-|-|BX|L|-|-|-|Qadha suggestions deferred.
NJ-151|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-152|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-153|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-154|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-155|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-156|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-157|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-158|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-159|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha ledger deferred.
NJ-160|DEFER|IU|P|-|NR|NR|-|M|PT-112|DASH|{noqadha}|No qadha actions exist; the "Qadha example" Today card copy should be checked for implying a ledger.
NJ-161|IN|IU|P|-|NR|NR|-|M|-|NOTIF|{notifblocked}|Device run pending (gate A9).
NJ-162|COND|BX|N|-|-|-|-|L|-|NOTIF|-|Push is off for launch (gate 3).
NJ-163|IN|IU|P|-|NR|NR|-|C|PT-152|NOTIF|{notifacct}; {chatacct}|Device run pending.
NJ-164|IN|IU|PP|-|NR|NR|-|H|PT-164|NOTIF|{notifhist}|Deletion→stale reminder untested (PT-164).
NJ-165|IN|IU|PP|-|NR|NR|-|M|-|NOTIF|test/notification_settings_race_test.dart|Travel transitions not asserted.
NJ-166|IN|IR|N|-|NR|NR|-|L|-|-|-|Local reminders are scheduled per category with no grouping or de-duplication.
NJ-167|COND|BX|N|-|-|-|-|L|-|NOTIF|-|Push off for launch.
NJ-168|IN|IU|PP|-|NR|NR|-|M|-|NOTIF|{notifnav}|Partly covered.
NJ-169|IN|IU|PP|-|NR|NR|-|M|-|NOTIF|test/app_wide_notification_controller_test.dart|Partly covered.
NJ-170|IN|BX|N|-|NR|NR|-|M|-|NOTIF|-|Platform restrictions need device evidence.
NJ-171|IN|IU|N|-|NR|NR|-|C|-|AI|-|AI chat history is per user server-side; stale in-flight response after switch not tested.
NJ-172|IN|IU|PP|P|-|-|-|C|-|AI|{rlssql}|Server RLS; AI edge functions filter by user (deployed 2026-10-29).
NJ-173|IN|IU|N|-|-|-|-|H|-|AI|-|Prompt-injection handling not tested.
NJ-174|NONE|BX|-|-|-|-|-|M|-|AI|-|The AI cannot change records, so AI mutation journeys do not apply unless that is put in scope.
NJ-175|NONE|BX|-|-|-|-|-|M|-|AI|-|AI cannot change records; see NJ-174.
NJ-176|NONE|BX|-|-|-|-|-|M|-|AI|-|AI cannot change records; see NJ-174.
NJ-177|NONE|BX|-|-|-|-|-|M|-|AI|-|AI cannot change records; see NJ-174.
NJ-178|NONE|BX|-|-|-|-|-|M|-|AI|-|AI cannot change records; see NJ-174.
NJ-179|IN|BX|N|-|-|-|BX|M|-|AI|-|Chat retention policy undecided (gate 2 item 6).
NJ-180|IN|IU|PP|-|-|-|BX|M|-|AI|{aicite}|Specialist review pending.
NJ-181|IN|IU|PP|-|NR|NR|-|M|-|MSG|{msg}; {msgrt}|Messaging scope to confirm.
NJ-182|IN|IU|PP|PP|NR|NR|-|C|-|MSG|{chatacct}; {boundary} (open chat closes on account change)|Membership enforced by RLS (is_conversation_participant).
NJ-183|IN|IR|N|-|-|-|-|C|-|COMM MSG|-|No block feature (App Store 1.2). rayan 2026-10-29: community ships; block/report/moderation is being built in a separate thread.
NJ-184|IN|IR|N|-|-|-|-|C|-|COMM|-|No report feature (App Store 1.2). rayan 2026-10-29: community ships; being built in a separate thread.
NJ-185|IN|IR|N|-|-|-|-|M|-|MSG|-|Depends on block.
NJ-186|IN|BX|-|-|-|-|-|M|-|MSG|-|Editing or deleting a sent message is not offered; whether it should be is part of the community moderation work in its own thread.
NJ-187|NONE|BX|-|-|-|-|-|L|-|COMM|-|Community and messages are text-only; no attachments.
NJ-188|NONE|BX|-|-|-|-|-|L|-|MSG|-|No attachments exist.
NJ-189|IN|IR|N|-|NR|NR|-|C|-|COMM|-|No moderator tooling in the app; being built in the community moderation thread (App Store 1.2).
NJ-190|IN|OOS|-|-|-|-|-|H|-|COMM|-|rayan decided 2026-10-29 that community is in launch scope, so the community-out-of-scope journey does not apply.
NJ-191|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-192|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-193|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-194|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-195|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-196|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-197|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-198|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-199|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-200|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-201|IN|IU|PP|-|NR|NR|-|H|PT-143|PBOS|{pending}|Edit-before-sync partly covered.
NJ-202|IN|IU|PP|-|NR|NR|-|C|PT-145|PBOS MIG|{episql} (tombstones, NW410)|Unsynced local delete path not asserted.
NJ-203|IN|IU|P|P|NR|NR|-|C|PT-145|MIG|{episql}; {obsrmsql} (replay after removal refused)|Device run pending.
NJ-204|IN|IR|N|-|-|-|-|M|-|TRACK|-|No field-level merge policy.
NJ-205|IN|IU|P|P|NR|NR|-|H|PT-148|TRACK MIG|{episql} section 8|Recoverable versions via revisions; device run pending.
NJ-206|IN|IU|PP|-|NR|NR|-|H|-|STORE|{securestore} (failure keeps original)|Full-storage path not asserted.
NJ-207|IN|IU|PP|-|NR|NR|-|H|PT-144|PBOS|{reconcile}|Partly covered.
NJ-208|IN|IU|P|-|NR|NR|-|C|PT-152|PBOS|{acct}; {thread}|Device run pending.
NJ-209|IN|IU|PP|-|NR|NR|-|H|-|PBOS STORE|{securestore}|Queue format migration partly covered.
NJ-210|IN|IU|PP|-|NR|NR|-|H|-|TRACK|{episodeedit} (changed elsewhere)|Partly covered.
NJ-211|IN|IU|PP|-|NR|NR|-|M|PT-182|TRACK|test/device_timezone_test.dart|Date line not asserted.
NJ-212|IN|IU|P|-|NR|NR|-|M|PT-181|TRACK|{dst}|Device run pending.
NJ-213|IN|IU|PP|-|NR|NR|-|M|PT-183|TRACK|test/device_timezone_test.dart|Partly covered.
NJ-214|IN|IU|P|-|NR|NR|-|H|PT-009|MIG|{rpcsql} (server-side future check)|Device run pending.
NJ-215|IN|IU|PP|-|NR|NR|-|C|-|PRAYER|{prayerloc}|Open PR #58 guards prayer-location saves across switches.
NJ-216|IN|IU|PP|-|NR|NR|-|M|-|PRAYER|{prayerloc}|Partly covered.
NJ-217|IN|IU|PP|-|NR|NR|-|M|-|PRAYER|{prayerloc}|Device run pending (gate A22).
NJ-218|IN|IU|PP|-|NR|NR|BX|M|-|PRAYER|{prayerint}|Calculation settings review pending.
NJ-219|IN|BX|N|-|-|-|BX|L|-|-|-|Depends on reviewed fasting rules.
NJ-220|IN|IU|PP|-|-|-|-|M|PT-184|TRACK|test/logging_sync_hardening/legacy_log_provenance_test.dart|Partly covered.
NJ-221|IN|IU|PP|-|NR|NR|-|M|-|MAIN|{textscale}|Device run pending.
NJ-222|IN|BX|PP|-|NR|NR|-|M|-|CAL|{a11y}|Screen reader evidence needed.
NJ-223|IN|IU|P|-|NR|NR|-|M|-|TRACK|{episodeedit} (liveRegion error, sheet kept)|Device run pending.
NJ-224|IN|IU|PP|-|NR|NR|-|M|-|CAL|{calendar}|Partly covered.
NJ-225|IN|IU|N|-|NR|NR|-|M|-|-|-|Calendar and Today animations honour reduced motion (MediaQuery.disableAnimationsOf); not tested across feedback surfaces.
NJ-226|IN|IU|PP|-|NR|NR|-|M|-|COMM|test/community_composer_keyboard_test.dart|Partly covered (PR #53).
NJ-227|IN|IU|N|-|NR|NR|-|M|-|-|-|Standard Material focus order only; no explicit traversal; needs a device run with keyboard or switch access.
NJ-228|IN|IU|PP|-|NR|NR|-|M|-|SIGNIN|{signup} (address forced left-to-right)|Partly covered.
NJ-229|IN|IU|PP|-|-|-|-|L|-|LOCALE|test/app_localization_delegates_test.dart|Partly covered.
NJ-230|IN|IU|P|-|NR|NR|-|M|PT-178|TRACK|{discard}|Device run pending.
NJ-231|IN|IU|PP|-|NR|NR|-|M|-|EXPORT|{export}|Many-years size not tested.
NJ-232|IN|IU|P|-|-|-|-|H|-|EXPORT|{boundary} (switch mid-export discards it, also A→B→A)|Draft PR #65; device run pending.
NJ-233|IN|IU|P|-|-|-|-|M|-|EXPORT|{export} (failed sections listed)|Device run pending.
NJ-234|IN|IU|N|-|NR|NR|-|L|-|EXPORT|-|Export copies to the clipboard only (no share sheet) and says "Copied to clipboard", never delivered.
NJ-235|IN|IU|PP|-|-|-|-|H|-|MAIN|{sentry}|Redaction partly covered.
NJ-236|OPS|BX|N|-|-|-|BX|H|-|-|-|Support access policy undecided.
NJ-237|IN|IR|N|-|NR|NR|-|H|-|-|-|Account deletion calls delete_my_account with the current session; no recent-authentication step. Policy decision needed.
NJ-238|OPS|BX|N|-|-|-|BX|M|-|-|-|Retention exceptions need legal policy.
NJ-239|IN|IU|PP|-|NR|NR|-|C|PT-156|DELETE STORE|{securestore} (clears deleted user)|Reinstall/backup run on device pending.
NJ-240|IN|IU|PP|-|-|-|-|M|-|TRACK|{episodeedit}|Correction traceable via revisions.
NJ-241|IN|IU|P|P|-|-|-|C|PT-154|MIG|{episql} (isolation); {obsrmsql} section 7|Covered by SQL; staging two-user probe passed 2026-10-28.
NJ-242|IN|IU|P|P|-|-|-|C|-|MIG|{rlssql}; {userssql}|Covered by SQL.
NJ-243|IN|IU|P|P|-|-|-|C|-|MIG|{rlssql}|Covered by SQL.
NJ-244|IN|IU|P|P|-|-|-|C|-|MIG|{anonsql}|Covered by SQL; prod advisor confirmed 2026-10-27.
NJ-245|IN|IU|P|-|-|-|-|H|-|MIG|{userssql}|Audit evidence not recorded.
NJ-246|NONE|BX|-|-|-|-|-|L|-|-|-|No shareable links or attachments exist.
NJ-247|IN|IU|PP|-|-|-|-|H|-|MAIN|{sentry}|Representative failure paths not all covered.
NJ-248|IN|IU|N|-|-|-|-|M|-|COMM MSG|-|Flutter renders text, not markup; not asserted.
NJ-249|IN|IU|N|-|-|-|-|M|-|AI|-|AI rate limit exists server-side; not tested here.
NJ-250|OPS|IU|PP|-|-|-|-|H|-|CI|test/android_release_manifest_contract_test.dart|CI secret-redaction check exists; secret scan of builds not confirmed.
NJ-251|IN|IU|PP|-|NR|NR|-|M|-|DASH|test/dashboard_canonical_degraded_evidence_test.dart|Partly covered.
NJ-252|IN|BX|PP|-|NR|NR|-|M|-|TRACK|test/prediction_efficiency/|No defined budgets yet.
NJ-253|IN|IU|PP|-|NR|NR|-|M|-|TRACK|{acct}|Partly covered.
NJ-254|IN|IU|PP|-|NR|NR|-|H|-|PBOS|{pending}|Device run pending.
NJ-255|IN|IR|N|-|NR|NR|-|M|-|TRACK|-|A failed local write (storage full) is not distinguished from other save failures.
NJ-256|IN|IU|N|-|NR|NR|-|M|-|AI|-|Some lists use server limits; no defined retention or pagination policy for AI history.
NJ-257|NONE|BX|-|-|-|-|-|L|-|-|-|No uploads exist.
NJ-258|IN|IU|PP|-|NR|NR|-|M|-|NOTIF|test/dashboard_notification_tap_stream_test.dart|Partly covered.
NJ-259|IN|IU|PP|-|NR|NR|-|M|-|PBOS|{idem}|Device run pending.
NJ-260|IN|IU|PP|-|-|-|-|M|-|TRACK|{netfail}|Partly covered.
NJ-261|OPS|IU|PP|-|-|-|-|H|-|MIG TRACK|{endunk} (old builds quarantine unknown rows)|Compatibility policy not written down.
NJ-262|OPS|IU|P|P|-|-|-|H|-|MIG|{episql}; {obsrmsql}; {endunksql}|Staging runs recorded for 100000.
NJ-263|OPS|IU|N|-|-|-|-|H|-|MIG|-|Partial apply of 100000 on staging was handled (2026-10-29) but detection is manual.
NJ-264|OPS|IU|P|-|-|-|-|M|-|MIG|{obsrmsql} section 8; {endunksql} section 7|Re-run is a no-op.
NJ-265|OPS|BX|N|-|-|-|-|H|-|-|-|Rollback procedure not rehearsed.
NJ-266|OPS|IR|N|-|-|-|-|M|PT-196|-|-|No feature flags.
NJ-267|OPS|BX|N|-|-|-|-|H|-|-|-|Backup restore not exercised.
NJ-268|OPS|BX|N|-|-|-|BX|H|-|-|-|No content versioning.
NJ-269|OPS|BX|N|-|-|-|-|M|-|-|-|Monitoring runbook not written.
NJ-270|OPS|IU|N|-|-|-|-|M|-|-|-|This register records commits; automatic invalidation not built.
NJ-271|IN|IU|PP|-|NR|NR|-|M|-|NOTIF TRACK|{notifnav}|Partly covered.
NJ-272|NONE|BX|N|-|-|-|-|M|-|-|-|No purchases.
NJ-273|NONE|BX|-|-|-|-|-|M|-|AI|-|AI cannot change records; see NJ-174.
NJ-274|COND|IU|N|-|NR|NR|-|M|-|PREG|-|Not asserted.
NJ-275|DEFER|BX|N|-|-|-|-|L|-|-|-|Qadha deferred.
NJ-276|IN|IU|N|-|NR|NR|-|M|-|TRACK LOCALE|-|Not asserted.
NJ-277|NONE|BX|N|-|-|-|-|L|-|-|-|No purchases.
NJ-278|IN|IR|N|-|-|-|-|M|-|EXPORT|-|Export reads sections one after another with no snapshot or scope disclosure.
NJ-279|IN|IR|N|-|-|-|-|L|PT-045|-|-|Depends on split/merge.
NJ-280|NONE|BX|-|-|-|-|-|M|PT-196|AI|-|No remote guidance disable exists (PT-196).
NJ-281|OPS|BX|-|-|NR|-|-|H|-|-|-|Signed iPhone run needed.
NJ-282|OPS|BX|-|-|-|NR|-|H|-|-|-|Signed Android run needed.
NJ-283|OPS|BX|-|-|NR|NR|-|H|-|-|-|Signed-device run needed.
NJ-284|OPS|BX|-|-|NR|NR|-|M|-|-|-|Signed-device run needed.
NJ-285|OPS|BX|-|-|NR|NR|-|H|-|-|-|Signed-device run needed.
NJ-286|OPS|BX|-|-|NR|NR|-|M|-|-|-|Screen privacy policy undecided; device run needed.
NJ-287|NONE|BX|-|-|-|-|-|L|-|-|-|No purchases.
NJ-288|OPS|BX|-|-|NR|NR|-|H|-|-|-|Signed-device run needed.
NJ-289|OPS|BX|-|-|NR|NR|-|M|-|-|-|Signed-device run needed.
NJ-290|OPS|BX|-|-|NR|NR|-|M|-|-|-|Signed-device run needed.
NJ-291|IN|IU|PP|-|NR|NR|-|M|-|DASH CALC|{late}|Missing months not treated as observations; not asserted for months.
NJ-292|IN|IU|PP|-|-|-|BX|M|-|CALC|{calcsvc}|Clinical review pending.
NJ-293|IN|IU|N|-|NR|NR|-|H|PT-157|TRACK|-|Server is the source; unsynced limitation not shown.
NJ-294|OPS|BX|-|-|-|-|BX|M|-|-|-|Needs user comprehension sessions.
NJ-295|OPS|BX|-|-|-|-|BX|M|-|-|-|Needs usability sessions.
NJ-296|IN|IU|P|-|NR|NR|-|M|-|SIGNIN|{signup} (wording asks, never asserts delivery)|Open PR feat/signup-email-guidance.
NJ-297|OPS|IU|P|-|-|-|-|M|-|-|scripts/journey_register.py (fails on an unmapped id)|Scope decisions recorded in docs/journeys/NISWAH_LAUNCH_SCOPE.md.
NJ-298|OPS|IU|P|-|-|-|-|M|-|-|scripts/journey_register.py (each automated PASS names its assertion)|Ongoing discipline.
NJ-299|OPS|IU|P|-|-|-|-|M|-|-|docs/journeys/NISWAH_JOURNEY_VERIFICATION_REPORT.md|Blockers listed per row.
NJ-300|OPS|BX|-|-|-|-|-|C|-|-|-|Launch approval is rayan's; engineering completion is reported separately.
"""

COLUMNS = [
    "id", "section", "journey", "required_outcome", "scope", "status",
    "automated", "staging", "signed_iphone", "signed_android", "specialist",
    "automated_outcome_demonstrated", "severity", "linked_pt", "locations",
    "evidence", "gap_or_next_action",
]


def read_source() -> list[tuple[str, str, str, str]]:
    rows, section = [], ""
    for line in SOURCE_MD.read_text(encoding="utf-8").splitlines():
        if line.startswith("### "):
            section = line[4:].strip()
        m = re.match(r"^\| (NJ-\d{3}) \| (.+?) \| (.+?) \|$", line)
        if m:
            rows.append((m.group(1), section, m.group(2).strip(), m.group(3).strip()))
    return rows


def expand(text: str, table: dict[str, str]) -> str:
    return " ".join(table.get(tok, tok) for tok in text.split())


def build() -> str:
    source = read_source()
    ids = [r[0] for r in source]
    if len(ids) != 300 or len(set(ids)) != 300:
        sys.exit(f"source has {len(ids)} rows / {len(set(ids))} unique ids, expected 300")
    if ids != [f"NJ-{n:03d}" for n in range(1, 301)]:
        sys.exit("source ids are not NJ-001..NJ-300 in order")

    data: dict[str, list[str]] = {}
    for raw in ASSESSMENT.strip().splitlines():
        parts = [p.strip() for p in raw.split("|")]
        if len(parts) != 13:
            sys.exit(f"bad assessment line ({len(parts)} fields): {raw}")
        if parts[0] in data:
            sys.exit(f"duplicate assessment for {parts[0]}")
        data[parts[0]] = parts
    missing = [i for i in ids if i not in data]
    extra = [i for i in data if i not in ids]
    if missing or extra:
        sys.exit(f"unassessed: {missing}; unknown: {extra}")

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(COLUMNS)
    for nj, section, journey, outcome in source:
        (_, scope, status, auto, staging, ios, android, spec, sev, pt, locs,
         evidence, nxt) = data[nj]
        for value, table, name in (
            (scope, SCOPE, "scope"), (status, STATUS, "status"),
            (sev, SEVERITY, "severity"),
        ):
            if value not in table:
                sys.exit(f"{nj}: unknown {name} {value!r}")
        for value in (auto, staging, ios, android, spec):
            if value not in DIM:
                sys.exit(f"{nj}: unknown evidence value {value!r}")
        evidence_text = evidence.format(**T)
        if auto in ("P", "PP") and evidence_text == "-":
            sys.exit(f"{nj}: automated evidence claimed without naming it")
        if status == "V":
            needed = [d for d in (auto, staging, ios, android, spec) if d != "-"]
            if any(d != "P" for d in needed):
                sys.exit(f"{nj}: VERIFIED but not every required dimension passed")
        writer.writerow([
            nj, section, journey, outcome, SCOPE[scope], STATUS[status],
            DIM[auto], DIM[staging], DIM[ios], DIM[android], DIM[spec],
            "yes" if auto == "P" else "no", SEVERITY[sev],
            "" if pt == "-" else pt, "" if locs == "-" else expand(locs, L),
            "" if evidence_text == "-" else evidence_text, nxt,
        ])
    return out.getvalue()


def summary(text: str) -> str:
    rows = list(csv.DictReader(io.StringIO(text)))
    lines = []
    for label in STATUS.values():
        lines.append(f"{sum(r['status'] == label for r in rows):4d}  {label}")
    demo = sum(r["automated_outcome_demonstrated"] == "yes" for r in rows)
    lines.append(f"{demo:4d}  automated outcome demonstrated")
    return "\n".join(lines)


def main() -> None:
    text = build()
    if "--check" in sys.argv:
        current = CSV_OUT.read_text(encoding="utf-8") if CSV_OUT.exists() else ""
        if current != text:
            sys.exit(f"{CSV_OUT.relative_to(ROOT)} is stale; run scripts/journey_register.py")
        return
    CSV_OUT.parent.mkdir(parents=True, exist_ok=True)
    CSV_OUT.write_text(text, encoding="utf-8")
    print(summary(text))


if __name__ == "__main__":
    main()

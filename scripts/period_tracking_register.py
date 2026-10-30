#!/usr/bin/env python3
"""Builds docs/period-tracking/PERIOD_TRACKING_COVERAGE.csv.

The 200 acceptance cases (scenario and expected behavior) are read verbatim
from docs/period-tracking/PERIOD_TRACKING_200_CASES.md; this script never
rewrites them. The per-case assessment (steps, stored/UI result,
downstream effects, priority, locations, verification, status) lives in
ASSESSMENT below and is merged by PT id. The build fails if any of the 200
ids is missing, duplicated, or has an unknown status, so a case can never
silently disappear.

  python3 scripts/period_tracking_register.py          # write the CSV
  python3 scripts/period_tracking_register.py --check  # fail if stale
"""
from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES_MD = ROOT / "docs/period-tracking/PERIOD_TRACKING_200_CASES.md"
CSV_OUT = ROOT / "docs/period-tracking/PERIOD_TRACKING_COVERAGE.csv"

STATUSES = {
    "NOT ASSESSED",
    "IMPLEMENTATION REQUIRED",
    "IMPLEMENTED — UNVERIFIED",
    "VERIFIED",
    "BLOCKED — EXTERNAL EVIDENCE REQUIRED",
}
NA = "NOT ASSESSED"
REQ = "IMPLEMENTATION REQUIRED"
IMP = "IMPLEMENTED — UNVERIFIED"
VER = "VERIFIED"
BLK = "BLOCKED — EXTERNAL EVIDENCE REQUIRED"

# Location shorthands, expanded in the CSV.
L = {
    "SBS": "lib/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart",
    "DCS": "lib/features/cycle_tracking/presentation/widgets/daily_checkin_sheet.dart",
    "CS": "lib/features/cycle_tracking/presentation/widgets/correction_sheet.dart",
    "ODS": "lib/features/cycle_tracking/presentation/widgets/observation_detail_sheet.dart",
    "CORR": "lib/features/cycle_tracking/data/repositories/episode_correction_repository.dart",
    "EPS": "lib/features/cycle_tracking/presentation/widgets/episode_edit_sheet.dart",
    "ROUTER": "lib/features/cycle_tracking/presentation/widgets/log_day_entry_router.dart",
    "LOGSHEET": "lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart",
    "CAL": "lib/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart",
    "LEGCAL": "lib/features/cycle_tracking/presentation/widgets/cycle_calendar.dart",
    "REPO": "lib/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart",
    "PROJ": "lib/features/cycle_tracking/data/repositories/cycle_entries_projection.dart",
    "LOCALREPO": "lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart",
    "PBOS": "lib/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart",
    "ENT": "lib/features/cycle_tracking/domain/entities/bleeding_episode.dart",
    "CALC": "lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart",
    "CTRL": "lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart",
    "STATUS": "lib/features/cycle_tracking/domain/services/canonical_bleeding_status_resolver.dart",
    "ENGINE": "lib/features/cycle_tracking/domain/services/cycle_status_engine.dart",
    "MADHHAB": "lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart",
    "FIQHADP": "lib/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart",
    "SYMDEC": "lib/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart",
    "ONB": "lib/features/onboarding/presentation/screens/onboarding_screen.dart",
    "DASH": "lib/features/dashboard/presentation/screens/dashboard_screen.dart",
    "INS": "lib/features/insights/",
    "WELL": "lib/features/wellbeing/",
    "NOTIF": "lib/features/notifications/domain/services/notification_scheduler.dart",
    "NREFRESH": "lib/features/notifications/domain/services/notification_refresh_coordinator.dart",
    "PREG": "lib/features/pregnancy_profile/",
    "AICTX": "supabase/functions/_shared/ai_user_context.ts",
    "AICHAT": "lib/features/ai_assistant/",
    "EXPORT": "lib/features/legal/domain/data_export_builder.dart",
    "TZ": "lib/core/utils/device_timezone.dart",
    "AUTH": "lib/features/auth/",
    "MIG_MODEL": "supabase/migrations/20260917090000_bleeding_episode_model.sql",
    "MIG_WB": "supabase/migrations/20261018090000_bleeding_write_boundary_validation.sql",
    "MIG_ONB": "supabase/migrations/20261021100000_onboarding_server_hardening.sql",
    "MIG_EPI": "supabase/migrations/20261029100000_bleeding_episode_corrections.sql",
    "MIG_OBSRM": "supabase/migrations/20261029120000_bleeding_observation_removal.sql",
    "MIG_ENDUNK": "supabase/migrations/20261029130000_bleeding_episode_end_unknown.sql",
    "FIQHA": "lib/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart",
    "ODS": "lib/features/cycle_tracking/presentation/widgets/observation_detail_sheet.dart",
    "CORR": "lib/features/cycle_tracking/data/repositories/episode_correction_repository.dart",
    "PRAYER": "lib/features/prayer_tracking/",
    "REPORTS": "lib/features/doctor_report/ lib/features/fiqh_report/ lib/features/husband_report/",
    "MAIN": "lib/main.dart",
}

# Test shorthands (all paths relative to the repo root).
T = {
    "calendar": "test/canonical_calendar_screen_test.dart",
    "startsheet": "test/start_bleeding_sheet_test.dart",
    "correction": "test/correction_sheet_test.dart",
    "estimate": "test/cycle_prediction_estimate_test.dart",
    "concurrency": "test/period_tracking_concurrency_test.dart",
    "acctswitch": "test/cycle_repository_account_switch_regression_test.dart",
    "pending": "test/pending_bleeding_operation_store_test.dart",
    "syncbanner": "test/sync_status_banner_test.dart",
    "idem": "test/cycle_local_sync_idempotency_test.dart",
    "failures": "test/logging_sync_hardening/bleeding_sheet_failure_outcomes_test.dart",
    "reconcile": "test/logging_sync_hardening/reconcile_pending_operations_test.dart",
    "rpcsql": "test/logging_sync_hardening/sql/canonical_rpc_regression.sql",
    "episql": "test/security/bleeding_episode_corrections.sql",
    "obsrmsql": "test/security/bleeding_observation_removal.sql",
    "obsrm": "test/period_tracking/observation_remove_test.dart",
    "endunksql": "test/security/bleeding_episode_end_unknown.sql",
    "endunk": "test/period_tracking/end_unknown_test.dart",
    "resumed": "test/resumed_bleeding/resumed_bleeding_prediction_test.dart",
    "resumedfiqh": "test/resumed_bleeding/resumed_bleeding_fiqh_parity_test.dart",
    "dst": "test/screens_hardening/dst_day_counts_test.dart",
    "caldst": "test/screens_hardening/calendar_dst_and_empty_test.dart",
    "late": "test/screens_hardening/dashboard_late_period_ring_test.dart",
    "symptomsonly": "test/round2_hardening/symptoms_only_sheet_marker_test.dart",
    "symptomsbleed": "test/round2_hardening/symptoms_on_bleeding_days_test.dart",
    "routerpast": "test/round2_hardening/log_day_router_past_day_test.dart",
    "routing": "test/screens_hardening/bleeding_entry_routing_test.dart",
    "notifcopy": "test/pregnancy_notifications_hardening/notification_copy_and_feed_test.dart",
    "notifsched": "test/services/notification_scheduler_test.dart",
    "notifacct": "test/notification_account_transition_test.dart",
    "notiftz": "test/notification_timezone_test.dart",
    "chatacct": "test/notification_chat_account_safety_test.dart",
    "deletion": "test/account_deletion_resilience_test.dart",
    "deletionpending": "test/logging_sync_hardening/account_deletion_pending_ops_test.dart",
    "export": "test/data_export_resilience_test.dart",
    "rtl": "test/localization_ui_test.dart",
    "a11y": "test/accessibility_semantics_test.dart",
    "textscale": "test/accessibility_text_scaling_test.dart",
    "fiqhparity": "test/fiqh_hardening/fiqh_engine_hardening_test.dart",
    "aifiqh": "test/fiqh_hardening/ai_client_fiqh_state_test.dart",
    "redflag": "test/dr_niswah_red_flag_dual_state_test.dart",
    "aifail": "test/ai_malformed_response_test.dart",
    "onbanswers": "test/onboarding_server_hardening/onboarding_answers_test.dart",
    "onbui": "test/onboarding_ui_test.dart",
    "madhhabres": "test/madhhab_resolution_test.dart",
    "madhhabhist": "test/madhhab_history_resolver_test.dart",
    "legacyprov": "test/logging_sync_hardening/legacy_log_provenance_test.dart",
    "strict": "test/cycle_log_strict_parsing_test.dart",
    "projection": "test/cycle_entries_projection_test.dart",
    "preg": "test/pregnancy_notifications_hardening/pregnancy_tracking_ended_no_nifas_test.dart",
    "wellsplit": "test/wellbeing_period_split_test.dart",
    "propcal": "test/round2_properties/calendar_segment_properties_test.dart",
    "proppred": "test/round2_properties/prediction_properties_test.dart",
    "episodeedit": "test/period_tracking/episode_edit_test.dart",
}

DEVICE = "Signed iPhone and Android build run (PT-200 policy)"
SCHOLAR = "Scholar-approved per-madhhab specification"
CLINICAL = "Clinician-approved safety specification and wording"
QADHA = "Deferred by product decision 2026-10-29: period tracking before qadha automation; needs scholar-approved fasting-qadha spec"


def a(steps, stored, ui, downstream, prio, risk, locs, method, evidence, status, dep=""):
    return dict(
        steps=steps, stored=stored, ui=ui, downstream=downstream, priority=prio,
        risk=risk, locations=locs, method=method, evidence=evidence,
        status=status, dependency=dep,
    )


ASSESSMENT: dict[int, dict] = {}

# --- 1. First use and historical information -------------------------------
ASSESSMENT.update({
    1: a("Onboarding step 5: pick last start; answer 'No, it has stopped'; pick end.",
         "One ended bleeding_episodes row (start/end date_only, user_reported_historical) via record_onboarding_menstrual_history; closing flow=none observation on end date.",
         "Calendar picker for start then end; end choices before start disabled.",
         "Today ring shows completed history; Calendar marks days; prediction needs 2+ starts.",
         "P1", "Medium", "ONB MIG_ONB", "Widget + SQL", f"{T['onbanswers']}, {T['onbui']}", IMP,
         "Add assertion that the saved payload equals the picked dates."),
    2: a("Onboarding step 5: pick start; 'No, it has stopped'; 'I'm not sure exactly when'.",
         "record_onboarding_menstrual_history saves an ENDED episode with the known start, end_precision 'unknown', no end date, no end time and no closing entry; nothing about the end is invented. Contradictory answers are refused. For overlap rules it occupies only its start day; correct_episode_end gives it its first real end.",
         "Period editor shows 'end date not recorded' and offers 'Add end date'. Insights: 'Ended, end date not recorded'. Today and the Fiqh report: 'End date needed', no ruling while it is her most recent period.",
         "Predictions use its start as a cycle start and never a length; Calendar and the wellbeing split mark only the start day; fiqh gives no ruling until the end is added (decided by rayan 2026-10-29).",
         "P2", "Medium (data loss of a known fact)", "ONB MIG_ENDUNK CALC FIQHA EPS", "SQL + widget + unit", f"{T['endunksql']} (sections 1-7), {T['onbanswers']} ('R2-ONB-3 / PT-002: ... saves the known start as an ended period with an unknown end'), {T['endunk']}, {T['episodeedit']} ('PT-002: a period whose end is unknown says so and lets her add the end')", VER,
         "Applies once migration 20261029130000 is run per environment. The Calendar's start-day-only marking and the Today copy are covered by code reading, not a dedicated test. An app build older than this change quarantines such a row (shows 'Unable to verify') rather than misreading it."),
    3: a("Onboarding/backfill: she only remembers 'about two weeks ago'.",
         "Expected: start stored with approximate-date precision. Actual: precision enum is exact_time/approximate_time/date_only only; an approximate date is stored as date_only (looks exact).",
         "Should say the estimate is wider because the date is approximate.",
         "Predictions should widen the range / exclude from learning.",
         "P2", "Medium (false precision)", "ONB SBS MIG_MODEL CALC", "Unit + SQL", "Code reading: bleeding_episodes_precision_check", REQ,
         "Needs approximate_date precision + prediction policy."),
    4: a("New account, onboarding: 'I don't remember' / no history.",
         "No episode, no baseline; nothing fabricated.",
         "Today shows 'no history' state with Start action available.",
         "No predictions, no reminders.",
         "P1", "High if violated", "ONB DASH STATUS", "Widget", f"{T['estimate']} ('no logged cycle and no estimate: nothing'), {T['calendar']} ('clean empty')", VER),
    5: a("Onboarding step 6: accept 'improve predictions', enter usual duration only.",
         "cycle_baselines row (USER_REPORTED_ESTIMATE), never an episode.",
         "Calendar shows a labeled estimate summary, never on a day.",
         "Used as a prediction prior only; labeled 'Based on the estimate you gave us'.",
         "P2", "Medium", "ONB CALC CAL", "Unit + widget", f"{T['estimate']} ('stated period length is used only when none is logged'), {T['calendar']} ('a real baseline estimate is shown as its own labeled summary')", VER),
    6: a("Onboarding step 6 cycle length: tap 'لست متأكدة'.",
         "No cycle-length baseline stored.",
         "«لست متأكدة» button present; onboarding continues.",
         "Prediction falls back to observed history only.",
         "P2", "Low", "ONB", "Widget", f"{T['onbui']}", IMP, "Add explicit widget assertion for the cycle-length skip."),
    7: a("User reports irregular cycles.",
         "Expected: an explicit 'irregular' context. Actual: no irregular-cycle field exists; prediction relies on observed variability only.",
         "Should avoid a regular-cycle assumption in copy.",
         "Prediction spread widens only after variable cycles are observed.",
         "P2", "Medium", "ONB CALC", "Unit", "Code reading: no irregular flag in ONB/cycle_baselines", REQ,
         "Product decision on what an 'irregular' answer changes."),
    8: a("Add several past periods one after another.",
         "Each period a separate ended episode; server rejects overlaps (start on/before an ended episode's end).",
         "Expected efficient multi-entry with duplicate/overlap check. Actual: one period at a time via Start then End sheets.",
         "Calendar/predictions recompute after each.",
         "P2", "Medium", "SBS ROUTER MIG_WB", "SQL + widget", f"{T['rpcsql']} (overlap rejection), {T['routerpast']}", IMP,
         "No dedicated multi-period entry flow; overlap check verified server-side."),
    9: a("Import from another app.", "No import feature exists.", "None.", "None.", "P3", "Low", "(none)", "-", "Code reading: no import path", REQ,
         "Product decision: which source format; out of launch scope unless requested."),
    10: a("Skip all optional onboarding questions.", "Only required profile; no baseline.", "Core tracking available.", "No predictions until data.",
          "P1", "Medium", "ONB", "Widget", f"{T['onbui']}", IMP, "Add test: skip path then Start bleeding works."),
})

# --- 2. Recording the start ---------------------------------------------------
ASSESSMENT.update({
    11: a("Today → Start bleeding → Today chip → flow → Save.",
          "start_bleeding_episode: open episode + first observation (user_observed).",
          "Prominent Start action on Today; immediate 'Bleeding recorded, Day 1'.",
          "Calendar, Insights, reminders consent prompt.",
          "P0", "High", "SBS DASH REPO", "Widget + SQL", f"{T['startsheet']}, {T['rpcsql']}", VER),
    12: a("Start sheet → Yesterday chip.", "start_date=yesterday, start_source=user_reported_historical (server-derived).", "One extra tap.", "Same as PT-011.",
          "P1", "Medium", "SBS MIG_WB", "Widget + SQL", f"{T['startsheet']}, {T['rpcsql']}", IMP, "Assert Yesterday chip path persists yesterday."),
    13: a("Calendar → tap a day weeks ago → Bleeding.", "Historical open episode (or rejected if it overlaps an ended one).", "Router opens Start sheet pre-set to that day.", "Recalculation of calendar and predictions.",
          "P1", "Medium", "ROUTER SBS", "Widget", f"{T['routerpast']}", VER),
    14: a("Try a future day.", "Rejected by date picker and by server (local today from utc offset).", "Future days offer no bleeding action; predicted days are labeled predictions.", "None.",
          "P0", "High", "ROUTER SBS MIG_WB", "Widget + SQL", f"{T['calendar']} ('a future day never offers to add or correct'), {T['rpcsql']}", VER),
    15: a("She knows the exact time.", "Server accepts exact_time + start_time + IANA zone; the sheet never offers a time.", "Expected optional time field. Actual: date only.", "Fiqh boundary cases (PT-113) need time.",
          "P2", "Medium", "SBS MIG_WB TZ", "Widget + SQL", "Code reading: SBS has no time picker", REQ),
    16: a("Date-only start.", "start_precision=date_only, start_time NULL (DB check enforces).", "No time shown.", "Day math uses calendar dates only.",
          "P0", "High", "SBS MIG_MODEL", "SQL", f"{T['rpcsql']}", VER),
    17: a("Remembers 'morning'.", "Schema supports approximate_time but requires a timestamp; no part-of-day field.", "Not offered.", "-",
          "P3", "Low", "SBS MIG_MODEL", "-", "Code reading", REQ, "Design part-of-day storage without inventing a timestamp."),
    18: a("Start sheet flow question → 'I'm not sure'.", "Observation flow=uncertain; never projected as bleeding.", "Selectable 'I'm not sure'.", "Fiqh/predictions treat as uncertain.",
          "P1", "Medium", "SBS PROJ", "Widget", f"{T['startsheet']} (\"I'm not sure\" is a real, selectable answer)", VER),
    19: a("Open episode exists; tap Bleeding on a day.", "Router routes to today's check-in / backfill on the open episode; DB one-open-per-user index.", "No second episode offered.", "None.",
          "P1", "High", "ROUTER MIG_MODEL", "Widget", f"{T['routing']}, {T['routerpast']}", VER),
    20: a("Double-tap Save.", "client_operation_id idempotency; Save disabled while saving.", "One saved state.", "None.",
          "P0", "High", "SBS DCS PBOS MIG_WB", "Unit + SQL", f"{T['pending']} ('saving the same operationId twice replaces'), {T['rpcsql']}", VER),
})

# --- 3. End and observed purity -----------------------------------------------
ASSESSMENT.update({
    21: a("End sheet → Today.", "end_bleeding_episode: closing flow=none observation then lifecycle ended.", "Episode shows as ended.", "Reminders cancelled; prediction learns the length.",
          "P0", "High", "SBS MIG_WB", "Widget + SQL", f"{T['startsheet']}, {T['rpcsql']}", VER),
    22: a("End sheet → earlier date.", "end_date earlier; rejected if bleeding recorded after it.", "Earlier dates selectable down to the start.", "Same as PT-021.",
          "P1", "Medium", "SBS MIG_WB", "SQL", f"{T['rpcsql']}", VER),
    23: a("End date before start.", "Rejected (DB check + RPC).", "Choices before the start are disabled, not hidden; expected an explanation beside the field.", "None.",
          "P1", "Medium", "SBS MIG_MODEL", "Widget", f"{T['startsheet']} ('the Yesterday chip is disabled')", IMP, "Add visible reason text for disabled dates."),
    24: a("Start and end on the same date.", "Allowed: end_date >= start_date.", "Saved as recorded.", "Length computed honestly.",
          "P2", "Low", "MIG_MODEL", "SQL", "Constraint bleeding_episodes_end_after_start_check", IMP, "Add SQL assertion."),
    25: a("Never marks the end.", "Episode stays open; never auto-ended.", "Missed check-in banner offers 'Add it', never forces.", "Prediction does not learn a length.",
          "P0", "High", "DASH MIG_MODEL", "Code + widget", "Contract §3 (never auto-ended); no auto-end code path", IMP, "Add regression test that time passing never ends an episode."),
    26: a("Predicted end passes while open.", "Nothing changes in storage.", "Expected gentle prompt; actual: missed check-in banner + optional reminder.", "-",
          "P2", "Medium", "DASH NREFRESH", "Widget", "Code reading", IMP),
    27: a("Ends the period, realises it was a mistake: tap Undo on the 'Period ended.' snackbar, or later open the period on Calendar → 'Edit this period' → 'I'm still bleeding'.",
          "reopen_episode: closing observation archived (bleeding_observations_archive) and tombstoned, episode end cleared, bleeding_episode_revisions row (action=reopen) keeps before/after state. A queued replay of the same end raises NW410 and is dropped from the queue, never re-ending it.",
          "Undo action on the end snackbar; 'I'm still bleeding' offered only on her latest ended period when nothing is open. Online only: offline keeps the sheet open and says nothing was changed.",
          "Today shows the period as ongoing again; Calendar, predictions and fiqh recompute from the reopened episode; reminders refresh on reload.",
          "P0", "High", "SBS EPS REPO MIG_EPI", "SQL + widget", f"{T['episql']} (section 5), {T['episodeedit']} ('PT-027: I'm still bleeding is offered only for her latest...', 'a queued end replayed after she undid that end is dropped')", VER,
          "Applies once migration 20261029100000 is run per environment (rayan, staging first)."),
    28: a("Unsure when it ended.", "end precision date_only only; 'I'm not sure' marks continuation uncertain while open.", "Uncertain continuation offered.", "-",
          "P2", "Medium", "DCS MIG_MODEL", "Widget", "Code reading", IMP),
    29: a("Record 'no bleeding' (observed purity).", "flow=none observation; fiqh state computed separately, never stored.", "Shown as 'no bleeding', not as a ruling.", "Fiqh engine reads it as evidence only.",
          "P1", "High", "DCS FIQHADP ENGINE", "Widget + unit", f"{T['calendar']} ('explicit no bleeding observation is announced distinctly')", VER),
    30: a("Purity then bleeding at conflicting times.", "Both stored; end rejected if bleeding after it.", "Expected timeline review prompt; actual: deterministic rejection message.", "-",
          "P2", "Medium", "MIG_WB SBS", "SQL", f"{T['rpcsql']}", IMP),
})

# --- 4. Flow, spotting, daily observations ---------------------------------
ASSESSMENT.update({
    31: a("Pick light/medium/heavy.", "flow enum.", "Labels Light/Medium/Heavy (خفيف/متوسط/غزير).", "-", "P1", "Low", "SBS DCS", "Widget", f"{T['correction']}", VER),
    32: a("Second check-in same day with new flow.", "New observation row; same episode.", "-", "-", "P1", "Medium", "DCS", "SQL", "Contract D2 live proof", IMP),
    33: a("Several observations one day.", "Separate rows with observed_time when given.", "Calendar detail lists all, oldest first.", "-", "P2", "Low", "ODS", "Widget", f"{T['calendar']} ('three independent same-day observations')", VER),
    34: a("Record spotting only.", "flow=spotting observation inside an episode; no 'spotting outside an episode' record.", "-", "Fiqh treats as evidence only.", "P1", "Medium", "SBS DCS", "Code", "Code reading: spotting can only be recorded inside an episode", IMP, "Spotting with no episode starts one; needs product decision."),
    35: a("Spotting then heavier.", "Both observations kept.", "-", "-", "P2", "Low", "DCS", "SQL", "Contract D2", IMP),
    36: a("Spotting after end.", "Ended episode rejects new facts; spotting after end must start a new episode.", "-", "-", "P2", "Medium", "MIG_WB", "SQL", f"{T['rpcsql']}", IMP),
    37: a("Brown discharge.", "No colour field; free-text note only.", "-", "-", "P3", "Low", "LOGSHEET", "-", "Code reading", REQ, "Needs agreed colour vocabulary; no auto-classification."),
    38: a("Explicit 'no bleeding today'.", "flow=none vs no row.", "Distinct labels.", "-", "P0", "High", "CAL DCS", "Widget", f"{T['calendar']} ('all four states remain distinct')", VER),
    39: a("Change yesterday's flow.", "correct_observation supersedes; history kept.", "Revision chain visible.", "Projection updated.", "P1", "Medium", "CS MIG_WB", "Widget + SQL", f"{T['calendar']} ('a corrected day shows the full revision chain'), {T['rpcsql']}", VER),
    40: a("Only start/end.", "Start and End sheets work alone.", "-", "-", "P2", "Low", "SBS", "Widget", f"{T['startsheet']}", VER),
})

# --- 5. Interrupted and ambiguous -------------------------------------------
ASSESSMENT.update({
    41: a("Bleeding stops a day then resumes.", "Short gap after an ended episode: new start <15d is prediction-uncertain; all dates kept.", "-", "Fiqh unchanged until scholar spec.", "P1", "High", "CALC ENGINE", "Unit", f"{T['resumed']}, {T['resumedfiqh']}", VER, SCHOLAR),
    42: a("Several gaps.", "Each interval preserved.", "Calendar segments.", "-", "P2", "Medium", "CAL", "Property", f"{T['propcal']}", IMP),
    43: a("Spotting in a gap.", "Needs an episode; see PT-034.", "-", "-", "P2", "Medium", "-", "-", "-", IMP),
    44: a("New bleeding shortly after.", "Prediction-only uncertain start; no auto merge or new cycle.", "-", "-", "P1", "High", "CALC", "Unit", f"{T['resumed']}", VER, SCHOLAR),
    45: a("Split an episode.", "Not supported.", "-", "-", "P2", "Medium", "EPS MIG_EPI", "-", "Code reading", REQ),
    46: a("Merge episodes.", "Not supported.", "-", "-", "P2", "Medium", "EPS MIG_EPI", "-", "Code reading", REQ),
    47: a("Unsure if episodes belong together.", "Uncertain start excluded from learning.", "-", "-", "P2", "Medium", "CALC", "Unit", f"{T['resumed']}", IMP),
    48: a("Two records same interval.", "Server rejects overlapping starts; legacy duplicates possible.", "-", "-", "P2", "Medium", "MIG_WB", "SQL", f"{T['rpcsql']}", IMP),
    49: a("Classification disagrees.", "Fiqh never stored; she can correct observations.", "Reasoning shown in fiqh report.", "-", "P2", "Medium", "ENGINE CS", "-", "-", IMP, SCHOLAR),
    50: a("New info changes classification.", "Recomputed on read; observation history kept.", "No explanation of the change.", "-", "P2", "Medium", "ENGINE", "-", "-", IMP),
})

# --- 6. Editing, deleting, correcting ---------------------------------------
ASSESSMENT.update({
    51: a("Calendar → tap a day of the period → 'Edit this period' → 'Change start date' → pick the new day (asks the flow when that day has no entry) → Save.",
          "correct_episode_start: new start observation; observations before the new start are archived only after she confirms (NW422 with the count). Days between the old and new start stay unrecorded, never 'no bleeding'. Revision row keeps before/after.",
          "Preview dialog names how many entries would be removed; refusals (overlap, future day) explained in her words.",
          "Calendar, Today, predictions and fiqh recompute from the corrected episode.",
          "P0", "High", "EPS REPO MIG_EPI", "SQL + widget", f"{T['episql']} (sections 1-2), {T['episodeedit']} ('PT-051: moving the start to a day with no entry asks for that day's flow')", VER,
          "Applies once migration 20261029100000 is run per environment."),
    52: a("Calendar → period → 'Edit this period' → 'Change end date' → pick the first clean day → Save (confirm if entries would be removed).",
          "correct_episode_end: closing observation archived and replaced; bleeding observations on/after the new end archived only after confirmation; revision row kept.",
          "Preview before removing entries; the device mirror is brought in line after the server confirms.",
          "Period length, predictions and fiqh recompute.",
          "P0", "High", "EPS REPO MIG_EPI", "SQL + widget", f"{T['episql']} (section 4), {T['episodeedit']} ('PT-052: a saved end correction sends her revision token...', 'PT-052: an earlier end over recorded bleeding is previewed...')", VER,
          "Applies once migration 20261029100000 is run per environment."),
    53: a("Change a start/end date to a day in another month via the editor's date picker.", "Same RPCs as PT-051/052; dates are plain dates, no month boundary logic.", "Picker allows any past day within limits.", "Calendar months both recompute on reload.", "P1", "Medium", "EPS CAL", "Widget", f"{T['episodeedit']}", IMP, "Add an explicit cross-month SQL case."),
    54: a("Move a start earlier or an end later into another period.", "Server refuses with an overlap error; nothing changes.", "Refusal explained in her words; sheet stays open.", "-", "P0", "High", "EPS MIG_EPI", "SQL + widget", f"{T['episql']} (section 3), {T['episodeedit']} ('PT-054: an overlap refusal is a rejection, not offline', 'a refusal (overlap) is explained in her words')", VER),
    55: a("Calendar → day → 'Delete this entry' → confirm.", "remove_observation archives that entry with its whole correction chain (never rewritten), tombstones its operations, deletes the cycle_entries mirror row and keeps a revision; the rest of the period is untouched. The period's start entry and an ended period's closing entry are refused (NW423) and changed through 'Edit this period' instead. Stale revision token refused (NW409).", "Confirmation says only this day becomes not recorded; then 'Entry deleted.' with Undo (restore_observation puts back the same ids; refused if a newer entry covers that day). Offline says nothing changed.", "Calendar and predictions recompute on reload via onEpisodeChanged.", "P1", "Medium", "ODS CORR MIG_OBSRM", "SQL + widget", f"{T['obsrmsql']} (sections 1-8), {T['obsrm']} ('a middle day: confirm, delete, then Undo restores it', 'the start day and the end of an ended period are protected', 'offline: she is told nothing changed, and the sheet stays')", VER, "Applies once migration 20261029120000 is run per environment; not yet on staging or production."),
    56: a("Calendar → period → 'Edit this period' → 'Remove this period' → confirm.", "remove_episode: episode and all its observations moved to the archive tables, operations tombstoned, cycle_entries projection rows deleted; revision row kept.", "Confirmation dialog explains what changes; then a snackbar with Undo.", "Calendar/Today/predictions/fiqh no longer use the period; reminders refresh on reload.", "P0", "High", "EPS REPO MIG_EPI", "SQL + widget", f"{T['episql']} (section 6), {T['episodeedit']} ('PT-056: removing a period deletes every mirrored entry...', 'PT-056/PT-057: removing explains what changes...')", VER, "Applies once migration 20261029100000 is run per environment."),
    57: a("Tap Undo on the 'Period removed' snackbar.", "restore_episode re-inserts the same ids from the archive; refused if a newer period now overlaps.", "Undo on the snackbar.", "Everything recomputes as before removal.", "P1", "Medium", "EPS MIG_EPI", "SQL + widget", f"{T['episql']} (sections 6-7), {T['episodeedit']} ('PT-056/PT-057: removing explains what changes, needs...')", VER, "No 'recently removed' list screen yet (getRemovedEpisodes exists in the repository)."),
    58: a("Edit a record with symptoms.", "Correction carries symptoms only if passed; legacy symptoms rows separate.", "-", "-", "P2", "Medium", "CS", "Unit", f"{T['symptomsbleed']}", IMP),
    59: a("Correct several episodes.", "Recalc from current state on every read.", "-", "-", "P2", "Low", "CALC", "-", "-", IMP),
    60: a("Edit form opened, the period changed on another device, then Save.", "Episode edits send updated_at as a revision token; a mismatch raises NW409 and nothing changes. Observation corrections keep their NW409 tip check.", "'This period was changed on another device' message; she reloads.", "-", "P1", "High", "EPS CS MIG_EPI MIG_WB", "SQL + unit", f"{T['episql']} (section 8), {T['rpcsql']}, {T['episodeedit']} ('PT-060/PT-148: a change made on another device first is reported')", VER),
})

# --- 7. Symptoms and wellbeing ----------------------------------------------
ASSESSMENT.update({
    61: a("Cramps, no bleeding.", "Symptoms-only legacy row with flow:unrecorded marker.", "-", "Never starts a period.", "P1", "Medium", "LOGSHEET", "Widget", f"{T['symptomsonly']}", VER),
    62: a("Symptoms after end.", "Stored on their own date.", "-", "-", "P2", "Low", "LOGSHEET", "Widget", f"{T['symptomsonly']}", IMP),
    63: a("Mood/energy/sleep.", "wellbeing_logs.", "Agreed accents.", "Insights split by period/no-period.", "P2", "Low", "WELL", "Widget", f"{T['wellsplit']}", VER),
    64: a("Several symptoms.", "Multi-select chips.", "-", "-", "P2", "Low", "LOGSHEET", "-", "-", IMP),
    65: a("Change severity.", "Latest state.", "-", "-", "P3", "Low", "LOGSHEET", "-", "-", IMP),
    66: a("Private note.", "Encrypted locally; synced to own row.", "Optional.", "Excluded from telemetry.", "P2", "Medium", "LOGSHEET", "-", "-", IMP),
    67: a("Choose tracked symptoms.", "No customization.", "-", "-", "P3", "Low", "-", "-", "-", REQ),
    68: a("Skip check-in.", "Nothing stored.", "-", "Not counted as 'no symptoms'.", "P1", "High", "WELL", "-", "-", IMP),
    69: a("Repeated taps.", "Toggle chips; one row per day.", "-", "-", "P2", "Low", "LOGSHEET", "-", "-", IMP),
    70: a("Symptom patterns.", "Insights wording.", "-", "-", "P2", "Medium", "INS", "-", "-", IMP, CLINICAL),
})

# --- 8. Predictions and uncertainty -----------------------------------------
ASSESSMENT.update({
    71: a("One recorded episode.", "-", "'Learning your cycle'; no average.", "No reminder from estimate alone.", "P1", "High", "DASH CALC", "Unit + widget", f"{T['estimate']} ('one logged start predicts from the estimate, but no statistic is fabricated')", VER),
    72: a("Consistent cycles.", "-", "Range, e.g. 2 days early to 3 late.", "-", "P1", "Medium", "CALC", "Unit", f"{T['estimate']} ('regular history: 2 days early to 3 days late')", VER),
    73: a("Variable cycles.", "-", "Wider range.", "-", "P1", "Medium", "CALC", "Property", f"{T['proppred']}", IMP),
    74: a("Earlier than estimated.", "Observation recorded; estimate recomputed.", "-", "-", "P1", "Medium", "CALC", "-", "-", IMP),
    75: a("Later than estimated.", "Predictions are not stored, so nothing is rewritten; also nothing kept for evaluation.", "-", "-", "P2", "Medium", "CALC", "-", "-", IMP, "See PT-080 for versioned history."),
    76: a("Predicted date passes.", "-", "Late period never drawn as predicted bleeding; no record ≠ no bleeding.", "-", "P1", "High", "CAL CALC", "Widget + unit", f"{T['calendar']} ('a clearly late period is never drawn as predicted bleeding'), {T['estimate']} ('clearly late: no range')", VER),
    77: a("Unusual episode.", "Outlier policy documented.", "-", "-", "P2", "Medium", "CALC", "Unit", "docs/cycle-prediction-model.md, test/cycle_calculation_service_test.dart", IMP),
    78: a("Remove a past period, then look at Today and Insights.", "remove_episode archives it and the cycle_entries mirror rows are deleted (PT-056). Returning from the Calendar reloads the view model and the canonical status, so predictions are computed from the remaining periods only.", "-", "Predictions and fiqh state recompute from what remains.", "P2", "Medium", "CALC DASH", "Code reading", "lib/features/dashboard/presentation/screens/dashboard_screen.dart (_openCanonicalCalendar reloads on return); " + T['episodeedit'] + " (PT-056 mirror deletion)", IMP, "No test yet asserts the prediction itself changes after a removal."),
    79: a("No period history (or too little) and she opens Insights.", "Nothing stored; no prediction computed.", "Expected-period card shows «لا تتوفر بيانات كافية للتوقع» / 'Not enough data for a prediction' and no date. Today shows no next-period line at all.", "No reminders scheduled from a missing prediction.", "P2", "Low", "INS DASH", "Widget", "test/period_tracking/prediction_no_data_test.dart (ar + en)", VER),
    80: a("Algorithm change.", "No prediction versioning.", "-", "-", "P3", "Medium", "CALC", "-", "-", REQ),
})

# --- 9. Life stages ----------------------------------------------------------
ASSESSMENT.update({
    81: a("Recently started menstruating.", "No age-specific path.", "-", "-", "P3", "Medium", "-", "-", "-", BLK, CLINICAL),
    82: a("Pregnancy possibility.", "No reviewed pathway.", "-", "-", "P2", "Medium", "-", "-", "-", BLK, CLINICAL),
    83: a("Confirmed pregnancy.", "Pregnancy profile; cycle reminders withheld.", "-", "Predictions/reminders off.", "P1", "High", "PREG NOTIF", "Unit", f"{T['notifsched']}", IMP),
    84: a("Bleeding in pregnancy.", "Health-safety pathway not reviewed.", "-", "-", "P1", "High", "PREG AICHAT", "-", "-", BLK, CLINICAL),
    85: a("Postpartum.", "Nifas mode; no ordinary cycle assumption.", "-", "-", "P1", "High", "PREG", "Unit", f"{T['preg']}", IMP, SCHOLAR),
    86: a("Breastfeeding, no periods.", "No breastfeeding state.", "-", "-", "P2", "Medium", "-", "-", "-", REQ, CLINICAL),
    87: a("Periods resume while breastfeeding.", "-", "-", "-", "P3", "Medium", "-", "-", "-", REQ, CLINICAL),
    88: a("Pregnancy loss.", "Pregnancy end without birth never starts nifas.", "-", "-", "P1", "High", "PREG", "Unit", f"{T['preg']}", BLK, CLINICAL + "; " + SCHOLAR),
    89: a("Perimenopause.", "No state.", "-", "-", "P3", "Medium", "-", "-", "-", REQ, CLINICAL),
    90: a("Contraception change.", "No state.", "-", "-", "P3", "Medium", "-", "-", "-", REQ, CLINICAL),
})

# --- 10. Health safety --------------------------------------------------------
RF = "lib/features/ai_assistant/domain/services/dr_niswah_red_flags.dart"
SAFETY_NOW = ("Today the only safety path is DrNiswahRedFlags: a keyword check on Dr Niswah chat messages that shows a fixed "
              "'contact your doctor or emergency services now' banner independently of the model. Tracking screens have no safety questions.")
ASSESSMENT.update({
    91: a("Tells Dr Niswah (or logs) bleeding she finds concerning.", "Nothing stored beyond the chat message; tracking records unchanged.", SAFETY_NOW + " Any message containing 'bleeding'/'نزيف' shows the urgent banner, which may over-escalate an ordinary period question.",
          "None on Calendar/Today/predictions/fiqh.", "P1", "High", f"{RF} AICHAT", "Unit + clinician review", f"{T['redflag']}", BLK, CLINICAL),
    92: a("Reports severe pain in chat.", "Chat only.", SAFETY_NOW + " 'severe pain'/'ألم شديد' triggers the banner; there is no reviewed follow-up question set.", "None.", "P1", "High", f"{RF} AICHAT", "Unit + clinician review", f"{T['redflag']}", BLK, CLINICAL),
    93: a("Reports dizziness or fainting with bleeding.", "Chat only.", "Dizziness/fainting are not in the keyword list; only the word 'bleeding' triggers the banner. No reviewed urgency pathway.", "None.", "P1", "High", f"{RF} AICHAT", "Clinician review", f"{T['redflag']}", BLK, CLINICAL),
    94: a("Bleeding continues for many days (tracked or in chat).", "Episode stays open; never auto-ended (invariant).", "No prolonged-bleeding message: the threshold is a clinical decision the app must not invent.", "Fiqh may show istihadah per madhhab rules; no medical message.", "P1", "High", "DASH ENGINE AICHAT", "Clinician review", "-", BLK, CLINICAL),
    95: a("Her period differs from her usual pattern.", "Observations stored as recorded.", "No 'unusual change' message; what counts as unusual is a clinical decision.", "Predictions widen with variability.", "P1", "High", "CALC AICHAT", "Clinician review", "-", BLK, CLINICAL),
    96: a("Gives partial safety information in chat.", "Chat only.", "No reviewed focused-question flow; the banner shows on any keyword match regardless of completeness.", "None.", "P1", "High", f"{RF} AICHAT", "Clinician review", f"{T['redflag']}", BLK, CLINICAL),
    97: a("Dismisses the urgent banner.", "Chat only.", "Banner is per message; it is not repeated as a blocking prompt.", "None.", "P1", "High", f"{RF} AICHAT", "Clinician review", f"{T['redflag']}", BLK, CLINICAL),
    98: a("Reports the same concern again later.", "Chat only.", "Each message is checked afresh by the keyword rule; no stored 'already handled' status.", "None.", "P1", "High", f"{RF} AICHAT", "Clinician review", f"{T['redflag']}", BLK, CLINICAL),
    99: a("AI or guidance service is down when she reports a concern.", "Chat only.", "The keyword banner runs on device before and independently of the model call, so it still shows. Approved fallback wording is still needed.", "None.", "P1", "High", f"{RF} AICHAT", "Unit + clinician review", f"{T['redflag']}, {T['aifail']}", BLK, CLINICAL),
    100: a("Asks whether tracking proves she is healthy.", "-", "Insights/prediction copy labels estimates; there is no reviewed statement of the limits of tracking.", "None.", "P2", "Medium", "AICHAT INS", "Clinician review", "-", BLK, CLINICAL),
})

# --- 11. Fiqh -----------------------------------------------------------------
ASSESSMENT.update({
    101: a("Madhhab selected in settings; she opens Today during bleeding.", "Observations only; fiqh state computed on read by the madhhab evaluator, never stored.", "Today's prayer card shows the computed state. The basis shown is the madhhab name; the rules themselves are not scholar-approved.", "Today prayer card, fiqh report, AI context.", "P1", "High", "ENGINE MADHHAB FIQHADP DASH", "Unit + scholar review", f"{T['fiqhparity']}, {T['madhhabres']}", BLK, SCHOLAR),
    102: a("No madhhab selected; she starts and ends a period.", "Tracking writes take no madhhab argument; nothing is assigned invisibly.", "Tracking works; fiqh shows 'Select your Madhhab' / «يلزم اختيار المذهب» rather than a ruling.", "Fiqh unresolved; predictions and Calendar unaffected.", "P0", "High", "SBS DCS ENGINE DASH", "Grep + unit", f"{T['madhhabres']}", IMP, "Add explicit test that Start works with madhhab unset."),
    103: a("Changes madhhab in settings.", "Observations untouched; madhhab history kept (madhhab_history_resolver) so past days resolve with the madhhab in force then.", "Interpretations recompute on read; no review prompt of affected days.", "Fiqh report, Today.", "P1", "High", "MADHHAB lib/core/preferences/madhhab_history_resolver.dart", "Unit + scholar review", f"{T['madhhabhist']}", BLK, SCHOLAR),
    104: a("Asks 'Can I pray?' with too little recorded.", "-", "Today shows 'Not enough history yet' / «لا يوجد سجل كافٍ بعد», never 'Salah is obligatory'. AI receives the same unresolved state.", "AI context.", "P1", "High", "DASH ENGINE AICTX", "Widget + scholar review", f"{T['aifiqh']}, test/parity_today_stepper_consistency_test.dart", BLK, SCHOLAR),
    105: a("Bleeding stops then returns.", "Resumed bleeding stays in the same episode by observation; no universal gap rule is applied in storage.", "Fiqh shows a case-specific review state where rules are not approved.", "Fiqh, predictions (resumed-bleeding tests).", "P1", "High", "ENGINE MADHHAB", "Unit + scholar review", f"{T['resumedfiqh']}", BLK, SCHOLAR),
    106: a("Knowledge base has a source but no scholar approval.", "kb items carry human_review_status (NOT_REVIEWED by default).", "Dr Niswah is told the content is evidence-verified only, not reviewed.", "AI answers.", "P1", "High", "supabase/functions/_shared/kb_retrieval.ts", "Unit + scholar review", "supabase/functions/_shared/kb_retrieval.test.ts", BLK, SCHOLAR),
    107: a("A rule is revised after review.", "Observations are never rewritten; interpretations are computed on read, so a rule change applies on next read.", "No notice of which past days changed.", "Fiqh report.", "P1", "High", "ENGINE", "Scholar review", "-", BLK, SCHOLAR),
    108: a("Disagrees with a fiqh classification.", "She can correct the observation (correction sheet / period editor); the interpretation itself is not editable.", "No 'request review' path.", "-", "P1", "High", "CS EPS ENGINE", "Scholar review", "-", BLK, SCHOLAR),
    109: a("AI answer contradicts the deterministic state.", "AI has no write path; records never change from chat.", "The client's deterministic fiqh state is passed to the server, which accepts only real engine values and only explains it, never recomputes it (fiqh_state_guard.ts). No visible contradiction flag.", "-", "P1", "High", "AICTX AICHAT", "Unit + scholar review", f"{T['aifiqh']}", BLK, SCHOLAR),
    110: a("Fiqh evaluation cannot run (no approved rule or unreadable evidence).", "Tracking writes unaffected.", "'Unable to verify' / «تعذر التحقق» state; tracking stays available.", "-", "P1", "High", "ENGINE DASH", "Unit", f"{T['fiqhparity']}", IMP, "Add widget test of Today with evidence unreadable while Start remains available."),
})

# --- 12. Ramadan and qadha ----------------------------------------------------
NOQADHA = "No fasting-qadha feature exists: no table, no suggestion, no ledger (structural test in test/period_tracking/no_qadha_from_predictions_test.dart)."
ASSESSMENT.update({
    111: a("A recorded period overlaps Ramadan.", NOQADHA, "No suggestion of affected dates.", "None.", "P2", "Medium", "(none)", "-", "Code reading", REQ, QADHA),
    112: a("Only predicted bleeding falls in Ramadan.", "Nothing written: predictions are computed on read and no code path can create qadha debt.", "Prediction labeled as an estimate only.", "No qadha, no prayer status inferred from predictions.", "P0", "High", "CALC PRAYER", "Structural unit test", "test/period_tracking/no_qadha_from_predictions_test.dart (3 tests)", VER),
    113: a("Start near Maghrib.", NOQADHA + " Start is date_only (no time captured, PT-015).", "-", "-", "P2", "Medium", "SBS", "-", "Code reading", REQ, QADHA),
    114: a("Purity near Fajr.", NOQADHA + " End is date_only.", "-", "-", "P2", "Medium", "SBS", "-", "Code reading", REQ, QADHA),
    115: a("Edits a period that affected confirmed qadha.", NOQADHA + " Period edits (PT-051/052) touch only tracking tables.", "-", "-", "P2", "Medium", "MIG_EPI", "-", "Code reading", REQ, QADHA),
    116: a("Removes a period that drove a qadha suggestion.", NOQADHA, "-", "-", "P2", "Medium", "MIG_EPI", "-", "Code reading", REQ, QADHA),
    117: a("Removes a period counted in confirmed debt.", NOQADHA, "-", "-", "P2", "Medium", "MIG_EPI", "-", "Code reading", REQ, QADHA),
    118: a("Bleeding overlaps a recorded qadha completion.", NOQADHA, "-", "-", "P2", "Medium", "(none)", "-", "Code reading", REQ, QADHA),
    119: a("Manual qadha balance already counts the dates.", NOQADHA, "-", "-", "P2", "Medium", "(none)", "-", "Code reading", REQ, QADHA),
    120: a("Turns off Ramadan suggestions.", NOQADHA + " Nothing to turn off; tracking is unaffected.", "-", "-", "P2", "Medium", "(none)", "-", "Code reading", REQ, QADHA),
})

# --- 13. Travel and time ------------------------------------------------------
ASSESSMENT.update({
    121: a("Travel to another zone.", "observed_date stored as calendar date with timezone + offset at observation.", "Dates unchanged.", "-", "P1", "High", "TZ MIG_MODEL", "Unit", f"{T['dst']}", IMP),
    122: a("Date line.", "Calendar date stored; offset may make 'today' repeat/skip.", "-", "-", "P3", "Medium", "TZ", "-", "-", IMP),
    123: a("On a flight.", "No uncertain-time option.", "-", "-", "P3", "Low", "SBS", "-", "-", REQ),
    124: a("Wrong manual zone.", "Not detected.", "-", "-", "P3", "Medium", "TZ", "-", "-", REQ),
    125: a("Device clock ahead.", "Server uses now() for future checks.", "-", "-", "P1", "High", "MIG_WB", "SQL", f"{T['rpcsql']}", VER),
    126: a("DST change.", "Calendar-day math.", "-", "-", "P1", "High", "CALC CAL", "Unit", f"{T['dst']}, {T['caldst']}", VER),
    127: a("Entry before midnight, save after.", "Sheet captures chosen date at selection.", "-", "-", "P2", "Medium", "SBS", "-", "-", IMP),
    128: a("Location denied.", "Tracking independent of location.", "-", "-", "P1", "Medium", "SBS", "Integration", "integration_test/pL2_location_denied_test.dart", IMP),
    129: a("Hijri display.", "Display only.", "-", "-", "P2", "Low", "CAL", "Widget", "-", IMP),
    130: a("Back home.", "Dates stored as dates.", "-", "-", "P1", "High", "CAL", "Unit", "-", IMP),
})

# --- 14. Consistency ----------------------------------------------------------
ASSESSMENT.update({
    131: a("Start from Today.", "One canonical record.", "-", "-", "P0", "High", "DASH CAL INS", "Widget", "test/screens_hardening/next_period_cross_screen_test.dart", IMP),
    132: a("Edit in Calendar.", "-", "-", "-", "P1", "High", "CAL DASH", "Widget", "-", IMP),
    133: a("Observed vs predicted overlap.", "-", "Distinct style + label.", "-", "P1", "High", "CAL", "Widget", f"{T['calendar']} ('a predicted day is visually distinct')", VER),
    134: a("Day without record.", "-", "'Not recorded'.", "-", "P0", "High", "CAL", "Widget", f"{T['calendar']} ('announced as \"no entry\"')", VER),
    135: a("Across new year.", "-", "-", "-", "P2", "Medium", "CAL", "-", "-", IMP),
    136: a("Several observations one date.", "-", "Timeline.", "-", "P2", "Low", "ODS", "Widget", f"{T['calendar']}", VER),
    137: a("Derived calc pending.", "-", "-", "-", "P2", "Medium", "DASH", "-", "-", IMP),
    138: a("Incomplete episodes in Insights.", "-", "-", "-", "P2", "Medium", "INS CALC", "-", "-", IMP),
    139: a("Chart point.", "-", "-", "-", "P3", "Low", "INS", "-", "-", REQ),
    140: a("No trend.", "-", "Insufficient evidence.", "-", "P2", "Medium", "INS", "-", "-", IMP),
})

# --- 15. Offline and sync -----------------------------------------------------
ASSESSMENT.update({
    141: a("Offline start.", "Pending operation persisted before RPC.", "'Saved on device — syncing'.", "-", "P0", "High", "PBOS SBS", "Widget", f"{T['startsheet']} (Closure Blocker 12)", VER),
    142: a("Restart before sync.", "Reconcile replays on start/resume.", "-", "-", "P0", "High", "REPO MAIN", "Unit", f"{T['pending']}, {T['reconcile']}", VER),
    143: a("Response lost.", "Idempotent replay returns original ids.", "-", "-", "P0", "High", "MIG_WB REPO", "SQL", f"{T['rpcsql']}", VER),
    144: a("Edit unsynced.", "Correction queued against queued target.", "-", "-", "P1", "High", "PBOS", "-", "-", IMP),
    145: a("Delete unsynced.", "No delete for canonical; local deletion not resurrected.", "-", "-", "P1", "High", "PBOS", "Unit", f"{T['concurrency']} ('a local deletion cannot be resurrected')", IMP),
    146: a("Two devices add same.", "One-open index; overlap check.", "-", "-", "P1", "High", "MIG_MODEL", "SQL", "-", IMP),
    147: a("Two devices edit fields.", "-", "-", "-", "P2", "Medium", "-", "-", "-", IMP),
    148: a("Two devices make incompatible date edits.", "Second edit refused with NW409 (revision token), never merged silently.", "Changed-elsewhere message.", "-", "P1", "High", "EPS MIG_EPI", "SQL + unit", f"{T['episql']} (section 8), {T['episodeedit']} ('PT-060/PT-148: a change made on another device first is reported')", VER),
    149: a("Old device reconnects.", "-", "-", "-", "P1", "High", "REPO", "-", "-", IMP),
    150: a("Storage/sync fails.", "Never claims success.", "Distinct outcomes.", "-", "P0", "High", "SBS DCS", "Widget", f"{T['failures']}", VER),
})

# --- 16. Accounts and privacy ----------------------------------------------
ASSESSMENT.update({
    151: a("Switch during save.", "Owner pinned at entry.", "-", "-", "P0", "Critical", "PBOS LOCALREPO", "Unit", f"{T['concurrency']}, {T['acctswitch']}", VER),
    152: a("Switch during load.", "Stale results rejected.", "-", "-", "P0", "Critical", "LOCALREPO", "Unit", f"{T['acctswitch']} ('account switch during local read never returns the previous account data')", VER),
    153: a("A→B→A.", "-", "-", "-", "P0", "Critical", "LOCALREPO AUTH", "Unit", "-", IMP),
    154: a("Sign out with pending.", "Per-user store keeps them; notifications cancelled.", "-", "-", "P1", "High", "PBOS AUTH", "Unit", f"{T['pending']}", IMP),
    155: a("Session expires editing.", "-", "-", "-", "P2", "Medium", "AUTH", "-", "-", IMP),
    156: a("Delete account mid-write.", "Queue payloads removed; server FK cascade.", "-", "-", "P0", "Critical", "AUTH PBOS", "Unit + SQL", f"{T['deletion']}, {T['deletionpending']}", IMP),
    157: a("New phone.", "RLS-scoped reads.", "-", "-", "P1", "High", "REPO", "-", "-", IMP),
    158: a("Shared device.", "Discreet notifications default.", "-", "-", "P2", "Medium", "NOTIF", "-", "-", IMP),
    159: a("Export.", "Data export builder.", "-", "-", "P2", "Medium", "EXPORT", "Unit", f"{T['export']}", IMP),
    160: a("Diagnostics.", "Reporter passes operation ids only.", "-", "-", "P1", "High", "REPO", "-", "-", IMP),
})

# --- 17. Notifications --------------------------------------------------------
ASSESSMENT.update({
    161: a("Declines permission.", "-", "-", "-", "P1", "High", "NOTIF", "-", "-", IMP),
    162: a("Prediction reminders.", "-", "Estimate wording.", "-", "P2", "Medium", "NOTIF", "Unit", f"{T['notifcopy']}", IMP),
    163: a("Period before reminder.", "-", "-", "-", "P2", "Medium", "NREFRESH", "-", "-", IMP),
    164: a("Remove or correct a period, or delete an entry, that a reminder was planned from.", "Every saved correction, removal or restore re-runs NotificationRefreshCoordinator for her account right away (best effort; a failure is reported and the next app start re-plans anyway). Refused or offline changes re-plan nothing.", "-", "Active-bleeding and estimated fertile-window reminders follow the current periods.", "P2", "Medium", "NREFRESH CORR", "Unit", f"{T['obsrm']} ('PT-164: reminders are re-planned once after a saved change, never after a refused one')", IMP, "The test proves the re-plan is triggered for the right account; the scheduled reminder set after a removal is not yet asserted end to end, and no device run."),
    165: a("Forgot to end.", "Optional active-bleeding check-in (consent, default off).", "-", "-", "P2", "Medium", "NREFRESH", "-", "-", IMP),
    166: a("Travel after scheduling.", "Recomputed on resume.", "-", "-", "P2", "Medium", "NREFRESH", "Unit", f"{T['notiftz']}", IMP),
    167: a("Old notification.", "Payload for ended episode not reopened.", "-", "-", "P2", "Medium", "DASH", "-", "-", IMP),
    168: a("Multiple categories.", "-", "-", "-", "P3", "Low", "NREFRESH", "-", "-", IMP),
    169: a("Pregnancy mode change.", "Cycle reminder withheld.", "-", "-", "P1", "High", "NOTIF", "Unit", f"{T['notifsched']}", IMP),
    170: a("Lock screen.", "Discreet copy.", "-", "-", "P1", "High", "NOTIF", "Unit", f"{T['notifcopy']}", VER),
})

# --- 18. Accessibility --------------------------------------------------------
ASSESSMENT.update({
    171: a("Arabic RTL.", "-", "-", "-", "P0", "High", "SBS CAL", "Widget", f"{T['startsheet']}, {T['calendar']} (Arabic RTL)", VER),
    172: a("Switch language mid-entry.", "-", "-", "-", "P2", "Medium", "SBS", "-", "-", IMP),
    173: a("Large text.", "-", "-", "-", "P1", "Medium", "SBS CAL", "Widget", f"{T['textscale']}", IMP),
    174: a("Screen reader.", "-", "-", "-", "P1", "High", "CAL", "Widget + device", f"{T['calendar']} (semantics)", BLK, DEVICE),
    175: a("Colour vision.", "-", "-", "-", "P1", "Medium", "CAL", "Widget", "-", IMP),
    176: a("Motor precision.", "-", "-", "-", "P2", "Medium", "SBS", "-", "-", IMP),
    177: a("Reduced motion.", "-", "-", "-", "P2", "Low", "LEGCAL DASH", "-", "-", IMP),
    178: a("Changes something in a tracking edit sheet, then presses Back, Close or taps outside.", "Nothing is saved without Save.", "Period editor, correction sheet and past-day entry sheet ask 'Discard this change?' (Keep editing / Discard) via DiscardEditGuard, and cannot close mid-save. With nothing changed they close as before.", "-", "P2", "Medium", "EPS CS DCS lib/features/cycle_tracking/presentation/widgets/discard_edit_guard.dart", "Widget", f"{T['episodeedit']} ('PT-178: Back with a picked, unsaved date asks before discarding', 'PT-178: Back with nothing picked closes'), {T['correction']} ('PT-178: Back after changing the flow asks before discarding')", VER, "Past-day entry sheet uses the same guard without its own test; the one-tap daily check-in is not guarded."),
    179: a("Long history.", "-", "-", "-", "P3", "Low", "CAL", "-", "-", IMP),
    180: a("Input error.", "-", "-", "-", "P2", "Medium", "SBS", "-", "-", IMP),
})

# --- 19. AI -------------------------------------------------------------------
AI_NOWRITE = "Dr Niswah has no tool or RPC that writes tracking data; records never change from chat."
ASSESSMENT.update({
    181: a("Writes «نزل علي شيء بني» in chat.", AI_NOWRITE, "Model answer only; no reviewed clarifying-question set for brown discharge.", "None.", "P1", "High", "AICHAT AICTX", "Specialist review", "-", BLK, CLINICAL + "; " + SCHOLAR),
    182: a("Writes «وقف يومين ورجع».", AI_NOWRITE, "Model answer only; no structured timeline clarification.", "None.", "P1", "High", "AICHAT AICTX", "Specialist review", "-", BLK, CLINICAL + "; " + SCHOLAR),
    183: a("Dialect, typos or voice transcription.", AI_NOWRITE + " So nothing is changed without confirmation.", "No interpreted-date confirmation UI (none needed while AI cannot write).", "None.", "P1", "High", "AICHAT", "Specialist review", "-", BLK, CLINICAL + "; " + SCHOLAR),
    184: a("Says 'yesterday' in a chat that spans midnight.", AI_NOWRITE, "Model resolves dates itself; no explicit date confirmation.", "None.", "P1", "High", "AICHAT AICTX", "Specialist review", "-", BLK, CLINICAL + "; " + SCHOLAR),
    185: a("Refers to 'it' / 'the same thing'.", AI_NOWRITE, "Model answer only.", "None.", "P1", "High", "AICHAT", "Specialist review", "-", BLK, CLINICAL + "; " + SCHOLAR),
    186: a("AI context cannot load her latest records.", AI_NOWRITE, "Context fields are null when unknown, and a question that depends on an unresolved fiqh state fails closed before the model call (fiqh_state_guard.ts). Disclosure wording needs review.", "None.", "P1", "High", "AICTX supabase/functions/_shared/fiqh_state_guard.ts", "Unit + specialist review", f"{T['aifiqh']}, supabase/functions/_shared/fiqh_state_guard.test.ts", BLK, CLINICAL + "; " + SCHOLAR),
    189: a("AI service is down.", "Tracking unaffected.", "Chat shows a failure; tracking and the red-flag banner keep working. Reviewed static guidance does not exist yet.", "None.", "P1", "High", "AICHAT", "Unit + specialist review", f"{T['aifail']}", BLK, CLINICAL + "; " + SCHOLAR),
})
ASSESSMENT[187] = a("AI proposes a change.", "No AI write path exists.", "-", "-", "P1", "High", "AICHAT", "Structural", "Code reading", IMP)
ASSESSMENT[188] = a("Misleading instructions.", "AI context bound to JWT user; no mutation tools.", "-", "-", "P0", "Critical", "AICTX", "Code review", "-", IMP)
ASSESSMENT[190] = a("Switch during AI response.", "-", "-", "-", "P0", "Critical", "AICHAT", "Unit", f"{T['chatacct']}", IMP)

# --- 20. Migration and release ----------------------------------------------
ASSESSMENT.update({
    191: a("Legacy records lack zone.", "legacy_unverified provenance.", "-", "-", "P2", "Medium", "PROJ", "Unit", f"{T['legacyprov']}", IMP),
    192: a("Legacy overlaps.", "-", "-", "-", "P2", "Medium", "-", "-", "-", IMP),
    193: a("Old app, new backend.", "-", "-", "-", "P1", "High", "-", "-", "-", IMP),
    194: a("App update with queue.", "Queue persisted in secure storage.", "-", "-", "P1", "High", "PBOS", "-", "-", BLK, DEVICE),
    195: a("Prediction rollback.", "No versioning.", "-", "-", "P3", "Medium", "CALC", "-", "-", REQ),
    196: a("Disable fiqh automation.", "-", "-", "-", "P2", "Medium", "ENGINE", "-", "-", REQ),
    197: a("Discrepancy detected.", "-", "-", "-", "P2", "Medium", "-", "-", "-", REQ),
    198: a("Guidance revision.", "KB review status/provenance.", "-", "-", "P2", "Medium", "-", "-", "-", BLK, CLINICAL),
    199: a("Wrong calendar report.", "-", "-", "-", "P2", "Medium", "-", "-", "-", REQ),
    200: a("Devices differ.", "-", "-", "-", "P0", "High", "-", "Device", "-", BLK, DEVICE),
})


def parse_cases(text: str) -> list[dict]:
    cases = []
    section = ""
    for line in text.splitlines():
        m = re.match(r"^## (\d+)\. (.+)$", line)
        if m:
            section = f"{m.group(1)}. {m.group(2)}"
            continue
        m = re.match(r"^\| (PT-(\d{3})) \| (.+?) \| (.+?) \|$", line)
        if m:
            cases.append(dict(id=m.group(1), n=int(m.group(2)), section=section,
                              scenario=m.group(3), expected=m.group(4)))
    return cases


def expand(locs: str) -> str:
    return "; ".join(L.get(tok, tok) for tok in locs.split())


def build() -> str:
    cases = parse_cases(CASES_MD.read_text(encoding="utf-8"))
    ids = [c["n"] for c in cases]
    if sorted(ids) != list(range(1, 201)):
        sys.exit(f"case list must hold PT-001..PT-200 exactly once; got {len(ids)}")
    missing = [n for n in range(1, 201) if n not in ASSESSMENT]
    if missing:
        sys.exit(f"no assessment for: {missing}")
    out = io.StringIO()
    cols = ["id", "section", "scenario", "expected_behavior", "preconditions_and_steps",
            "expected_stored_result", "expected_ui", "downstream_effects", "priority",
            "risk", "implementation_locations", "verification_method", "evidence",
            "status", "remaining_dependency"]
    w = csv.writer(out, lineterminator="\n")
    w.writerow(cols)
    for c in cases:
        x = ASSESSMENT[c["n"]]
        if x["status"] not in STATUSES:
            sys.exit(f"{c['id']}: unknown status {x['status']!r}")
        if x["status"] == VER and x["evidence"] in ("", "-"):
            sys.exit(f"{c['id']}: VERIFIED needs evidence")
        w.writerow([c["id"], c["section"], c["scenario"], c["expected"], x["steps"],
                    x["stored"], x["ui"], x["downstream"], x["priority"], x["risk"],
                    expand(x["locations"]), x["method"], x["evidence"], x["status"],
                    x["dependency"]])
    return out.getvalue()


def main() -> None:
    content = build()
    if "--check" in sys.argv:
        if not CSV_OUT.exists() or CSV_OUT.read_text(encoding="utf-8") != content:
            sys.exit("PERIOD_TRACKING_COVERAGE.csv is stale; run scripts/period_tracking_register.py")
        return
    CSV_OUT.write_text(content, encoding="utf-8")
    counts: dict[str, int] = {}
    for x in ASSESSMENT.values():
        counts[x["status"]] = counts.get(x["status"], 0) + 1
    for k in sorted(counts):
        print(f"{counts[k]:4d}  {k}")


if __name__ == "__main__":
    main()

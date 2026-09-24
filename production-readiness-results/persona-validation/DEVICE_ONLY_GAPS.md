# Real-Device-Only (E4) Gaps

Everything in this wave (and the two prior notification-focused waves
on this same PR) ran on the iOS Simulator, against a disposable local
backend. `E4` (a real physical device, a real owner, real network
conditions) is not claimed anywhere in this PR's evidence trail. This
document lists specifically what a simulator run cannot prove.

## Cannot be proven on any simulator, iOS or Android

- **Real push-notification delivery and timing.** The simulator can
  prove a `zonedSchedule`/`cancel` call was accepted by the plugin API;
  it cannot prove the OS actually delivers the notification at the
  expected wall-clock moment, or delivers it at all under real
  power-saving/Doze/background-refresh restrictions.
- **Real OS permission prompts** (notifications, location) — the
  simulator can be pre-authorized or denied programmatically, which is
  not the same interaction as a real human tapping a real system
  dialog for the first time.
- **Real airplane-mode / genuine network-loss behavior.** This wave's
  own Persona F evidence is existing unit/widget-level coverage
  (`pending_bleeding_operation_store_test.dart`, 28 tests) of the
  offline-queue and reconciliation logic — not a live device losing and
  regaining a real network connection.
- **Real timezone/DST transitions** while the app is genuinely
  backgrounded across a real wall-clock boundary.
- **Real keyboard/autofill/password-manager interactions** on the
  sign-up and sign-in forms.
- **Real biometric/Face ID/Touch ID-gated flows**, if any exist
  elsewhere in the app.
- **Real background app-refresh timing** for the reminder-reconciliation
  logic described in the earlier notification-focused waves on this PR.
- **Real battery/thermal/performance behavior** under sustained use.

## Android-specific gaps this wave

An Android emulator (`Pixel_8` AVD) is present and was confirmed
bootable in this environment, but **no Android run was executed this
wave** — every persona above ran on iOS Simulator only. This is a real,
disclosed gap, not inferred-safe from a successful Android compile (the
existing CI `Build Android` job is a compile-correctness check only,
explicitly not persona-suite evidence — see `TEST_EXECUTION_REPORT.md`).
Specifically untested on Android:
- The native Android date-picker interaction pattern (Persona D relied
  on iOS's specific "Switch to input" `DatePickerDialog` affordance;
  Android's own Material date picker has a different, though similar,
  interaction).
- Android's own notification-permission model (`POST_NOTIFICATIONS`
  runtime permission, Android 13+) versus iOS's.
- Android back-button/back-gesture behavior on any of the sheets/dialogs
  exercised this wave.
- Android-specific keyboard/IME behavior on the sign-up form.

## Bilingual (Arabic RTL) gaps this wave

Every live persona run this wave used the English UI path (the
`Flows.boot(english: true)` default). Arabic-language correctness for
the specific journeys exercised live this wave (sign-up, onboarding,
Start Bleeding, backfill, correction, notification settings, account
switch) was **not** re-verified live in Arabic. Existing, already-
passing widget-level Arabic/RTL coverage exists for several of the
individual sheets involved (e.g. `correction_sheet_test.dart`'s own
"Arabic: the sheet renders RTL with the Arabic labels" test,
`sign_in_rtl_test.dart`), but a live, full-journey Arabic run — the
level of evidence the charter asks for — was not performed this wave.

## What IS claimed

- E2 (automated, live against a real compiled app and a real, disposable
  Postgres database) for the personas and features marked EXECUTED in
  `COVERAGE_MATRIX.csv`.
- E2/E3 (existing suite, live-Postgres-verified in earlier waves) for
  Persona F (offline/pending) and Persona I (degraded evidence), cited
  rather than re-demonstrated live this wave.

No E4 evidence is claimed for any item in this document or this wave's
work as a whole.

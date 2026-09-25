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

## Android

An Android emulator (`Pixel_8`, Android 15, hardware GPU) ran the whole persona
suite live, and GitHub-hosted emulators (API 34, software GPU, sharded) ran it
too: 21/21 PASS (run 36114358622). Android compile-only CI is **not** counted
as evidence. Still not provable without a physical Android device:

- OEM-specific behaviour (battery optimisation killing reminders, vendor
  keyboards/IMEs, gesture-navigation variants).
- The real `POST_NOTIFICATIONS` runtime dialog and delivery timing.
- Real GPS (the location personas set the OS permission from the host and use
  a fixed fix; on Android that persona is exercised via the emulator geo fix
  in `scripts/set_location_permission.sh`).
- Real Play services sign-in (Google) and SMS OTP (phone) — external
  providers, recorded BLOCKED.

## Bilingual (Arabic RTL)

A **live** Arabic journey now exists (`pAR1_arabic_rtl_test`, iOS and
Android): language switch from Profile, five-tab navigation, a real save in
Arabic, the date picker with Arabic digits, Arabic keyboard entry, back
navigation, RTL month controls, no overflow at 200% text scale on any tab,
no English leaks per tab, semantic labels on icon buttons. It found D-009 and
D-010. Not provable in an emulator: a real VoiceOver/TalkBack reading order
and Arabic text shaping on physical fonts/hardware keyboards.

## What IS claimed

- E2 (automated, live against a real compiled app and a real, disposable
  Postgres database) for the personas and features marked EXECUTED in
  `COVERAGE_MATRIX.csv`.
- E2 for Persona F (offline/pending/replay) and Persona I (degraded
  evidence) executed live on iOS and Android in this program.

No E4 evidence is claimed for any item in this document or this wave's
work as a whole.

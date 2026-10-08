# E4 — physical-device checklist (the smallest possible)

**Status: NOT EXECUTED. E4 is not claimed as passed anywhere.** This is the
minimum a person must do on a real phone. It deliberately does **not** repeat
anything already proven on the simulator/emulator (see `COVERAGE_MATRIX.csv`):
only behaviour a simulator cannot prove.

Two devices are enough: one iPhone and one Android phone (ideally a non-Pixel
vendor build). Use a **test account**; do not use a real person's data.

## The build under test

Fill this in when handing over (the build is identified by its exact commit):

| | |
|---|---|
| Git SHA | *(see `E4_BUILD_MANIFEST.md`)* |
| Android | `dist/niswah-e4-<sha>.apk` — a **profile** (AOT, debug-signed) build for sideloading: release performance without a store keystore. Not store-publishable. |
| iOS | `flutter build ios --release` then sign with your Apple team in Xcode (CI proves the no-codesign compile only). |
| Banner | The build shows `SHA:… ENV:… BACKEND:…` — confirm the SHA on screen equals the one above before testing. |
| Backend | **Your decision.** The acceptance harness refuses production by design and never creates accounts there. Options: (a) an approved non-production staging project (a reviewed one-line allowlist change), or (b) production with a founder-created test account. Do not let testers create accounts on production casually. |

## Checklist

Mark each row PASS / FAIL with a screenshot or screen recording and the exact
device model + OS version. Time-based rows need the elapsed time recorded.

| # | Behaviour | Why a simulator cannot prove it | Steps | Pass means | Related rows |
|---|---|---|---|---|---|
| **E4-01** | **Real notification delivery over time** | OS scheduling, Doze / Low-Power / vendor battery killers, lock screen | Sign in, open an episode with no check-in today, enable the daily check-in reminder for +2 min; **lock the phone and force-quit the app**; repeat with a reminder set for tomorrow morning and leave overnight; repeat with battery saver on | Each notification arrives within the OS's tolerance of the set local time with the app closed; tapping opens the daily check-in for the right episode; the notification text carries no health content | REM-01/02/03 |
| **E4-02** | **Notification permission prompt** | The real OS prompt (iOS; Android 13+ POST_NOTIFICATIONS) | Fresh install; enable a reminder; **Allow** once, then on a second install **Deny**; re-enable from OS settings | Allow -> notifications work. Deny -> the app says so honestly (no silent failure), the rest of the app works, and re-enabling from OS settings works | REM-01, AUTH-* |
| **E4-03** | **Real location permission** | Real GPS, precise/approximate, "Once" | Onboarding -> Use current location: **While Using**, then **Once**, then **Deny**, then **Deny + don't ask again**; try indoors with no fix; iOS: turn *Precise* off | A real fix sets the prayer city; no fix falls back honestly after ≤20 s ("Unable to get your location"), never an endless spinner; Deny leaves manual city selection working | ONB-04, PRAY-02/03 |
| **E4-04** | **Airplane mode and recovery** | A real radio going away mid-request; real reconnection | Start Bleeding in airplane mode; confirm "Saved on device"; **force-quit** the app; airplane off; reopen | The pending item replays exactly once (one episode, one observation), Today updates without a manual refresh, no "Salah is obligatory" while bleeding; repeat on a weak/flaky network | MENS-13 |
| **E4-05** | **Time zone and DST** | Real zone/DST transitions and travel | With a reminder set for 18:00: change the device zone (e.g. Riyadh -> London) and, on a second pass, set the date across a DST change | The reminder is still 18:00 **local**; the app's "today" and the day count follow the device date; no duplicate or missing reminder | PRAY-05, REM-02 |
| **E4-06** | **Keyboard, autofill, password manager** | Real IME and credential providers | Sign up and sign in using the iCloud Keychain / Google Password Manager (and one third-party manager); type Arabic with the system keyboard, paste, dictate, emoji | Autofill fills email+password; Arabic text entry and cursor behave; nothing is clipped by the keyboard (Publish / Save reachable) | AUTH-01/02, COMM-01 |
| **E4-07** | **VoiceOver / TalkBack** | The real screen reader and its reading order | Turn the reader on and complete: sign in -> Today -> Start Bleeding (save) -> Calendar day detail -> a community post -> Profile. Repeat in **Arabic** | Every control is announced with a meaningful label; focus order is logical (and RTL in Arabic); actions (tap, back, dismiss) work; no unlabeled icon buttons | AR-04 |
| **E4-08** | **Performance, background, battery** | Real CPU/GPU/thermals/memory | 30-minute session across Today/Calendar/Community; cold start x5; background for 10 min then resume; Low-Power Mode; 1 hour idle-in-background battery drain | Cold start < 3 s on the mid-range device; no visible jank scrolling Today/Calendar/Community; no crash or data loss on resume; no abnormal battery/thermal use | — |

## Not part of E4 (kept BLOCKED, external)

- SMS OTP and Google sign-in (need real providers and credentials).
- AI answer quality / Fiqh and medical content correctness (needs a model
  backend and qualified review — a separate content gate).
- Anything already proven on the emulator/simulator.

## Recording results

For every row keep: device + OS, app SHA on the banner, PASS/FAIL, evidence file
name, and any deviation. E4 stays **NOT PASSED** until every row has been
physically executed and recorded here.

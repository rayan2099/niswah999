# Period tracking: external dependencies

These cases cannot reach VERIFIED from inside the repository. Each one needs
evidence that only people or physical devices can provide. The app must not
invent medical thresholds or religious rules to close them.

## 1. Clinician-approved safety specification and wording

Needed for: PT-081, PT-082, PT-084, PT-086, PT-087, PT-088, PT-089, PT-090,
PT-091..PT-100, PT-181..PT-186, PT-189, PT-198.

What is needed:
- The thresholds that make bleeding "prolonged", "heavy" or "concerning".
- Which symptoms (severe pain, dizziness, fainting) escalate, and how urgently.
- Approved Arabic and English wording for each message.
- What to show when the guidance service is unavailable.

The app today keeps the existing red-flag behavior. Nothing new is invented.

## 2. Scholar-approved per-madhhab specification

Needed for: PT-088, PT-101, PT-103..PT-109, PT-111, PT-113..PT-120,
PT-181..PT-186, PT-189.

What is needed:
- Per-madhhab rules for minimum and maximum hayd, interrupted bleeding,
  brown discharge, and pregnancy loss.
- Rules for start near Maghrib and purity near Fajr, which qadha needs.
- The wording to use when evidence exists but no rule is approved.

Qadha automation (PT-111, PT-113..PT-120) is deferred by the 2026-10-29
product decision. The cases stay in the register as IMPLEMENTATION REQUIRED,
with this dependency recorded.

## 3. Signed iPhone and Android build runs

Needed for: PT-174, PT-194, PT-200, plus device confirmation of every widget
VERIFIED row.

What is needed:
- A screen-reader pass on both platforms, covering VoiceOver and TalkBack.
- An app update installed while operations are still queued.
- The acceptance flows run on signed builds.

CI passing is not device evidence.

## 4. Per-environment migration approval

`supabase/migrations/20261029100000_bleeding_episode_corrections.sql` adds the
episode-correction tables and RPCs. It is additive: it creates new tables and
functions, and replaces one validation trigger function with a superset.

It has not been applied to staging or production. Until rayan applies it, the
"Edit this period" actions fail on the server: she sees a "not saved"
message and nothing changes. The new UI therefore must not ship in a build
until the migration is on that build's backend.

Order: staging, then a device check, then production. rayan runs the SQL in
the dashboard.

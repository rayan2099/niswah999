# 00_01 — Release Candidate Baseline

Audit start date: 2026-09-04

## Release Candidate Identity

| Field | Value |
|---|---|
| Repository | `/Users/rynadalsabh/Niswah` (local working copy; no `origin` remote configured — verify with `git remote -v`) |
| Branch | `main` |
| Commit SHA | `13a9387e9f2e5bbb0f61f7b13906d75e2f4d0d9f` |
| Prior commit | `6d59bfe` ("feat: initial clean commit for Niswah mobile app") |
| Tag/version | None (no git tags). App version per `pubspec.yaml`: `1.0.0+1` |
| Build artifact | None built during this audit (no CI, no build was produced) |
| Build number | `1` (Android versionCode / iOS CFBundleVersion, from `pubspec.yaml` `version: 1.0.0+1`) |
| DB migration state | 15 migration files in `supabase/migrations/`, latest timestamp `20260830140000_community_schema_reset.sql`. `supabase/schema.sql` (507 lines) present as a consolidated schema snapshot — relationship between `schema.sql` and the migrations directory (source of truth vs. generated dump) is **UNKNOWN / REQUIRES VALIDATION**, assigned to Database audit. |
| Dependency lockfile | `pubspec.lock` present (Flutter/Dart — authoritative for the audited app). `package-lock.json` present but belongs to the **reference-only web app** (see Scope Note below), not the release candidate. |
| Environment config | `.env` present locally (not committed — `.gitignore` excludes `.env*`, keeps `.env.example`). Contains `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_ENV`, `GEMINI_API_KEY`. Real values not reproduced in this report. |
| Feature flags | No feature-flag system discovered in `lib/` (no LaunchDarkly/Firebase Remote Config/custom flag service found). Marked UNKNOWN — will be confirmed by Dependencies/Config audit. |
| Runtime versions | Flutter SDK constraint `^3.13.0` (`pubspec.yaml`); Flutter tool revision `4cf24164269a5ebf0c16a028a00727d0e77bbb05` (`.metadata`) |
| Deployment target | iOS + Android native app, bundle ID `com.niswah.niswah` (both platforms, confirmed in `ios/Runner.xcodeproj/project.pbxproj` and `android/app/build.gradle.kts`). No CI/CD pipeline found (no `.github/workflows`, no other CI config discovered). |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions). Project URL/keys not disclosed in this report. |

## Git History Caveat

The repository contains only **2 commits**, the first labeled "initial clean commit." This indicates history was squashed/reset prior to this audit — normal development history (incremental commits, PR trail, code review record) is **not available**. This is recorded as a limitation for Code Quality and Release/Deployment audits (no audit trail of how the current state was reached) rather than assumed benign.

## Scope Note — Two Codebases Present

This repository contains **two distinct applications**:

1. **`lib/` — Flutter mobile app "Niswah"** (Dart, iOS + Android, bundle `com.niswah.niswah`). This is the actual release candidate: a women's menstrual/pregnancy health tracker with Islamic fiqh (madhhab-based) cycle classification, prayer tracking, community, private messaging, AI chat ("Dr. Niswah"), dream interpretation, and PDF doctor/husband reports. Backed by Supabase.
2. **`src/` — React/Vite web app** (TypeScript, `package.json`, Firebase + `@google/genai` deps, deployed via Vercel per `.vercel/project.json`). Per prior project guidance (persisted memory) this is a **design reference only** used as the visual/UX source of truth for the Flutter port (see `FLUTTER_UI_PARITY_GUIDE.md`, `MANIFEST.md`, `docs/UI_PARITY_TEST_PLAN.md`, golden captures in `test/goldens/`). It is not being edited or shipped as the production consumer-facing product in this engagement.

**Decision:** This audit treats the **Flutter app (`lib/` + `android/` + `ios/`) and its Supabase backend (`supabase/`) as the release candidate under audit.** The `src/` web app is inspected only where it affects the release candidate (e.g., as the design/behavior reference, or if it shares a live backend project with the mobile app — see `UNK-001`). This scope decision is recorded in the Unknown/Assumption register (`ASM-001`) and must be confirmed with the release owner if incorrect.

## Legacy/Stale Artifacts Observed (flagged for Code Quality / Dependencies audits, not yet verified)

- `firestore.rules`, `firebase-blueprint.json`, `firebase-applet-config.json` at repo root reference a **Firestore data model** (`/users/{userId}` with fields like `madhhab`, `premium_status`, etc.), but **no Firebase/Firestore dependency exists in `pubspec.yaml`** — the Flutter app uses Supabase exclusively. These appear to be stale artifacts from an earlier or parallel prototype (the web app does list `firebase` in `package.json`). Candidate stale-code finding for Code Quality audit.
- `haidfigh.md` (fiqh rule specification, "Draft Implementation Spec (Pending Human Scholar Review)") — if this governs the shipped cycle-classification logic, its draft/unreviewed status is a **content-accuracy and regulated-domain risk** (menstrual/religious rulings affecting real users' religious practice), relevant to Functional QA and Privacy/Compliance audits.

## Preliminary Confirmed-by-Code Findings (seed evidence for Security/Code Quality waves — to be formally registered with finding IDs by the specialist audits)

1. `pubspec.yaml` lists `.env` under `flutter: assets:`, meaning the local `.env` file (containing `GEMINI_API_KEY`) is **bundled directly into the compiled app binary** at build time. `lib/core/services/gemini_service.dart` reads `GEMINI_API_KEY` via `flutter_dotenv` and calls the Google Generative Language API **directly from the client** (no server-side proxy), for the AI Advisor and Dream Interpreter features. This key would be extractable from any release APK/IPA. Contrast with `lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart`, which correctly proxies the "Dr. Niswah" chat feature through a Supabase Edge Function (`dr-niswah-chat`) that keeps the Gemini call server-side. This is an architectural inconsistency (competing implementations) and a probable client-secret-exposure issue — routed to Security audit as a candidate for the highest severity finding pending confirmation.
2. `GeminiService` calls endpoint `https://generativelanguage.googleapis.com/v1beta/interactions`, which does not match the publicly documented Gemini REST API shape (`.../v1beta/models/{model}:generateContent`). This may be a hallucinated/incorrect API surface — if so, the AI Advisor and Dream Interpreter features could be non-functional in production. Requires runtime validation (Functional QA / API audit); not confirmed here.
3. `AppEnvironment` (`lib/core/config/app_environment.dart`) declares required client-side secrets `OPENAI_API_KEY`, `NISWAH_AI_API_KEY`, `DREAM_INTERPRETER_API_KEY`, none of which are present in `.env` or `.env.example`. Accessing these getters would throw `FormatException`. Whether any live code path calls them is unconfirmed — candidate dead-code/phantom-env-var finding.
4. No CI/CD configuration was found anywhere in the repository — routed to Release/Deployment audit as a candidate mandatory-gate failure (`LG-M-17`).

## Release Candidate Change Log

| Change ID | Date/time | Change | Why | Domains invalidated | Re-audit required? |
|---|---|---|---|---|---|
| — | — | No changes observed during audit so far | — | — | — |

This table will be updated if the working tree changes materially during the audit.

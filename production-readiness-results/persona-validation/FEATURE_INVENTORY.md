# Feature Inventory — Niswah, PR #4 (`feat/menstrual-data-integrity`)

Built directly from the codebase (`lib/features/*`), not from memory or
marketing copy. Each row is one independently-reachable, user-facing
feature. IDs are stable references used by `COVERAGE_MATRIX.csv`.

This inventory undercounts on purpose in one direction and overcounts in
another: it does not split "tap a switch" into its own feature for every
screen that has one (covered under the owning screen), but it does list
every distinct **journey outcome** (e.g. sign-up success vs sign-up
failure) as separate rows, since those are the acceptance-relevant units
the charter asks to be tested.

| ID | Area | Feature | Primary file(s) |
|---|---|---|---|
| AUTH-01 | Auth | Email sign-up | `sign_in_screen.dart` |
| AUTH-02 | Auth | Email sign-in | `sign_in_screen.dart` |
| AUTH-03 | Auth | Phone sign-up (OTP) | `sign_in_screen.dart` |
| AUTH-04 | Auth | Phone sign-in (OTP) | `sign_in_screen.dart` |
| AUTH-05 | Auth | Google sign-in | `sign_in_screen.dart` |
| AUTH-06 | Auth | Failed sign-in (wrong password) | `sign_in_screen.dart` |
| AUTH-07 | Auth | Network failure during auth | `sign_in_screen.dart`, `network_failure.dart` |
| AUTH-08 | Auth | Email confirmation pending state | `sign_in_screen.dart` |
| AUTH-09 | Auth | Session restore on app restart | `main.dart` (`_buildHome`), `auth_controller.dart` |
| AUTH-10 | Auth | Sign-out | `profile_screen.dart`, `auth_controller.dart` |
| AUTH-11 | Auth | Account deletion | `profile_screen.dart` (the reachable path; `account_settings_screen.dart` has no navigation path) |
| AUTH-12 | Auth | Consent gate (Privacy Policy checkbox) | `sign_in_screen.dart` |
| ONB-01 | Onboarding | Madhhab: explicit selection | `onboarding_screen.dart` |
| ONB-02 | Onboarding | Madhhab: "I don't know" → suggestion flow | `onboarding_screen.dart`, `madhhab_resolution_screen.dart` |
| ONB-03 | Onboarding | Marital status (married/unmarried) | `onboarding_screen.dart` |
| ONB-04 | Onboarding | Location: current location | `onboarding_screen.dart` |
| ONB-05 | Onboarding | Location: manual city pick | `onboarding_screen.dart` |
| ONB-06 | Onboarding | Location: skip | `onboarding_screen.dart` |
| ONB-07 | Onboarding | Menstrual history: known last period date | `onboarding_screen.dart` |
| ONB-08 | Onboarding | Menstrual history: "I'm not sure" | `onboarding_screen.dart` |
| ONB-09 | Onboarding | Menstrual history: still bleeding now | `onboarding_screen.dart` |
| ONB-10 | Onboarding | Baseline estimate (period/cycle length) | `onboarding_screen.dart` |
| ONB-11 | Onboarding | Anonymous mode toggle | `onboarding_screen.dart` |
| ONB-12 | Onboarding | Save failure / retry | `onboarding_screen.dart` |
| MENS-01 | Menstrual | Start Bleeding (today/yesterday/date) | `start_bleeding_sheet.dart` |
| MENS-02 | Menstrual | Daily check-in (Yes/No/Not sure) | `daily_checkin_sheet.dart` |
| MENS-03 | Menstrual | End Bleeding | `start_bleeding_sheet.dart` (`_EndBleedingSheet`) |
| MENS-04 | Menstrual | Add a missing day (backfill) | `daily_checkin_sheet.dart` (`showBackfillObservationSheet`) |
| MENS-05 | Menstrual | Multiple observations same day | same as MENS-04, applied to today's own date |
| MENS-06 | Menstrual | Correct an existing entry | `correction_sheet.dart` |
| MENS-07 | Menstrual | Correction conflict resolution | `correction_sheet.dart` |
| MENS-08 | Menstrual | Revision history display | `observation_detail_sheet.dart` |
| MENS-09 | Menstrual | Canonical calendar (month grid, day detail) | `canonical_calendar_screen.dart` |
| MENS-10 | Menstrual | Legacy Calendar tab (bottom nav) | `cycle_tracking_screen.dart` |
| MENS-11 | Menstrual | Insights | `insights_screen.dart` |
| MENS-12 | Menstrual | Evidence-unresolved / degraded-evidence states | `dashboard_screen.dart` (`_FiqhEvidenceUnresolvedCard`) |
| MENS-13 | Menstrual | Offline write + pending-operation recovery | `pending_bleeding_operation_store.dart`, all 4 sheets |
| REM-01 | Reminders | Enable/disable daily check-in reminder | `notification_settings_screen.dart` |
| REM-02 | Reminders | Change reminder time | `notification_settings_screen.dart` |
| REM-03 | Reminders | Notification tap routing | `notification_service.dart`, `dashboard_screen.dart` |
| PRAY-01 | Prayer | Manual city selection | `profile_screen.dart` (Prayer Times Settings) |
| PRAY-02 | Prayer | Device location for prayer times | `profile_screen.dart` |
| PRAY-03 | Prayer | Location permission denied | `prayer_tracking_screen.dart` |
| PRAY-04 | Prayer | Prayer logging (mark completed/missed/excused) | `prayer_tracking_screen.dart` |
| PRAY-05 | Prayer | Timezone change re-derivation | `device_timezone.dart` |
| PRAY-06 | Prayer | Salah status card (obligatory/lifted/unresolved/insufficient-history) | `dashboard_screen.dart` (`_PrayerStatusCard`) |
| TTC-01 | TTC | Unmarried restriction (feature hidden/gated) | `dashboard_screen.dart`, onboarding marital gating |
| TTC-02 | TTC | Married + TTC enabled | `dashboard_screen.dart` |
| TTC-03 | TTC | Fertility window display | `dashboard_screen.dart`, `cycle_calculation_service.dart` |
| PREG-01 | Pregnancy | Setup (tracking basis, reference date) | `dashboard_screen.dart` (pregnancy setup flow) |
| PREG-02 | Pregnancy | Active pregnancy overview | `dashboard_screen.dart` (`_PregnancyOverviewCard`) |
| PREG-03 | Pregnancy | Week progression | `pregnancy_status_engine.dart` |
| PREG-04 | Pregnancy | Log birth → Nifas transition | `dashboard_screen.dart` (`pregnancy-log-birth`) |
| PREG-05 | Pregnancy | Pregnancy report | `doctor_report_screen.dart`? / husband/fiqh reports |
| PREG-06 | Pregnancy | AI context includes pregnancy state | `ai_advisor_service.dart` |
| NIFAS-01 | Nifas | Start postpartum (from birth log) | `dashboard_screen.dart` |
| NIFAS-02 | Nifas | Active Nifas status card | `dashboard_screen.dart` (`nifas-status`) |
| NIFAS-03 | Nifas | Prayer/fasting status during Nifas | `dashboard_screen.dart`, `_PrayerStatusCard` |
| NIFAS-04 | Nifas | Nifas end / transition back | `dashboard_screen.dart` |
| WELL-01 | Wellbeing | Mood/energy/sleep entry | `dashboard_screen.dart` (Mental state check-in), `wellbeing` feature |
| WELL-02 | Wellbeing | History | `wellbeing_report_screen.dart` |
| WELL-03 | Wellbeing | Report | `wellbeing_report_screen.dart` |
| WELL-04 | Wellbeing | Reminder | `notification_settings_screen.dart` (Daily wellbeing check-in) |
| AI-01 | AI | General assistant | `dr_niswah_chat_screen.dart` (`NiswahAssistantMode.general`) |
| AI-02 | AI | Health assistant (Dr Niswah) | `dr_niswah_chat_screen.dart` (`.health`) |
| AI-03 | AI | Fiqh advisor | `dr_niswah_chat_screen.dart` (`.fiqhAdvisory`) |
| AI-04 | AI | Dream interpreter | `dream_interpreter_screen.dart` |
| AI-05 | AI | Conversation history | `dr_niswah_chat_screen.dart` |
| AI-06 | AI | Delete conversation | `dr_niswah_chat_screen.dart` |
| AI-07 | AI | Backend unavailable | edge functions, `ai_advisor_service.dart` |
| AI-08 | AI | Malformed response handling | edge functions |
| AI-09 | AI | Citation/source requirements (Fiqh) | `fiqh-advisor-chat` edge function |
| COMM-01 | Community | Create post | `community_board_screen.dart` |
| COMM-02 | Community | Anonymous post | `community_board_screen.dart` |
| COMM-03 | Community | Search | `community_board_screen.dart` |
| COMM-04 | Community | Like | `community_board_screen.dart` |
| COMM-05 | Community | Open post detail | `post_detail_screen.dart` |
| COMM-06 | Community | Delete own post | `post_detail_screen.dart` |
| COMM-07 | Community | Author preview | `post_detail_screen.dart` |
| COMM-08 | Community | Message author | `post_detail_screen.dart` → `private_messaging` |
| COMM-09 | Community | Empty state | `community_board_screen.dart` |
| COMM-10 | Community | Backend failure | `community_board_screen.dart` |
| MSG-01 | Messaging | Create/open conversation | `conversations_screen.dart` |
| MSG-02 | Messaging | Send message | `chat_detail_screen.dart` |
| MSG-03 | Messaging | Receive message | `chat_detail_screen.dart` |
| MSG-04 | Messaging | Unread state | `conversations_screen.dart` |
| MSG-05 | Messaging | History | `chat_detail_screen.dart` |
| MSG-06 | Messaging | Delete conversation | `conversations_screen.dart` |
| MSG-07 | Messaging | Cross-account privacy (RLS) | private_messaging repository |
| RPT-01 | Reports | Fiqh report | `fiqh_report_screen.dart` |
| RPT-02 | Reports | Doctor report | `doctor_report_screen.dart` |
| RPT-03 | Reports | Wellbeing report | `wellbeing_report_screen.dart` |
| RPT-04 | Reports | Husband report (eligible only) | `husband_report_screen.dart` |
| RPT-05 | Reports | JSON data export | `data_export_screen.dart` |
| PROF-01 | Profile | Anonymous mode | `profile_screen.dart` |
| PROF-02 | Profile | Notification settings | `notification_settings_screen.dart` |
| PROF-03 | Profile | Privacy policy | `privacy_policy_screen.dart` |
| PROF-04 | Profile | Account state toggles (married/pregnant/nifas) | `profile_screen.dart` |
| PROF-05 | Profile | Delete-account confirmation + completion | `profile_screen.dart` |
| SYS-01 | System | Build identity confirmation (SHA/backend) | `diagnostics_banner.dart`, `build_info.dart` |
| SYS-02 | System | Account switch / sign-out data isolation | `auth_controller.dart` (`cancelAll`, secure-storage cleanup) |
| MAD-01 | Madhhab | Guided suggestion stored only after the user confirms it | `madhhab_resolution_screen.dart`, `onboarding_screen.dart` |
| MAD-02 | Madhhab | Declining the suggestion stores nothing | `onboarding_screen.dart` |
| AR-01 | Arabic/RTL | Live Arabic journey (switch, 5 tabs, save, date picker, keyboard, back) | whole app |
| AR-02 | Arabic/RTL | 200% text scale layout in Arabic | whole app |
| AR-03 | Arabic/RTL | RTL directional layout + Arabic-Indic date picker | calendar, pickers |
| AR-04 | Accessibility | Screen-reader semantics (labels) | whole app |
| SYS-03 | System | Whole persona suite on a real Android emulator | `scripts/run_acceptance_suite.sh` |
| SYS-04 | System | Production kill switch | `test_backend_gate.dart`, `assert_test_backend.py` |
| SYS-05 | System | Account deletion leaves no orphan rows | `delete_my_account()` + migrations |
| JRN-01 | Journeys | Guided journeys | `guided_journeys_screen.dart` — **no navigation path** |
| LIB-01 | Library | Educational resource library | `resource_library_screen.dart` — **no navigation path** |
| GHU-01 | Fiqh | Ghusl guide | `ghusl_guide_screen.dart` — **no navigation path** |
| SET-01 | Settings | Account/Settings screens | `account_settings_screen.dart`, `settings_screen.dart` — **no navigation path** |

**Total inventoried features/journeys: 114** (101 from the original
directory/grep pass + 13 added while executing Phases 3-4: the Madhhab
guided flow, the live Arabic/RTL/accessibility rows, three system rows and
the four features that turned out to have **no navigation path** in the
shipped app — they are counted, marked BLOCKED, and listed in
`DEFECT_REGISTER.md` F-001 rather than being dropped from the denominator).
`COVERAGE_MATRIX.csv` is the authoritative row-for-row match to this list.

This list is still a working denominator built from directory/file
structure, grep and reachability analysis, not an audited final one.

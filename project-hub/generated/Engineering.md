---
type: index
generated: true
---

# Engineering

Generated navigation; edit source files or `scripts/sync_project_vault.py`, then regenerate.
These links do not certify current runtime behavior, review approval, or launch readiness.

[Project home](../Home.md)

## .

- [pubspec.yaml](../../pubspec.yaml)

## docs

- [database-migration-strategy.md](../../docs/database-migration-strategy.md)

## lib

- [main.dart](../../lib/main.dart)

## lib/core/auth

- [auth_controller.dart](../../lib/core/auth/auth_controller.dart)

## lib/core/config

- [app_environment.dart](../../lib/core/config/app_environment.dart)

## lib/core/data

- [countries.dart](../../lib/core/data/countries.dart)
- [iso_countries.dart](../../lib/core/data/iso_countries.dart)

## lib/core/errors

- [app_error_reporter.dart](../../lib/core/errors/app_error_reporter.dart)
- [failures.dart](../../lib/core/errors/failures.dart)

## lib/core/localization

- [app_locale_controller.dart](../../lib/core/localization/app_locale_controller.dart)

## lib/core/models

- [cycle_log.dart](../../lib/core/models/cycle_log.dart)
- [madhhab_type.dart](../../lib/core/models/madhhab_type.dart)
- [user_profile.dart](../../lib/core/models/user_profile.dart)

## lib/core/network

- [supabase_client.dart](../../lib/core/network/supabase_client.dart)

## lib/core/preferences

- [madhhab_controller.dart](../../lib/core/preferences/madhhab_controller.dart)
- [marital_status_controller.dart](../../lib/core/preferences/marital_status_controller.dart)
- [notification_log_controller.dart](../../lib/core/preferences/notification_log_controller.dart)
- [prayer_location_controller.dart](../../lib/core/preferences/prayer_location_controller.dart)
- [pregnancy_status_controller.dart](../../lib/core/preferences/pregnancy_status_controller.dart)
- [ttc_mode_controller.dart](../../lib/core/preferences/ttc_mode_controller.dart)

## lib/core/services

- [cycle_log_repository.dart](../../lib/core/services/cycle_log_repository.dart)
- [notification_service.dart](../../lib/core/services/notification_service.dart)
- [user_profile_repository.dart](../../lib/core/services/user_profile_repository.dart)

## lib/core/storage

- [local_sensitive_data_cleanup.dart](../../lib/core/storage/local_sensitive_data_cleanup.dart)
- [secure_local_store.dart](../../lib/core/storage/secure_local_store.dart)

## lib/core/theme

- [app_radius.dart](../../lib/core/theme/app_radius.dart)
- [app_spacing.dart](../../lib/core/theme/app_spacing.dart)
- [app_theme.dart](../../lib/core/theme/app_theme.dart)
- [app_theme_controller.dart](../../lib/core/theme/app_theme_controller.dart)

## lib/core/utils

- [app_clock.dart](../../lib/core/utils/app_clock.dart)

## lib/core/widgets

- [common_widgets.dart](../../lib/core/widgets/common_widgets.dart)
- [empty_state.dart](../../lib/core/widgets/empty_state.dart)
- [floating_nav_bar.dart](../../lib/core/widgets/floating_nav_bar.dart)
- [load_error_banner.dart](../../lib/core/widgets/load_error_banner.dart)
- [niswah_loading_indicator.dart](../../lib/core/widgets/niswah_loading_indicator.dart)
- [niswah_logo.dart](../../lib/core/widgets/niswah_logo.dart)
- [rating_scale_row.dart](../../lib/core/widgets/rating_scale_row.dart)
- [selectable_chip.dart](../../lib/core/widgets/selectable_chip.dart)
- [user_avatar.dart](../../lib/core/widgets/user_avatar.dart)

## supabase/functions

- [.env.example](../../supabase/functions/.env.example)
- [deno.json](../../supabase/functions/deno.json)
- [deno.lock](../../supabase/functions/deno.lock)

## supabase/functions/_shared

- [ai_user_context.test.ts](../../supabase/functions/_shared/ai_user_context.test.ts)
- [ai_user_context.ts](../../supabase/functions/_shared/ai_user_context.ts)
- [fiqh_state_guard.test.ts](../../supabase/functions/_shared/fiqh_state_guard.test.ts)
- [fiqh_state_guard.ts](../../supabase/functions/_shared/fiqh_state_guard.ts)
- [kb_relevance_gate.test.ts](../../supabase/functions/_shared/kb_relevance_gate.test.ts)
- [kb_relevance_gate.ts](../../supabase/functions/_shared/kb_relevance_gate.ts)
- [kb_retrieval.test.ts](../../supabase/functions/_shared/kb_retrieval.test.ts)
- [kb_retrieval.ts](../../supabase/functions/_shared/kb_retrieval.ts)
- [openai_client.test.ts](../../supabase/functions/_shared/openai_client.test.ts)
- [openai_client.ts](../../supabase/functions/_shared/openai_client.ts)
- [pregnancy_status.test.ts](../../supabase/functions/_shared/pregnancy_status.test.ts)
- [pregnancy_status.ts](../../supabase/functions/_shared/pregnancy_status.ts)
- [rate_limit.ts](../../supabase/functions/_shared/rate_limit.ts)

## supabase/functions/ai-assistant-chat

- [index.ts](../../supabase/functions/ai-assistant-chat/index.ts)

## supabase/functions/dr-niswah-chat

- [index.ts](../../supabase/functions/dr-niswah-chat/index.ts)

## supabase/functions/dream-interpreter-chat

- [index.ts](../../supabase/functions/dream-interpreter-chat/index.ts)

## supabase/functions/fiqh-advisor-chat

- [index.ts](../../supabase/functions/fiqh-advisor-chat/index.ts)

## supabase/migrations

- [20260906090000_ai_rate_limit.sql](../../supabase/migrations/20260906090000_ai_rate_limit.sql)
- [20260909100000_wellbeing_logs_notes.sql](../../supabase/migrations/20260909100000_wellbeing_logs_notes.sql)
- [20260914120000_madhhab_authority_state.sql](../../supabase/migrations/20260914120000_madhhab_authority_state.sql)
- [20260914120100_madhhab_authority_drop_legacy_uppercase_check.sql](../../supabase/migrations/20260914120100_madhhab_authority_drop_legacy_uppercase_check.sql)
- [20260929114500_knowledge_base_v1.sql](../../supabase/migrations/20260929114500_knowledge_base_v1.sql)
- [20260929120000_knowledge_base_v1_qualification_and_snapshot.sql](../../supabase/migrations/20260929120000_knowledge_base_v1_qualification_and_snapshot.sql)
- [20260930130000_retrieve_knowledge_v1_relevance_anchor.sql](../../supabase/migrations/20260930130000_retrieve_knowledge_v1_relevance_anchor.sql)
- [20261015105437_admin_dashboard.sql](../../supabase/migrations/20261015105437_admin_dashboard.sql)

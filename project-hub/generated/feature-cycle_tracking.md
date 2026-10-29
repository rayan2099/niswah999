---
type: feature
generated: true
---

# Cycle Tracking

Generated navigation; edit source files or `scripts/sync_project_vault.py`, then regenerate.
These links do not certify current runtime behavior, review approval, or launch readiness.

[Project home](../Home.md)

## Implementation

- [local_cycle_tracking_data_source.dart](../../lib/features/cycle_tracking/data/datasources/local_cycle_tracking_data_source.dart)
- [cycle_log_draft_store.dart](../../lib/features/cycle_tracking/data/local/cycle_log_draft_store.dart)
- [pending_bleeding_operation_store.dart](../../lib/features/cycle_tracking/data/local/pending_bleeding_operation_store.dart)
- [bleeding_episode_repository_impl.dart](../../lib/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart)
- [cycle_entries_projection.dart](../../lib/features/cycle_tracking/data/repositories/cycle_entries_projection.dart)
- [cycle_tracking_repository_impl.dart](../../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart)
- [cycle_tracking_controller.dart](../../lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart)
- [bleeding_episode.dart](../../lib/features/cycle_tracking/domain/entities/bleeding_episode.dart)
- [cycle_log.dart](../../lib/features/cycle_tracking/domain/entities/cycle_log.dart)
- [evidence_provenance.dart](../../lib/features/cycle_tracking/domain/entities/evidence_provenance.dart)
- [load_result.dart](../../lib/features/cycle_tracking/domain/entities/load_result.dart)
- [cycle_tracking_repository.dart](../../lib/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart)
- [canonical_bleeding_status_resolver.dart](../../lib/features/cycle_tracking/domain/services/canonical_bleeding_status_resolver.dart)
- [canonical_fiqh_assessment.dart](../../lib/features/cycle_tracking/domain/services/canonical_fiqh_assessment.dart)
- [canonical_fiqh_evidence_adapter.dart](../../lib/features/cycle_tracking/domain/services/canonical_fiqh_evidence_adapter.dart)
- [cycle_calculation_service.dart](../../lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart)
- [cycle_segment_planner.dart](../../lib/features/cycle_tracking/domain/services/cycle_segment_planner.dart)
- [cycle_status_engine.dart](../../lib/features/cycle_tracking/domain/services/cycle_status_engine.dart)
- [cycle_symptom_decoder.dart](../../lib/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart)
- [madhhab_rule_evaluator.dart](../../lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart)
- [report_canonical_evidence.dart](../../lib/features/cycle_tracking/domain/services/report_canonical_evidence.dart)
- [cycle_log_form_data.dart](../../lib/features/cycle_tracking/presentation/models/cycle_log_form_data.dart)
- [canonical_calendar_screen.dart](../../lib/features/cycle_tracking/presentation/screens/canonical_calendar_screen.dart)
- [cycle_tracking_screen.dart](../../lib/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart)
- [cycle_tracking_view_model.dart](../../lib/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart)
- [correction_sheet.dart](../../lib/features/cycle_tracking/presentation/widgets/correction_sheet.dart)
- [cycle_calendar.dart](../../lib/features/cycle_tracking/presentation/widgets/cycle_calendar.dart)
- [cycle_log_form_sheet.dart](../../lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart)
- [daily_checkin_sheet.dart](../../lib/features/cycle_tracking/presentation/widgets/daily_checkin_sheet.dart)
- [log_day_entry_router.dart](../../lib/features/cycle_tracking/presentation/widgets/log_day_entry_router.dart)
- [observation_detail_sheet.dart](../../lib/features/cycle_tracking/presentation/widgets/observation_detail_sheet.dart)
- [predicted_range_text.dart](../../lib/features/cycle_tracking/presentation/widgets/predicted_range_text.dart)
- [provenance_badge.dart](../../lib/features/cycle_tracking/presentation/widgets/provenance_badge.dart)
- [start_bleeding_sheet.dart](../../lib/features/cycle_tracking/presentation/widgets/start_bleeding_sheet.dart)

## Test navigation hints

Filename matches only; inspect imports and behavior to establish actual coverage.

- [cycle_tracking_controller_test.dart](../../test/cycle_tracking_controller_test.dart)
- [cycle_tracking_ui_flow_test.dart](../../test/cycle_tracking_ui_flow_test.dart)

## Related features to inspect

- [Dashboard](feature-dashboard.md)
- [Insights](feature-insights.md)
- [Fiqh Report](feature-fiqh_report.md)
- [Notifications](feature-notifications.md)

## Requirements, decisions, and verification

Read the [document catalog](Documents.md) and [work queue](../Work-Queue.md). Add explicit links from authored decision/work notes to this feature. Existing audit reports are dated evidence; check their scope and freshness.

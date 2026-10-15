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
- [cycle_tracking_repository_impl.dart](../../lib/features/cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart)
- [cycle_tracking_controller.dart](../../lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart)
- [cycle_log.dart](../../lib/features/cycle_tracking/domain/entities/cycle_log.dart)
- [cycle_tracking_repository.dart](../../lib/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart)
- [cycle_calculation_service.dart](../../lib/features/cycle_tracking/domain/services/cycle_calculation_service.dart)
- [cycle_segment_planner.dart](../../lib/features/cycle_tracking/domain/services/cycle_segment_planner.dart)
- [cycle_status_engine.dart](../../lib/features/cycle_tracking/domain/services/cycle_status_engine.dart)
- [cycle_symptom_decoder.dart](../../lib/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart)
- [madhhab_rule_evaluator.dart](../../lib/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart)
- [cycle_log_form_data.dart](../../lib/features/cycle_tracking/presentation/models/cycle_log_form_data.dart)
- [cycle_tracking_screen.dart](../../lib/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart)
- [cycle_tracking_view_model.dart](../../lib/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart)
- [cycle_calendar.dart](../../lib/features/cycle_tracking/presentation/widgets/cycle_calendar.dart)
- [cycle_log_form_sheet.dart](../../lib/features/cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart)

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

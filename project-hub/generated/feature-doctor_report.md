---
type: feature
generated: true
---

# Doctor Report

Generated navigation; edit source files or `scripts/sync_project_vault.py`, then regenerate.
These links do not certify current runtime behavior, review approval, or launch readiness.

[Project home](../Home.md)

## Implementation

- [flagged_conversations_repository.dart](../../lib/features/doctor_report/data/repositories/flagged_conversations_repository.dart)
- [flagged_conversation.dart](../../lib/features/doctor_report/domain/entities/flagged_conversation.dart)
- [report_completeness.dart](../../lib/features/doctor_report/domain/entities/report_completeness.dart)
- [report_source_status.dart](../../lib/features/doctor_report/domain/entities/report_source_status.dart)
- [doctor_report_insights_engine.dart](../../lib/features/doctor_report/domain/services/doctor_report_insights_engine.dart)
- [doctor_report_pdf_builder.dart](../../lib/features/doctor_report/presentation/pdf/doctor_report_pdf_builder.dart)
- [doctor_report_screen.dart](../../lib/features/doctor_report/presentation/screens/doctor_report_screen.dart)

## Test navigation hints

Filename matches only; inspect imports and behavior to establish actual coverage.

- [doctor_report_pdf_builder_test.dart](../../test/doctor_report_pdf_builder_test.dart)
- [doctor_report_source_loading_test.dart](../../test/doctor_report_source_loading_test.dart)
- [doctor_report_insights_engine_test.dart](../../test/services/doctor_report_insights_engine_test.dart)

## Requirements, decisions, and verification

Read the [document catalog](Documents.md) and [work queue](../Work-Queue.md). Add explicit links from authored decision/work notes to this feature. Existing audit reports are dated evidence; check their scope and freshness.

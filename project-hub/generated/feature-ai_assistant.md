---
type: feature
generated: true
---

# Ai Assistant

Generated navigation; edit source files or `scripts/sync_project_vault.py`, then regenerate.
These links do not certify current runtime behavior, review approval, or launch readiness.

[Project home](../Home.md)

## Implementation

- [chat_repository_impl.dart](../../lib/features/ai_assistant/data/repositories/chat_repository_impl.dart)
- [dr_niswah_backend_service.dart](../../lib/features/ai_assistant/data/services/dr_niswah_backend_service.dart)
- [chat_message.dart](../../lib/features/ai_assistant/domain/entities/chat_message.dart)
- [chat_thread.dart](../../lib/features/ai_assistant/domain/entities/chat_thread.dart)
- [chat_repository.dart](../../lib/features/ai_assistant/domain/repositories/chat_repository.dart)
- [answer_notice_policy.dart](../../lib/features/ai_assistant/domain/services/answer_notice_policy.dart)
- [dr_niswah_red_flags.dart](../../lib/features/ai_assistant/domain/services/dr_niswah_red_flags.dart)
- [dr_niswah_chat_screen.dart](../../lib/features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart)
- [chat_view_model.dart](../../lib/features/ai_assistant/presentation/viewmodels/chat_view_model.dart)

## Test navigation hints

Filename matches only; inspect imports and behavior to establish actual coverage.

No filename matches. Search `test/` and inspect dependencies before concluding coverage is missing.

## Backend entry point

- [index.ts](../../supabase/functions/dr-niswah-chat/index.ts)

## Related features to inspect

- [Pregnancy Profile](feature-pregnancy_profile.md)
- [Doctor Report](feature-doctor_report.md)

## Requirements, decisions, and verification

Read the [document catalog](Documents.md) and [work queue](../Work-Queue.md). Add explicit links from authored decision/work notes to this feature. Existing audit reports are dated evidence; check their scope and freshness.

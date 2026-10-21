// Onboarding/server hardening regression (finding #10): the "Export My Data"
// sections (data_export_builder.dart exportSections) omitted health/personal
// tables the app itself writes, yet the export reported
// `export_complete: true`. Asserts the complete coverage.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/legal/domain/data_export_builder.dart';

void main() {
  test('R2-EXP-1: every user-owned table the app writes is exported', () {
    final exported = exportSections.map((s) => s.table).toSet();
    // Each is written by app code: wellbeing_repository.dart (mood/sleep +
    // free-text notes), dream_interpreter_repository_impl.dart,
    // madhhab_controller/madhhab history writes, cycle_tracking legacy
    // cycle_logs, private_messaging, community comments/likes.
    const written = {
      'wellbeing_logs',
      'dream_entries',
      'madhhab_history',
      'cycle_logs',
      'private_conversations',
      'private_messages',
      'community_comments',
      'community_likes',
    };
    expect(written.difference(exported), isEmpty);
  });

  test('R2-EXP-2: conversations are matched on either participant', () {
    final conversations = exportSections.firstWhere(
      (s) => s.table == 'private_conversations',
    );
    expect(
      conversations.matchAny,
      containsAll(['participant_one', 'participant_two']),
    );
  });
}

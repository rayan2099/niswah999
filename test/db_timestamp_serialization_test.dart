import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/db_timestamp.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';
import 'package:niswah/features/community/domain/entities/community_comment.dart';
import 'package:niswah/features/community/domain/entities/community_post.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/dream_interpreter/domain/entities/dream_entry.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/wellbeing/domain/entities/wellbeing_log.dart';

/// Found live: a device at UTC+3 wrote `pregnancy_profile.manual_week_set_at`
/// and `wellbeing_logs.created_at` exactly 3 hours ahead of the server clock,
/// because a local DateTime's toIso8601String() has no zone designator and
/// Postgres reads it as UTC. Every timestamptz field a client writes must carry
/// an explicit UTC designator, whatever the machine's own zone is (so this holds
/// on a UTC CI runner too).
void main() {
  final local = DateTime(2026, 9, 26, 23, 15, 37, 244); // a LOCAL instant

  void expectUtc(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k] as String;
      expect(v, endsWith('Z'), reason: '$k = $v has no UTC designator');
      expect(
        DateTime.parse(v).isAtSameMomentAs(local),
        isTrue,
        reason: '$k = $v is not the same instant as the local time written',
      );
    }
  }

  test('dbTimestamp is the same instant, marked UTC', () {
    expect(dbTimestamp(local), endsWith('Z'));
    expect(DateTime.parse(dbTimestamp(local)).isAtSameMomentAs(local), isTrue);
  });

  test('pregnancy_profile', () {
    final json = PregnancyProfile(
      id: 'p',
      userId: 'u',
      trackingBasis: TrackingBasis.manualWeek,
      manualWeekValue: 12,
      manualWeekSetAt: local,
      updatedAt: local,
    ).toJson();
    expectUtc(json, ['manual_week_set_at', 'updated_at']);
  });

  test('wellbeing_logs', () {
    final json = WellbeingLog(
      id: 'w',
      userId: 'u',
      logDate: DateTime(2026, 9, 26),
      mood: 3,
      energy: 3,
      sleep: 3,
      createdAt: local,
      updatedAt: local,
    ).toJson();
    expectUtc(json, ['created_at', 'updated_at']);
  });

  test('chat_messages / chat_threads', () {
    expectUtc(
      ChatMessage(
        id: 'm',
        threadId: 't',
        userId: 'u',
        role: ChatRole.user,
        content: 'x',
        metadata: const {},
        createdAt: local,
      ).toJson(),
      ['created_at'],
    );
    expectUtc(
      ChatThread(
        id: 't',
        userId: 'u',
        title: 'x',
        threadType: ChatThreadType.general,
        status: ChatThreadStatus.active,
        metadata: const {},
        createdAt: local,
        updatedAt: local,
      ).toJson(),
      ['created_at', 'updated_at'],
    );
  });

  test('community_posts / community_comments', () {
    expectUtc(
      CommunityPost(
        id: 'p',
        userId: 'u',
        authorName: 'a',
        title: 't',
        content: 'c',
        category: CommunityCategory.support,
        tags: const [],
        isAnonymous: false,
        createdAt: local,
      ).toJson(),
      ['created_at'],
    );
    expectUtc(
      CommunityComment(
        id: 'c',
        postId: 'p',
        userId: 'u',
        authorName: 'a',
        content: 'x',
        createdAt: local,
      ).toJson(),
      ['created_at'],
    );
  });

  test('dream_entries / cycle_entries', () {
    expectUtc(
      DreamEntry(
        id: 'd',
        userId: 'u',
        title: 't',
        description: 'x',
        mood: DreamMood.peaceful,
        tags: const [],
        createdAt: local,
      ).toJson(),
      ['created_at'],
    );
    final json = CycleLog(
      id: 'c',
      userId: 'u',
      date: DateTime(2026, 9, 26),
      flow: FlowLevel.medium,
      createdAt: local,
      updatedAt: local,
    ).toJson();
    expectUtc(json, ['time_logged', 'created_at', 'updated_at']);
  });
}

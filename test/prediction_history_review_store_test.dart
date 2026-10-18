import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/cycle_tracking/data/local/prediction_history_review_store.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/prediction_history_review.dart';

void main() {
  late Map<String, String> disk;
  late PredictionHistoryReviewStore store;
  PredictionHistoryReview review(int day, PredictionGapResolution resolution) =>
      PredictionHistoryReview(
        start: DateTime.utc(2025, 1, day),
        end: DateTime.utc(2025, 9, day),
        resolution: resolution,
        reportedAt: DateTime.utc(2026, 1, day),
      );
  setUp(() {
    disk = {};
    store = PredictionHistoryReviewStore(
      read: (owner) async => disk[owner],
      write: (owner, value) async {
        disk[owner] = value;
      },
    );
  });
  test(
    'a fresh account has no answers and answers are isolated by owner',
    () async {
      await store.save('alice', review(1, PredictionGapResolution.unsure));
      expect(
        (await store.load('alice')).single.resolution,
        PredictionGapResolution.unsure,
      );
      expect(await store.load('bob'), isEmpty);
    },
  );
  test(
    'simultaneous saves from different screen stores retain both answers',
    () async {
      final other = PredictionHistoryReviewStore(
        read: store.read,
        write: store.write,
      );
      await Future.wait([
        store.save('alice', review(1, PredictionGapResolution.unsure)),
        other.save('alice', review(2, PredictionGapResolution.missedRecords)),
      ]);
      expect((await store.load('alice')).length, 2);
    },
  );
  test('changing an answer replaces only that exact interval', () async {
    await store.save('alice', review(1, PredictionGapResolution.unsure));
    await store.save('alice', review(2, PredictionGapResolution.unsure));
    await store.save('alice', review(1, PredictionGapResolution.longerCycle));
    final saved = await store.load('alice');
    expect(saved.length, 2);
    expect(
      saved
          .singleWhere(
            (r) => r.key == review(1, PredictionGapResolution.unsure).key,
          )
          .resolution,
      PredictionGapResolution.longerCycle,
    );
  });
  test(
    'malformed storage fails explicitly instead of fabricating no answers',
    () async {
      disk['alice'] = '{invalid';
      await expectLater(store.load('alice'), throwsFormatException);
      await expectLater(
        store.save('alice', review(1, PredictionGapResolution.unsure)),
        throwsFormatException,
      );
      expect(disk['alice'], '{invalid');
    },
  );
  test('unknown schema or unknown answer is not silently accepted', () async {
    disk['alice'] = jsonEncode({'version': 2, 'reviews': []});
    await expectLater(store.load('alice'), throwsFormatException);
    disk['alice'] = jsonEncode({
      'version': 1,
      'reviews': [
        {
          ...review(1, PredictionGapResolution.unsure).toJson(),
          'resolution': 'healthy',
        },
      ],
    });
    await expectLater(store.load('alice'), throwsArgumentError);
  });
  test('unverified writes fail and do not emit a successful change', () async {
    final broken = PredictionHistoryReviewStore(
      read: (_) async => null,
      write: (_, _) async {},
    );
    await expectLater(
      broken.save('alice', review(1, PredictionGapResolution.unsure)),
      throwsStateError,
    );
    await store.save('alice', review(1, PredictionGapResolution.unsure));
    expect((await store.load('alice')).length, 1);
  });
  test('verified writes announce the owning account only', () async {
    final changed = PredictionHistoryReviewStore.changes.first;
    await store.save('alice', review(1, PredictionGapResolution.unsure));
    expect(await changed, 'alice');
  });
  test('invalid endpoint order cannot poison a stored review list', () async {
    final invalid = PredictionHistoryReview(
      start: DateTime.utc(2026, 2, 1),
      end: DateTime.utc(2026, 1, 1),
      resolution: PredictionGapResolution.unsure,
      reportedAt: DateTime.utc(2026, 3, 1),
    );
    await expectLater(store.save('alice', invalid), throwsFormatException);
    expect(disk, isEmpty);
  });
  test('account cleanup can wait for an in-flight write before deleting its category', () async {
    final release = Completer<void>();
    final blocked = PredictionHistoryReviewStore(
      read: store.read,
      write: (owner, raw) async {
        await release.future;
        disk[owner] = raw;
      },
    );
    final saving = blocked.save(
      'alice',
      review(1, PredictionGapResolution.unsure),
    );
    await Future<void>.delayed(Duration.zero);
    var cleared = false;
    final cleanup = PredictionHistoryReviewStore.waitForPendingWrites('alice')
        .then((_) {
          disk.remove('alice');
          cleared = true;
        });
    await Future<void>.delayed(Duration.zero);
    expect(cleared, isFalse);
    release.complete();
    await saving;
    await cleanup;
    expect(cleared, isTrue);
    expect(disk['alice'], isNull);
  });
}

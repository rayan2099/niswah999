import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/storage/scoped_mutation_queue.dart';

void main() {
  test(
    'same-owner mutations retain invocation order even across suspension',
    () async {
      final release = Completer<void>();
      final events = <String>[];
      final first = ScopedMutationQueue.run(
        category: 'test',
        owner: 'a',
        action: () async {
          events.add('first-start');
          await release.future;
          events.add('first-end');
        },
      );
      final second = ScopedMutationQueue.run(
        category: 'test',
        owner: 'a',
        action: () async {
          events.add('second');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['first-start']);
      release.complete();
      await Future.wait([first, second]);
      expect(events, ['first-start', 'first-end', 'second']);
    },
  );
  test('a suspended owner cannot block another owner or category', () async {
    final release = Completer<void>();
    final first = ScopedMutationQueue.run(
      category: 'test',
      owner: 'a',
      action: () => release.future,
    );
    try {
      expect(
        await ScopedMutationQueue.run(
          category: 'test',
          owner: 'b',
          action: () async => 2,
        ),
        2,
      );
      expect(
        await ScopedMutationQueue.run(
          category: 'other',
          owner: 'a',
          action: () async => 3,
        ),
        3,
      );
    } finally {
      release.complete();
      await first;
    }
  });
  test(
    'a failed mutation fails its caller without poisoning later work',
    () async {
      final first = ScopedMutationQueue.run(
        category: 'test',
        owner: 'a',
        action: () async => throw StateError('synthetic failure'),
      );
      final rejected = expectLater(first, throwsStateError);
      final second = ScopedMutationQueue.run(
        category: 'test',
        owner: 'a',
        action: () async => 4,
      );
      await rejected;
      expect(await second, 4);
    },
  );
}

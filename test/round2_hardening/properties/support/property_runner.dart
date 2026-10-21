// Seeded property runner: generates [count] histories from consecutive
// seeds, runs [check] on each, and on failure prints the seed, the
// original failing history and a greedily shrunk minimal history.
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_history.dart';

/// Incremented by checks for every single evaluation (history × today ×
/// madhhab …) so the run reports how many generated cases it covered.
int evaluationCounter = 0;

void property(
  String name, {
  required int seedBase,
  int count = 150,
  String? Function(int seed)? kindFor,
  SynthHistory Function(SynthHistory)? adapt,
  required String? Function(SynthHistory h) check,
  int maxReported = 3,
}) {
  test(name, () {
    final failures = <String>[];
    final before = evaluationCounter;
    for (var i = 0; i < count; i++) {
      final seed = seedBase + i;
      var h = generateHistory(seed, forcedKind: kindFor?.call(seed));
      if (adapt != null) h = adapt(h);
      final message = check(h);
      if (message == null) continue;
      failures.add('seed=$seed $message');
      if (failures.length <= maxReported) {
        final minimal = shrink(h, (c) => check(c) != null);
        // ignore: avoid_print
        print(
          '\n=== [$name] FAILED seed=$seed (kind=${h.kind})\n'
          '$message\n--- original history\n${h.describe()}'
          '--- minimal failing history\n${minimal.describe()}'
          '--- minimal failure: ${check(minimal)}\n',
        );
      }
    }
    final cases = evaluationCounter - before;
    // ignore: avoid_print
    print(
      'PROPERTY [$name] histories=$count evaluations=$cases '
      'failingHistories=${failures.length}',
    );
    expect(
      failures,
      isEmpty,
      reason: failures.isEmpty
          ? null
          : '[$name] ${failures.length}/$count generated histories violate '
                'the invariant; first: ${failures.first}',
    );
  });
}

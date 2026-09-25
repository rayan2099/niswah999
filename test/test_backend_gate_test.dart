import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/config/test_backend_gate.dart';

/// Production kill switch. The vectors are shared with the host-side
/// Python checker (scripts/test_assert_test_backend.py) so the two
/// implementations cannot drift.
void main() {
  final vectors =
      (jsonDecode(
            File('test/fixtures/backend_gate_vectors.json').readAsStringSync(),
          ) as Map<String, dynamic>)['vectors']
          as List<dynamic>;

  group('TestBackendGate shared vectors', () {
    for (final raw in vectors) {
      final v = raw as Map<String, dynamic>;
      test(v['name'] as String, () {
        final env = (v['env'] as Map<String, dynamic>).map(
          (k, val) => MapEntry(k, val as String),
        );
        final approved = ((v['approved_hosts'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toSet();
        final verdict = TestBackendGate.evaluateEnvironment(
          env,
          approvedHosts: approved,
        );
        expect(verdict.allowed, v['expected'] == 'allowed', reason: '$verdict');
      });
    }
  });

  group('TestBackendGate invariants', () {
    test('no hosted test project is approved by default', () {
      expect(TestBackendGate.approvedTestHosts, isEmpty);
    });

    test('a refusal names only the safe host, never a path or credential', () {
      final v = TestBackendGate.evaluate(
        'https://jkmjobvxfrmuwafczvtw.supabase.co/rest/v1/?apikey=SECRETKEY',
      );
      expect(v.allowed, isFalse);
      expect(v.host, 'jkmjobvxfrmuwafczvtw.supabase.co');
      expect('$v', isNot(contains('SECRETKEY')));
      expect('$v', isNot(contains('apikey')));
    });

    test('a port is preserved in the safe identifier', () {
      expect(
        TestBackendGate.evaluate('http://127.0.0.1:54321').host,
        '127.0.0.1:54321',
      );
    });

    test('the production host is on the denylist', () {
      expect(
        TestBackendGate.productionHosts,
        contains('jkmjobvxfrmuwafczvtw.supabase.co'),
      );
    });
  });
}

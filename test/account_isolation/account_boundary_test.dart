import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/auth/account_route_boundary.dart';
import 'package:niswah/features/legal/domain/data_export_builder.dart';

/// Account boundaries for screens opened over home (NJ-071, NJ-182) and
/// for a data export that runs across an account switch (NJ-232).
/// Synthetic account ids only.
class _SwitchingFetcher implements ExportSectionFetcher {
  _SwitchingFetcher(this.onCall);

  final void Function(int call) onCall;
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> fetchOne(
    String table,
    String userId, {
    String idColumn = 'user_id',
  }) async {
    onCall(++calls);
    return {'user_id': userId};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMany(
    String table,
    String userId, {
    List<String> matchAny = const ['user_id'],
  }) async {
    onCall(++calls);
    return [
      {'user_id': userId},
    ];
  }
}

void main() {
  group('AccountRouteBoundary', () {
    late ValueNotifier<String?> account;
    late NavigatorObserver observer;
    late AccountRouteBoundary boundary;

    setUp(() {
      account = ValueNotifier<String?>('account-a');
      observer = NavigatorObserver();
      boundary = AccountRouteBoundary(
        auth: account,
        currentAccount: () => account.value,
        navigatorObserver: observer,
      );
    });

    tearDown(() => boundary.dispose());

    Future<void> openScreenAndSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: const Text('home')),
      );
      observer.navigator!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('export of A')),
      );
      await tester.pumpAndSettle();
      showModalBottomSheet<void>(
        context: observer.navigator!.context,
        builder: (_) => const Text('sheet of A'),
      );
      await tester.pumpAndSettle();
      expect(find.text('sheet of A'), findsOneWidget);
    }

    testWidgets('sign-out closes screens and sheets opened over home', (
      tester,
    ) async {
      await openScreenAndSheet(tester);
      account.value = null;
      await tester.pumpAndSettle();
      expect(find.text('export of A'), findsNothing);
      expect(find.text('sheet of A'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a direct switch to another account closes them too', (
      tester,
    ) async {
      await openScreenAndSheet(tester);
      account.value = 'account-b';
      await tester.pumpAndSettle();
      expect(find.text('export of A'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('signing in from signed out leaves the sign-in sheet alone', (
      tester,
    ) async {
      account.value = null;
      await openScreenAndSheet(tester);
      account.value = 'account-a';
      await tester.pumpAndSettle();
      expect(find.text('sheet of A'), findsOneWidget);
    });

    testWidgets('the same account refreshing its session keeps them open', (
      tester,
    ) async {
      await openScreenAndSheet(tester);
      // A token refresh notifies listeners without changing the account.
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('sheet of A'), findsOneWidget);
    });
  });

  group('buildDataExport across an account switch (NJ-232)', () {
    test('a switch mid-export discards everything fetched', () async {
      var current = 'account-a';
      final fetcher = _SwitchingFetcher((call) {
        if (call == 3) current = 'account-b';
      });
      await expectLater(
        buildDataExport(
          fetcher: fetcher,
          userId: 'account-a',
          onSectionError: (_, _, _) {},
          isCurrentAccount: () => current == 'account-a',
        ),
        throwsA(isA<ExportAccountChanged>()),
      );
      expect(fetcher.calls, 3, reason: 'no section is fetched after it');
    });

    test('A→B→A: a section read as B is never kept for A', () async {
      var current = 'account-a';
      final fetcher = _SwitchingFetcher((call) {
        // B is signed in while section 2 is read, then A signs back in.
        if (call == 2) current = 'account-b';
        if (call == 3) current = 'account-a';
      });
      await expectLater(
        buildDataExport(
          fetcher: fetcher,
          userId: 'account-a',
          onSectionError: (_, _, _) {},
          isCurrentAccount: () => current == 'account-a',
        ),
        throwsA(isA<ExportAccountChanged>()),
      );
    });

    test('an export that stays on one account completes', () async {
      final result = await buildDataExport(
        fetcher: _SwitchingFetcher((_) {}),
        userId: 'account-a',
        onSectionError: (_, _, _) {},
        isCurrentAccount: () => true,
      );
      expect(result.export['export_complete'], isTrue);
    });
  });
}

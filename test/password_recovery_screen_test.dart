import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/auth/presentation/screens/password_recovery_screen.dart';

void main() {
  testWidgets('rejects mismatched passwords before calling the server', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: PasswordRecoveryScreen(
      updatePassword: (_) async { calls++; },
    )));
    await tester.enterText(find.byKey(const Key('new_password')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password')), 'different123');
    await tester.tap(find.byKey(const Key('save_new_password')));
    await tester.pump();
    expect(calls, 0);
    expect(find.textContaining('غير متطابقتين'), findsOneWidget);
  });

  testWidgets('updates once and finishes after a successful save', (tester) async {
    String? sent;
    var completed = false;
    await tester.pumpWidget(MaterialApp(home: PasswordRecoveryScreen(
      updatePassword: (password) async { sent = password; },
      onComplete: () { completed = true; },
    )));
    await tester.enterText(find.byKey(const Key('new_password')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password')), 'password123');
    await tester.tap(find.byKey(const Key('save_new_password')));
    await tester.pumpAndSettle();
    expect(sent, 'password123');
    expect(completed, isTrue);
  });

  testWidgets('does not finish if the server rejects the update', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(home: PasswordRecoveryScreen(
      updatePassword: (_) async { throw Exception('failed'); },
      onComplete: () { completed = true; },
    )));
    await tester.enterText(find.byKey(const Key('new_password')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password')), 'password123');
    await tester.tap(find.byKey(const Key('save_new_password')));
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    expect(find.textContaining('تعذّر تحديث'), findsOneWidget);
  });
}

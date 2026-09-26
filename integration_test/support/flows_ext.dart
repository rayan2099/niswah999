import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flows.dart';

/// Extra reusable onboarding flows for the closure-wave personas.
extension StillBleedingFlow on Flows {
  /// Real onboarding with EXPLICIT answers: Hanafi (so the Fiqh state can be
  /// evaluated), married, Riyadh, a last period that started
  /// [startedDaysAgo] days ago and is STILL GOING (the app records an open
  /// canonical episode whose start observation has flow "uncertain", because
  /// onboarding never asks for a flow), usual duration 5 / cycle 28. Returns
  /// the account's email.
  Future<String> newAccountHanafiStillBleeding(
    String persona, {
    int startedDaysAgo = 3,
  }) async {
    await boot();
    final email = await signUpWithEmail(persona);
    h.note('$persona EMAIL $email');
    await h.tapVisible(find.text('Create Account'));
    await h.waitFor(
      find.text('Get Started'),
      timeout: const Duration(seconds: 25),
    );
    await h.settle(2);
    await h.tapVisible(find.text('Hanafi'));
    await h.settle(1);
    await h.tapVisible(find.text('Continue'));
    await h.settle(2);
    await h.tapVisible(find.text('Yes'));
    await h.settle(1);
    await h.tapVisible(find.text('Continue'));
    await h.settle(2);
    await h.tapVisible(find.text('Riyadh'));
    await t.pump(const Duration(seconds: 2));
    await h.settle(2);
    final openedStart = await h.tapVisible(find.text('Select the date'));
    if (openedStart) {
      await h.settle(1);
      await h.tapVisible(find.byTooltip('Switch to input'));
      await h.settle(1);
      final field = find.byType(TextField);
      if (field.evaluate().isNotEmpty) {
        final d = DateTime.now().subtract(Duration(days: startedDaysAgo));
        await t.enterText(
          field.first,
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.day.toString().padLeft(2, '0')}/${d.year}',
        );
        await t.pump(const Duration(milliseconds: 300));
        await h.tapVisible(find.text('OK'));
        await h.settle(1);
      }
    }
    await h.tapVisible(find.text('Continue'));
    await h.settle(2);
    await h.tapVisible(find.text('Yes, still going'));
    await h.settle(2);
    for (final value in ['5', '28']) {
      final field = find.byType(TextField);
      if (field.evaluate().isNotEmpty) {
        await t.enterText(field.first, value);
        await t.pump(const Duration(milliseconds: 300));
      }
      await h.tapVisible(find.text('Continue'));
      await h.settle(2);
    }
    await h.tapVisible(find.text('Continue')); // anonymous-mode step, default
    await h.settle(2);
    await h.tapVisible(find.text('Get Started'));
    await h.settle(3);
    return email;
  }
}

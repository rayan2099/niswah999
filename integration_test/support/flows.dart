import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Real-screen flows shared across personas. Every step drives the real
/// production widgets.
class Flows {
  Flows(this.h);
  final Harness h;
  WidgetTester get t => h.tester;

  Future<void> boot({bool english = true}) async {
    await h.requireApprovedBackend();
    await t.pump(const Duration(seconds: 5));
    await h.settle();
    if (english) {
      await h.tapVisible(find.text('EN'));
      await h.settle();
    }
  }

  /// Ticks the hand-drawn consent box (tapping the row center would hit the
  /// Privacy Policy link, exactly like a real user's thumb could).
  Future<void> acceptConsent() async {
    final box = find.descendant(
      of: find.byKey(const Key('consent_checkbox')),
      matching: find.byType(AnimatedContainer),
    );
    await h.tapVisible(box);
  }

  Future<String> signUpWithEmail(String persona) async {
    await h.requireApprovedBackend();
    await acceptConsent();
    await h.tapVisible(find.text('Email'));
    await h.settle();
    await h.tapVisible(find.byKey(const Key('mode_tab_sign_up')));
    await h.settle();
    final email =
        '$persona.${DateTime.now().millisecondsSinceEpoch}@example.test';
    final fields = {
      'Full name': 'Persona $persona',
      'Email': email,
      'Password': 'Test-Pass-12345',
    };
    for (final e in fields.entries) {
      final f = find.widgetWithText(TextField, e.key);
      if (f.evaluate().isEmpty) {
        h.note('MISSING FIELD ${e.key}');
        continue;
      }
      await t.enterText(f.first, e.value);
    }
    await t.pump(const Duration(milliseconds: 300));
    return email;
  }
}

extension OnboardingFlow on Flows {
  /// Walks the REAL onboarding by repeatedly pressing the first label found
  /// from [preferences] (highest priority first), screenshotting and dumping
  /// every step. Stops when none matches or [maxSteps] is reached.
  Future<void> walkOnboarding(
    String persona,
    List<String> preferences, {
    int maxSteps = 25,
  }) async {
    for (var i = 0; i < maxSteps; i++) {
      await h.settle(2);
      h.dumpTexts('$persona step $i');
      await h.shot(persona, 'onb_$i');
      String? pressed;
      for (final label in preferences) {
        final finder = find.text(label);
        if (finder.evaluate().isNotEmpty) {
          if (await h.tapVisible(finder)) {
            pressed = label;
            break;
          }
        }
      }
      h.note('$persona step $i pressed: ${pressed ?? '<none>'}');
      if (pressed == null) return;
      await t.pump(const Duration(seconds: 2));
    }
  }
}

extension AccountFlow on Flows {
  /// Fresh disposable account → real onboarding (UNKNOWN Madhhab, no
  /// menstrual history) → real dashboard. Returns the email.
  Future<String> newAccountOnDashboard(
    String persona, {
    bool english = true,
  }) async {
    await boot(english: english);
    final email = await signUpWithEmail(persona);
    h.note('$persona EMAIL $email');
    await h.tapVisible(find.text(english ? 'Create Account' : 'إنشاء حساب'));
    await h.waitFor(
      find.text('Get Started'),
      timeout: const Duration(seconds: 25),
    );
    await walkOnboarding(persona, [
      'Get Started',
      "I don't know my Madhhab",
      "I'll decide later",
      'Skip for now',
      'I’m not sure',
      'Continue',
    ], maxSteps: 12);
    return email;
  }
}

extension ReturningUserFlow on Flows {
  /// Real onboarding, but answering the last-period-history questions
  /// with REAL values instead of "I'm not sure": a real start date
  /// ([startDaysAgo] days ago), "No, it has stopped" + a real end date
  /// ([endDaysAgo] days ago), plus real usual-duration/usual-cycle-length
  /// numbers. Drives `record_onboarding_menstrual_history`'s real
  /// episode+baseline path — a genuinely historical, completed episode,
  /// never a seeded/injected row. Returns the account's email so a
  /// caller can also sign back into this exact account later if needed.
  Future<String> newAccountWithRealHistory(
    String persona, {
    int startDaysAgo = 32,
    int endDaysAgo = 27,
    int usualDurationDays = 5,
    int usualCycleLengthDays = 32,
    Future<void> Function()? beforeFinish,
  }) async {
    await boot();
    final email = await signUpWithEmail(persona);
    h.note('$persona EMAIL $email');
    await h.tapVisible(find.text('Create Account'));
    await h.waitFor(
      find.text('Get Started'),
      timeout: const Duration(seconds: 25),
    );

    final skipPreferences = [
      "I don't know my Madhhab",
      "I'll decide later",
      'Continue',
      'Skip for now',
    ];
    for (var i = 0; i < 4; i++) {
      await h.settle(2);
      h.dumpTexts('$persona pre-history step $i');
      for (final label in skipPreferences) {
        final finder = find.text(label);
        if (finder.evaluate().isNotEmpty && await h.tapVisible(finder)) break;
      }
      if (find
          .textContaining('When did your last period start?')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: startDaysAgo));
    final endDate = now.subtract(Duration(days: endDaysAgo));

    Future<bool> pickDateViaTextInput(DateTime date) async {
      await h.settle(1);
      await h.tapVisible(find.byTooltip('Switch to input'));
      await h.settle(1);
      final field = find.byType(TextField);
      if (field.evaluate().isEmpty) return false;
      final typed =
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.day.toString().padLeft(2, '0')}/${date.year}';
      await t.enterText(field.first, typed);
      await t.pump(const Duration(milliseconds: 300));
      final tappedOk = await h.tapVisible(find.text('OK'));
      await h.settle(1);
      return tappedOk;
    }

    final openedStartPicker = await h.tapVisible(find.text('Select the date'));
    h.note('$persona opened start-date picker: $openedStartPicker');
    final pickedStart = openedStartPicker
        ? await pickDateViaTextInput(startDate)
        : false;
    if (!pickedStart) {
      h.note('$persona ABORTED — could not pick the real start date');
      return email;
    }
    await h.tapVisible(find.text('Continue'));
    await h.settle(1);

    final tappedNo = await h.tapVisible(find.text('No, it has stopped'));
    h.note('$persona tapped "No, it has stopped": $tappedNo');
    await h.settle(1);
    if (tappedNo) {
      final openedEndPicker = await h.tapVisible(find.text('Select the date'));
      if (openedEndPicker) await pickDateViaTextInput(endDate);
      await h.tapVisible(find.text('Continue'));
      await h.settle(1);
    }

    var durationField = find.byType(TextField);
    if (durationField.evaluate().isNotEmpty) {
      await t.enterText(durationField.first, usualDurationDays.toString());
      await t.pump(const Duration(milliseconds: 300));
    }
    await h.tapVisible(find.text('Continue'));
    await h.settle(1);

    var cycleField = find.byType(TextField);
    if (cycleField.evaluate().isNotEmpty) {
      await t.enterText(cycleField.first, usualCycleLengthDays.toString());
      await t.pump(const Duration(milliseconds: 300));
    }
    await h.tapVisible(find.text('Continue'));
    await h.settle(1);

    for (var i = 0; i < 4; i++) {
      await h.settle(2);
      h.dumpTexts('$persona post-history step $i');
      if (find.text('Get Started').evaluate().isNotEmpty) {
        await beforeFinish?.call();
        await h.tapVisible(find.text('Get Started'));
        break;
      }
      await h.tapVisible(find.text('Continue'));
    }
    await h.settle(2);
    return email;
  }
}

extension EpisodeFlow on Flows {
  /// Real Start Bleeding sheet: Today + [flow], Save, then dismiss the
  /// contextual reminder prompt with "Not now" (persona G covers enabling).
  Future<void> startBleedingToday(
    String persona, {
    String flow = 'Medium',
  }) async {
    await h.tapVisible(find.text('Period Started'));
    await h.settle(2);
    await h.tapVisible(find.text('Today'), last: true);
    await h.tapVisible(find.text(flow));
    await h.tapVisible(find.text('Save'));
    await t.pump(const Duration(seconds: 6));
    await h.settle(2);
    if (find.text('Not now').evaluate().isNotEmpty) {
      await h.tapVisible(find.text('Not now'));
      await h.settle(2);
    }
    await t.drag(
      find.byType(Scrollable).first,
      const Offset(0, 2500),
      warnIfMissed: false,
    );
    await h.settle(1);
  }
}

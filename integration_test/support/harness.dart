import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Shared UI-acceptance helpers. Everything here drives the REAL app
/// (`main()`), never a replacement widget.
class Harness {
  Harness(this.binding, this.tester);

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;

  int _shotCounter = 0;

  /// Captures a screenshot named `<persona>_<nn>_<label>`.
  Future<void> shot(String persona, String label) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    _shotCounter++;
    final n = _shotCounter.toString().padLeft(2, '0');
    await binding.takeScreenshot('${persona}_${n}_$label');
  }

  Future<void> settle([int seconds = 3]) async {
    await tester.pumpAndSettle(Duration(seconds: seconds));
  }

  /// Pumps in small steps for up to [timeout] until [finder] matches —
  /// tolerant of real network latency without hanging on infinite
  /// animations (pumpAndSettle can time out on a live spinner).
  Future<bool> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  /// Scrolls [finder] into view, then taps it. Never throws — returns
  /// whether the target existed, so one missing control cannot discard
  /// every screenshot already captured in the run.
  Future<bool> tapVisible(Finder finder, {bool last = false}) async {
    try {
      if (finder.evaluate().isEmpty) return false;
      final target = last ? finder.last : finder.first;
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(target, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      return true;
    } catch (_) {
      return false;
    }
  }

  final List<String> notes = [];
  void note(String s) {
    notes.add(s);
    // ignore: avoid_print
    print('NOTE => $s');
  }

  Finder text(String s) => find.text(s);
  Finder textContaining(String s) => find.textContaining(s);

  String bannerText() {
    final finder = find.byKey(const Key('diagnostics_banner_text'));
    if (finder.evaluate().isEmpty) return '<no banner>';
    return (finder.evaluate().first.widget as Text).data ?? '<empty>';
  }
}

extension HarnessDump on Harness {
  /// Logs every visible Text string (deduped, in order) so a run's log
  /// shows exactly what the real screen presented.
  void dumpTexts(String label) {
    final seen = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (s.trim().isNotEmpty && !seen.contains(s)) seen.add(s);
    }
    note('TEXTS[$label] ${seen.join(' | ')}');
  }
}

/// One structured result for one acceptance test, per the acceptance
/// charter's own required schema. This is the SOLE source of truth for
/// whether a persona run counts as a pass — never `flutter drive`'s own
/// process exit code, which stays 0 even when a persona's own checks
/// fail (every assertion in these tests is a logged, non-throwing
/// check; see PersonaStatus's own doc comment for why).
enum PersonaStatus { pass, fail, blocked, skipped }

class PersonaResult {
  PersonaResult({
    required this.testId,
    required this.expectedOutcome,
    required this.actualOutcome,
    required this.status,
    this.screenshotRef,
  });

  final String testId;
  final String expectedOutcome;
  final String actualOutcome;
  final PersonaStatus status;
  final String? screenshotRef;

  Map<String, dynamic> toJson({
    required String testedSha,
    required String devicePlatform,
    required String backendEnvironment,
  }) => {
    'test_id': testId,
    'tested_sha': testedSha,
    'device_platform': devicePlatform,
    'backend_environment': backendEnvironment,
    'expected_outcome': expectedOutcome,
    'actual_outcome': actualOutcome,
    'status': status.name.toUpperCase(),
    if (screenshotRef != null) 'screenshot_ref': screenshotRef,
  };
}

extension HarnessReport on Harness {
  /// Writes the one structured result this test is graded on into
  /// `binding.reportData` — `flutter_driver`'s own host<->guest
  /// communication channel (`IntegrationTestWidgetsFlutterBinding.
  /// reportData`), which `test_driver/integration_test.dart`'s
  /// `responseDataCallback` forwards to a JSON file on the HOST after
  /// the run completes. `--dart-define=GIT_SHA`/`ENABLE_DIAGNOSTICS_
  /// SCREEN` are already used elsewhere in this suite for the exact
  /// same "confirm what was actually run" purpose.
  void reportResult(PersonaResult result) {
    const testedSha = String.fromEnvironment(
      'GIT_SHA',
      defaultValue: 'unknown',
    );
    const backend = String.fromEnvironment(
      'BACKEND_ENV',
      defaultValue: 'local-test:127.0.0.1:54321',
    );
    final json = result.toJson(
      testedSha: testedSha,
      devicePlatform: 'ios-simulator',
      backendEnvironment: backend,
    );
    binding.reportData = json;
    note('RESULT_JSON=${jsonEncode(json)}');
  }
}

extension HarnessScroll on Harness {
  /// Jumps the first real scrollable to the very top — a plain drag
  /// gesture can hit the wrong nested scrollable once the tree gets deep
  /// (horizontal chip lists, etc.), so this goes straight to the
  /// ScrollableState instead, exactly like this repo's own existing
  /// dashboard tests already do for the opposite (bottom) direction.
  Future<void> scrollToTop() async {
    final finder = find.byType(Scrollable);
    if (finder.evaluate().isEmpty) return;
    final state = tester.state<ScrollableState>(finder.first);
    state.position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

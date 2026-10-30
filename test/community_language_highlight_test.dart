import 'dart:async';

import 'package:flutter/material.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/community_language_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/parity_test_harness.dart';

/// Testing feedback 2026-10-30: Profile's community language row showed
/// neither Arabic nor English as selected although one had been chosen.
void main() {
  final controller = CommunityLanguageController.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller.resetInMemory();
  });
  tearDown(() {
    CommunityLanguageController.serverReadOverride = null;
    controller.resetInMemory();
  });

  test('a choice made while a load is in flight is not erased by it', () async {
    final server = Completer<CommunityLanguage?>();
    CommunityLanguageController.serverReadOverride = () => server.future;
    final loading = controller.load();
    await controller.select(CommunityLanguage.en);
    server.complete(null); // the older server read: nothing stored yet
    await loading;
    expect(controller.selectedOrNull, CommunityLanguage.en);
  });

  test('sign-out during a load keeps the next account unset', () async {
    final server = Completer<CommunityLanguage?>();
    CommunityLanguageController.serverReadOverride = () => server.future;
    final loading = controller.load();
    controller.resetInMemory();
    server.complete(CommunityLanguage.ar); // the previous account's value
    await loading;
    expect(controller.selectedOrNull, isNull);
  });

  test('the choice survives a restart from this device\'s cache', () async {
    CommunityLanguageController.serverReadOverride = () async => null;
    await controller.select(CommunityLanguage.en);
    controller.resetInMemory();
    await controller.load();
    expect(controller.selectedOrNull, CommunityLanguage.en);
  });

  testWidgets('Profile highlights the chosen community and switches', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    CommunityLanguageController.serverReadOverride = () async => null;
    await ParityTestHarness.pump(tester, arabic: true);
    await controller.select(CommunityLanguage.en);
    await tester.tap(find.text('الملف الشخصي').last);
    await tester.pumpAndSettle();
    final ar = find.byKey(const Key('community-language-ar'));
    final en = find.byKey(const Key('community-language-en'));
    await tester.scrollUntilVisible(
      ar,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(tester.getSemantics(en).flagsCollection.isSelected, Tristate.isTrue);
    expect(
      tester.getSemantics(ar).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(
      find.descendant(of: en, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
      reason: 'not color alone',
    );
    expect(tester.getSize(ar).height, greaterThanOrEqualTo(44));

    await tester.tap(ar);
    await tester.pumpAndSettle();
    expect(controller.selectedOrNull, CommunityLanguage.ar);
    expect(tester.getSemantics(ar).flagsCollection.isSelected, Tristate.isTrue);
    expect(
      tester.getSemantics(en).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    semantics.dispose();
  });
}

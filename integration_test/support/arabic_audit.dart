import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Arabic acceptance audit: run on every screen an Arabic persona visits.
///
/// Per screen it asserts:
///  * RTL: the screen's Directionality is right-to-left;
///  * no English-only remnants: any visible text that is Latin letters only
///    (>= 3 letters) is a finding unless it is a known brand/format token or
///    user-generated content the persona typed;
///  * dates: no English month name and no dd/mm/yyyy in Arabic mode;
///  * directional icons: every arrow/chevron icon mirrors with the text
///    direction (IconData.matchTextDirection), and a back button sits at the
///    RIGHT edge;
///  * no clipping/overflow: no framework exception at normal scale nor at 1.6x
///    text scale.
/// Findings accumulate in [findings]; a persona passes only if it is empty.
class ArabicAudit {
  ArabicAudit(this.h);

  final Harness h;
  WidgetTester get tester => h.tester;
  final List<String> findings = [];
  int screens = 0;

  /// Latin tokens that legitimately appear in Arabic UI.
  static const brandTokens = {
    'Niswah',
    'PLUS',
    'Google',
    'PDF',
    'JSON',
    'AR',
    'EN',
    'SHA',
    'ENV',
    'BACKEND',
    'ci',
    'acceptance',
    'local',
    'test',
    'PM',
    'AM',
    'Wi',
    'Fi',
    // Deliberate Latin acronym in the Arabic label "وضع التخطيط للحمل (TTC)"
    // (recorded as a cosmetic note, not a defect) and vendor names that are
    // proper nouns in the (Arabic) privacy policy.
    'TTC', 'Supabase', 'Gemini', 'Sentry',
  };

  static final _latin = RegExp(r'[A-Za-z]{3,}');
  static final _arabic = RegExp(r'[؀-ۿﭐ-﻿]');
  static final _englishMonth = RegExp(
    r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\b',
  );
  static final _slashDate = RegExp(r'\b\d{1,2}/\d{1,2}/\d{4}\b');

  static const _directionalIcons = <IconData>[
    Icons.chevron_right,
    Icons.chevron_left,
    Icons.chevron_right_rounded,
    Icons.chevron_left_rounded,
    Icons.arrow_back,
    Icons.arrow_forward,
    Icons.arrow_back_ios,
    Icons.arrow_forward_ios,
    Icons.arrow_back_ios_new,
    Icons.arrow_back_rounded,
    Icons.arrow_forward_rounded,
    Icons.keyboard_arrow_right,
    Icons.keyboard_arrow_left,
    Icons.navigate_next,
    Icons.navigate_before,
  ];

  List<String> visibleTexts() {
    final out = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      final s = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  Future<void> audit(
    String screen, {
    Set<String> userContent = const {},
    Set<String> extraAllowed = const {},
  }) async {
    screens++;
    final texts = visibleTexts();

    // -- English remnants + date presentation --
    for (final raw in texts) {
      if (raw.startsWith('SHA:')) continue; // the diagnostics banner
      if (userContent.any(raw.contains)) continue;
      final words = _latin.allMatches(raw).map((m) => m.group(0)!);
      final bad = words
          .where((w) => !brandTokens.contains(w) && !extraAllowed.contains(w))
          .toList();
      if (bad.isNotEmpty && !_arabic.hasMatch(raw)) {
        findings.add('$screen: English-only text "$raw"');
      } else if (bad.isNotEmpty) {
        findings.add('$screen: mixed text with English word(s) $bad in "$raw"');
      }
      if (_englishMonth.hasMatch(raw)) {
        findings.add('$screen: English month name in "$raw"');
      }
      if (_slashDate.hasMatch(raw)) {
        findings.add('$screen: dd/mm/yyyy date in "$raw"');
      }
    }

    // -- direction --
    final scaffold = find.byType(Scaffold);
    if (scaffold.evaluate().isNotEmpty) {
      final dir = Directionality.of(tester.element(scaffold.last));
      if (dir != TextDirection.rtl) findings.add('$screen: not RTL ($dir)');
    }

    // -- directional icons mirror --
    for (final e in find.byType(Icon).evaluate()) {
      final icon = (e.widget as Icon).icon;
      if (icon != null &&
          _directionalIcons.any((d) => d.codePoint == icon.codePoint) &&
          !icon.matchTextDirection &&
          !((e.widget as Icon).textDirection != null)) {
        findings.add(
          '$screen: directional icon U+${icon.codePoint.toRadixString(16)} does not mirror',
        );
      }
    }
    final back = find.byType(BackButton);
    if (back.evaluate().isNotEmpty) {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final dx = tester.getCenter(back.first).dx;
      if (dx < size.width / 2)
        findings.add('$screen: back button on the LEFT in RTL (dx=$dx)');
    }

    // -- overflow / clipping at normal and large text scale --
    var ex = tester.takeException();
    if (ex != null)
      findings.add('$screen: exception ${ex.toString().split('\n').first}');
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await tester.pump(const Duration(milliseconds: 600));
    ex = tester.takeException();
    if (ex != null) {
      findings.add(
        '$screen: overflow at 1.6x text scale: ${ex.toString().split('\n').first}',
      );
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pump(const Duration(milliseconds: 400));
    h.note(
      'ARABIC AUDIT [$screen] texts=${texts.length} findingsSoFar=${findings.length}',
    );
  }

  String get summary =>
      'screens=$screens findings=${findings.length} ${findings.take(12).toList()}';
}

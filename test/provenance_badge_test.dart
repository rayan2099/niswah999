import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/evidence_provenance.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/provenance_badge.dart';

/// F7 — [ProvenanceBadge] is the one shared widget every provenance-
/// aware surface renders from. Its own contract: never color alone
/// (every value has an icon + short text label), and the long-form
/// sentence must reach a screen reader via [Semantics.label] even
/// though the visible chip only shows the short label — verified here
/// independently of any one consuming screen.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
  });

  Future<void> pumpBadge(
    WidgetTester tester,
    EvidenceProvenance provenance,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ProvenanceBadge(provenance: provenance)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final provenance in EvidenceProvenance.values) {
    testWidgets(
      '${provenance.name}: shows an icon and a short text label (never '
      'color alone)',
      (tester) async {
        await pumpBadge(tester, provenance);

        expect(find.byIcon(provenance.icon), findsOneWidget);
        expect(find.text(provenance.shortLabel(false)), findsOneWidget);
      },
    );

    testWidgets('${provenance.name}: the long-form sentence reaches a screen '
        'reader via Semantics, not just the short chip text', (tester) async {
      await pumpBadge(tester, provenance);

      final semantics = tester.getSemantics(find.byType(ProvenanceBadge));
      expect(semantics.label, provenance.longLabel(false));
    });
  }

  testWidgets('predicted is never rendered as tentative-false — it must never '
      'share confirmed bleeding\'s own confident style', (tester) async {
    expect(EvidenceProvenance.predicted.isTentative, isTrue);
    expect(EvidenceProvenance.userObserved.isTentative, isFalse);
  });

  testWidgets(
    'legacyUnverified is never silently upgraded to userObserved in its '
    'own long-form label',
    (tester) async {
      await pumpBadge(tester, EvidenceProvenance.legacyUnverified);
      final semantics = tester.getSemantics(find.byType(ProvenanceBadge));
      expect(
        semantics.label,
        isNot(equals(EvidenceProvenance.userObserved.longLabel(false))),
      );
      expect(
        semantics.label.toLowerCase(),
        contains('not'),
        reason: 'the legacy-unverified label must honestly disclose the gap',
      );
    },
  );

  testWidgets('Arabic: renders the Arabic short and long labels', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(true);
    await pumpBadge(tester, EvidenceProvenance.userObserved);

    expect(
      find.text(EvidenceProvenance.userObserved.shortLabel(true)),
      findsOneWidget,
    );
    final semantics = tester.getSemantics(find.byType(ProvenanceBadge));
    expect(semantics.label, EvidenceProvenance.userObserved.longLabel(true));
    AppLocaleController.instance.setArabic(false);
  });

  testWidgets('survives 200% text scale without overflowing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: ProvenanceBadge(provenance: EvidenceProvenance.predicted),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/period_prediction.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/prediction_history_review.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_prediction_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/widgets/period_prediction_details.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppLocaleController.instance.setArabic(true));

  Future<void> show(
    WidgetTester tester,
    PeriodPrediction prediction,
    bool arabic, {
    Future<void> Function(PredictionHistoryReview)? onSaveReview,
  }) async {
    AppLocaleController.instance.setArabic(arabic);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PeriodPredictionDetails(
                prediction: prediction,
                onSaveReview: onSaveReview,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final arabic in [false, true]) {
    testWidgets(
      'range is disclosed as past variation at phone width: Arabic=$arabic',
      (tester) async {
        final prediction = const CyclePredictionService().predict(
          lastStart: DateTime(2026, 10, 1),
          cycleLengths: [27, 31, 29],
          now: DateTime(2026, 10, 2),
        );
        await show(tester, prediction, arabic);
        expect(
          find.byKey(const Key('period-historical-range')),
          findsOneWidget,
        );
        expect(
          find.textContaining(arabic ? 'ولا يضمن' : 'does not guarantee'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'overdue does not display the previous range as a fresh forecast',
    (tester) async {
      final prediction = const CyclePredictionService().predict(
        lastStart: DateTime(2026, 10, 1),
        cycleLengths: [27, 31, 29],
        now: DateTime(2026, 12, 1),
      );
      await show(tester, prediction, false);
      expect(find.byKey(const Key('period-historical-range')), findsNothing);
      expect(
        find.textContaining('no new period has been assumed'),
        findsOneWidget,
      );
    },
  );

  for (final arabic in [false, true]) {
    testWidgets(
      'gap review saves an unsure answer without creating a bleeding record: Arabic=$arabic',
      (tester) async {
        final prediction = const CyclePredictionService().predict(
          lastStart: DateTime(2026, 10, 1),
          cycleLengths: [28, 200, 29, 28],
          now: DateTime(2026, 10, 1),
        );
        PredictionHistoryReview? saved;
        await show(
          tester,
          prediction,
          arabic,
          onSaveReview: (review) async {
            saved = review;
          },
        );
        expect(find.byKey(const Key('period-historical-range')), findsNothing);
        await tester.tap(find.byKey(const Key('review-prediction-history')));
        await tester.pumpAndSettle();
        final answer = find.text(arabic ? 'لست متأكدة' : 'I am unsure');
        await tester.ensureVisible(answer);
        await tester.tap(answer);
        await tester.pumpAndSettle();
        expect(saved?.key, prediction.reviewGaps.single.key);
        expect(saved?.resolution, PredictionGapResolution.unsure);
        expect(prediction.expectedStart, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('save failure keeps review open and offers retry', (
    tester,
  ) async {
    final prediction = const CyclePredictionService().predict(
      lastStart: DateTime(2026, 10, 1),
      cycleLengths: [28, 200, 29, 28],
      now: DateTime(2026, 10, 1),
    );
    await show(
      tester,
      prediction,
      false,
      onSaveReview: (_) async {
        throw StateError('write unavailable');
      },
    );
    await tester.tap(find.byKey(const Key('review-prediction-history')));
    await tester.pumpAndSettle();
    final answer = find.text('I am unsure');
    await tester.ensureVisible(answer);
    await tester.tap(answer);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not verify the saved answer'),
      findsOneWidget,
    );
    expect(find.text('Review recorded gaps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

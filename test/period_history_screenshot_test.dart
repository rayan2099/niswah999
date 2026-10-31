import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/cycle_log.dart';
import 'package:niswah/features/cycle_tracking/domain/repositories/cycle_tracking_repository.dart';
import 'package:niswah/features/cycle_tracking/domain/services/cycle_calculation_service.dart';
import 'package:niswah/features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'package:niswah/features/insights/domain/period_history.dart';
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';
import 'package:niswah/features/insights/presentation/widgets/period_history_view.dart';

import 'support/parity_test_harness.dart';

/// Reproduces TestFlight Feedback 2, page 5: a completed period 27 -> 30
/// October 2026 (30 October is the first clean day, the canonical end) and
/// the closing "stopped" observation on 30 October, projected into
/// cycle_entries as flow none with the default cycle_day 1.
/// Synthetic data. SCREENSHOT_DIR writes a PNG of the Insights screen.
class _Repo implements CycleTrackingRepository {
  _Repo(this.logs);
  final List<CycleLog> logs;
  @override
  Future<List<CycleLog>> getCycleLogs({
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async => logs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CycleTrackingViewModel pageFiveViewModel() => CycleTrackingViewModel(
  repository: _Repo([
    CycleLog(
      id: 'closing-observation',
      userId: 'local-user',
      date: DateTime(2026, 10, 30),
      flow: FlowLevel.none,
      cycleDay: 1,
    ),
  ]),
  canonicalEpisodeLoader: (_) async => [
    CanonicalEpisodeTiming(
      startDate: DateTime(2026, 10, 27),
      endDate: DateTime(2026, 10, 30),
    ),
  ],
);

void main() {
  testWidgets('page 5 history renders (screenshot)', (tester) async {
    final vm = pageFiveViewModel();
    await ParityTestHarness.pump(
      tester,
      arabic: true,
      size: const Size(390, 4200),
      homeOverride: RepaintBoundary(
        key: const Key('shot'),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: InsightsScreen(viewModel: vm)),
        ),
      ),
    );
    AppClock.now = () => DateTime(2026, 10, 31, 12);
    await vm.loadLogs();
    await tester.pumpAndSettle();
    final dir = Platform.environment['SCREENSHOT_DIR'];
    if (dir == null || dir.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/insights_page5.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('history timeline with several periods renders (screenshot)', (
    tester,
  ) async {
    CycleLog log(String id, DateTime d, FlowLevel f) =>
        CycleLog(id: id, userId: 'local-user', date: d, flow: f, cycleDay: 1);
    final items = buildPeriodHistory(
      periods: [
        HistoryPeriodInput(
          startDate: DateTime(2026, 10, 27),
          firstCleanDay: DateTime(2026, 10, 30),
        ),
        HistoryPeriodInput(
          startDate: DateTime(2026, 9, 28),
          firstCleanDay: DateTime(2026, 10, 4),
        ),
        HistoryPeriodInput(
          startDate: DateTime(2026, 8, 30),
          firstCleanDay: DateTime(2026, 9, 5),
        ),
      ],
      logs: [
        log('closing', DateTime(2026, 10, 30), FlowLevel.none),
        log('lone', DateTime(2026, 10, 12), FlowLevel.spotting),
        log('s1', DateTime(2026, 9, 28), FlowLevel.heavy),
        log('s2', DateTime(2026, 9, 30), FlowLevel.medium),
        log('s3', DateTime(2026, 10, 4), FlowLevel.none),
      ],
      today: DateTime(2026, 10, 31, 12),
    );
    await ParityTestHarness.pump(
      tester,
      arabic: true,
      size: const Size(390, 470),
      homeOverride: RepaintBoundary(
        key: const Key('timeline'),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: const Color(0xFFFBF8F7),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: PeriodHistoryBody(
                    items: items,
                    isLoading: false,
                    error: null,
                    incomplete: false,
                    onRetry: () {},
                    onOpen: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final dir = Platform.environment['SCREENSHOT_DIR'];
    if (dir == null || dir.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('timeline')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/history_timeline.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}

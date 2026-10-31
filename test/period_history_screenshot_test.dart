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
import 'package:niswah/features/insights/presentation/screens/insights_screen.dart';

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
}

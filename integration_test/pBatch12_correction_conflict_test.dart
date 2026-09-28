import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import 'package:niswah/features/cycle_tracking/domain/entities/bleeding_episode.dart';
import 'package:niswah/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/flows.dart';
import 'support/harness.dart';

/// Phase 3 batch 12 — MENS-07 (correction conflict resolution) and MENS-08
/// (revision markers), against the DISPOSABLE database with TWO
/// authenticated concurrent writers (two independent sessions of the same
/// account — "two devices").
///  1. MENS-08: correct today's entry through the real UI; the chain is
///     original -> correction (supersedes link), effective tip = correction,
///     the day sheet marks exactly one revision "Current" and one
///     "Superseded", and the legacy projection shows the corrected flow.
///  2. MENS-07 race: for several observations, both writers try to correct
///     the SAME observation at the same moment (Future.wait). Exactly one
///     must win and the other must get the conflict — never two winners,
///     never a forked chain.
///  3. MENS-07 UI: the app's own correction sheet, opened on stale data,
///     while the other writer corrects first -> the conflict panel shows the
///     saved value; "Use my change" rebases onto the new tip (chain of 3, no
///     fork).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Batch 12: correction conflicts with two concurrent writers', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    if (!await h.guardBackend('Batch12')) return;
    final f = Flows(h);

    final email = await f.newAccountOnDashboard('CC');
    h.note('LOOKUP_EMAIL=$email');
    await f.startBleedingToday('CC', flow: 'Light');
    final clientA = NiswahSupabase.clientOrNull!;
    final uid = clientA.auth.currentUser!.id;

    // The second writer: an independent session of the same account.
    final clientB = SupabaseClient(
      dotenv.env['SUPABASE_URL']!,
      dotenv.env['SUPABASE_ANON_KEY']!,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await clientB.auth.signInWithPassword(
      email: email,
      password: 'Test-Pass-12345',
    );
    final repoA = BleedingEpisodeRepositoryImpl(client: clientA);
    final repoB = BleedingEpisodeRepositoryImpl(client: clientB);
    final offset = DateTime.now().timeZoneOffset.inMinutes;

    Future<List<Map<String, dynamic>>> observations() async =>
        List<Map<String, dynamic>>.from(
          await clientA
              .from('bleeding_observations')
              .select()
              .eq('user_id', uid)
              .order('created_at', ascending: true),
        );

    Future<String?> flowOfEffective(String rootId) async {
      final tip = await repoA.effectiveObservationId(rootId);
      final rows = await observations();
      return rows.where((r) => r['id'] == tip).firstOrNull?['flow'] as String?;
    }

    // ================= 1. MENS-08 through the real UI =================
    final before = await observations();
    final originalId = '${before.single['id']}';
    final episodeId = '${before.single['episode_id']}';
    final originalFlow = before.single['flow'];

    await h.scrollToTop();
    await h.tapVisible(find.bySemanticsLabel('Cycle calendar'));
    await h.settle(3);
    await h.tapVisible(find.text(DateTime.now().day.toString()), last: true);
    await h.settle(2);
    await h.tapVisible(find.text('Correct this entry'));
    await h.settle(2);
    await h.tapVisible(find.text('Heavy'));
    await h.tapVisible(find.text('Save correction'));
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);

    final afterUi = await observations();
    final correction = afterUi.where((r) => r['supersedes_id'] == originalId);
    final chainOk =
        originalFlow == 'light' &&
        afterUi.length == 2 &&
        correction.length == 1 &&
        correction.single['flow'] == 'heavy' &&
        await repoA.effectiveObservationId(originalId) ==
            correction.single['id'];
    final legacy = List<Map<String, dynamic>>.from(
      await clientA.from('cycle_entries').select().eq('user_id', uid),
    );
    final projectionOk = legacy.length == 1 && legacy.single['flow'] == 'heavy';

    // Day sheet markers: reopen the day.
    await h.tapVisible(find.text(DateTime.now().day.toString()), last: true);
    await h.settle(2);
    h.dumpTexts('CC day detail after correction');
    final day = h.notes.last;
    final markersOk =
        RegExp('Current').allMatches(day).length >= 1 &&
        day.contains('Superseded');
    h.note(
      'CC MENS-08 chain=$chainOk projection=$projectionOk markers=$markersOk',
    );

    // ================= 2. MENS-07 through the app's own sheet =================
    // The sheet targets today's effective observation (the UI correction from part 1).
    final openedSheet = await h.tapVisible(find.text('Correct this entry'));
    await h.settle(2);
    h.dumpTexts('CC correction sheet (stale view)');
    final pickedLight = await h.tapVisible(find.text('Light'), last: true);
    h.note('CC sheet opened=$openedSheet pickedLight=$pickedLight');
    // Meanwhile the OTHER writer corrects the same target first.
    final beforeStale = await observations();
    final staleTarget =
        '${beforeStale.firstWhere((r) => r['supersedes_id'] == originalId)['id']}';
    final otherWon = await repoB.correctObservation(
      clientOperationId: const Uuid().v4(),
      supersedesId: staleTarget,
      observedDate: DateTime.now(),
      precision: ObservationPrecision.dateOnly,
      flow: ObservationFlow.spotting,
      utcOffsetMinutes: offset,
    );
    final savedStale = await h.tapVisible(find.text('Save correction'));
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    h.note('CC stale save tapped=$savedStale');
    h.dumpTexts('CC conflict panel');
    final panel = h.notes.last;
    final conflictShown =
        otherWon != null &&
        panel.contains('This entry changed elsewhere') &&
        panel.contains('Current saved value: Spotting');
    final rebased = await h.tapVisible(find.text('Use my change'));
    await tester.pump(const Duration(seconds: 5));
    await h.settle(2);
    final rows3 = await observations();
    final chain3 = <String>[];
    String? cursor = originalId;
    while (cursor != null) {
      chain3.add(cursor);
      final next = rows3.where((r) => r['supersedes_id'] == cursor);
      cursor = next.length == 1 ? '${next.single['id']}' : null;
      if (next.length > 1) chain3.add('FORK');
    }
    final finalFlow = await flowOfEffective(originalId);
    final uiConflictOk =
        conflictShown &&
        rebased &&
        !chain3.contains('FORK') &&
        chain3.length ==
            4 && // original -> UI correction -> other writer -> rebased (the app's own)
        finalFlow == 'light';
    h.note(
      'CC MENS-07 ui conflictShown=$conflictShown rebased=$rebased '
      'chain=${chain3.length} finalFlow=$finalFlow',
    );

    // ================= 3. MENS-07 race: two writers, same observation =================
    final targets = <String>[];
    for (final flow in [
      ObservationFlow.spotting,
      ObservationFlow.medium,
      ObservationFlow.light,
      ObservationFlow.heavy,
      ObservationFlow.medium,
    ]) {
      final id = await repoA.recordObservation(
        clientOperationId: const Uuid().v4(),
        episodeId: episodeId,
        observedDate: DateTime.now(),
        precision: ObservationPrecision.dateOnly,
        flow: flow,
        utcOffsetMinutes: offset,
      );
      if (id != null) targets.add(id);
    }
    var races = 0;
    var oneWinnerOneConflict = 0;
    var forks = 0;
    for (final target in targets) {
      Future<String> attempt(
        BleedingEpisodeRepositoryImpl repo,
        ObservationFlow flow,
      ) async {
        try {
          final id = await repo.correctObservation(
            clientOperationId: const Uuid().v4(),
            supersedesId: target,
            observedDate: DateTime.now(),
            precision: ObservationPrecision.dateOnly,
            flow: flow,
            utcOffsetMinutes: offset,
          );
          return id == null ? 'error' : 'won';
        } on CorrectionConflictException {
          return 'conflict';
        }
      }

      final results = await Future.wait([
        attempt(repoA, ObservationFlow.heavy),
        attempt(repoB, ObservationFlow.light),
      ]);
      races++;
      if (results.contains('won') && results.contains('conflict')) {
        oneWinnerOneConflict++;
      }
      final rows = await observations();
      final children = rows.where((r) => r['supersedes_id'] == target).length;
      if (children != 1) forks++;
      h.note('CC race $races results=$results children=$children');
    }
    final raceOk = races == 5 && oneWinnerOneConflict == 5 && forks == 0;
    h.note(
      'CC MENS-07 race ok=$raceOk (races=$races clean=$oneWinnerOneConflict forks=$forks)',
    );

    clientB.dispose();
    final crashed = tester.takeException() != null;
    final pass =
        !crashed &&
        chainOk &&
        projectionOk &&
        markersOk &&
        raceOk &&
        uiConflictOk;
    h.reportResult(
      PersonaResult(
        testId: 'Batch12',
        expectedOutcome:
            'MENS-08: correction chain + Current/Superseded markers + legacy '
            'projection; MENS-07: with two concurrent writers exactly one wins '
            'each race (no fork), and the app shows the conflict and rebases '
            'onto the new tip',
        actualOutcome:
            'crashed=$crashed chain=$chainOk projection=$projectionOk '
            'markers=$markersOk race=$raceOk uiConflict=$uiConflictOk',
        status: pass ? PersonaStatus.pass : PersonaStatus.fail,
        screenshotRef: 'CC_day_detail.png',
      ),
    );
  });
}

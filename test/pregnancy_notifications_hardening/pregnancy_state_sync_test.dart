// Pregnancy/notifications hardening (2026-10-21) — regression tests for
// findings 3 (turning pregnancy/nifas off reaches the synced profile, and
// every state change re-plans reminders), 8 (birth date passed to both
// stores, no future date) and the shared nifas definition.
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';
import 'package:niswah/core/utils/app_clock.dart';
import 'package:niswah/features/pregnancy_profile/data/pregnancy_state_sync.dart';
import 'package:niswah/features/pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import 'package:niswah/features/pregnancy_profile/domain/entities/pregnancy_profile.dart';
import 'package:niswah/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo extends PregnancyProfileRepository {
  _FakeRepo({this.row, this.fail = false}) : super(supabaseClient: null);

  PregnancyProfile? row;
  final bool fail;
  final calls = <String>[];
  DateTime? postpartumStart;

  @override
  Future<PregnancyProfile?> getForUser(String userId) async => row;

  @override
  Future<PregnancyProfile> upsert(PregnancyProfile profile) async {
    if (fail) throw StateError('offline');
    calls.add('upsert');
    row = profile;
    return profile;
  }

  @override
  Future<void> markPostpartumStarted(
    String userId, {
    DateTime? startDate,
  }) async {
    if (fail) throw StateError('offline');
    calls.add('markPostpartumStarted');
    postpartumStart = startDate;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 10, 21, 14);
  late List<String?> refreshes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppClock.now = () => today;
    refreshes = [];
    await PregnancyStatusController.instance.load();
  });
  tearDown(() => AppClock.now = DateTime.now);

  PregnancyStateSync sync(_FakeRepo repo, {String? userId = 'user-1'}) =>
      PregnancyStateSync(
        repository: repo,
        currentUserId: () => userId,
        refreshNotifications: (u) async => refreshes.add(u),
      );

  test(
    'turning pregnancy off clears the synced row and re-plans reminders',
    () async {
      final repo = _FakeRepo(
        row: PregnancyProfile(
          id: 'row',
          userId: 'user-1',
          trackingBasis: TrackingBasis.manualWeek,
          manualWeekValue: 10,
          manualWeekSetAt: DateTime(2026, 10, 1),
          highRiskFlags: const ['gestational diabetes'],
          locale: 'en',
        ),
      );
      await PregnancyStatusController.instance.activate(startWeek: 10);

      expect(await sync(repo).deactivate(), isTrue);

      expect(PregnancyStatusController.instance.isPregnant, isFalse);
      expect(repo.calls, ['upsert']);
      expect(
        PregnancyStatusEngine.getStatus(repo.row, today).mode,
        PregnancyMode.unknown,
      );
      expect(repo.row!.highRiskFlags, ['gestational diabetes']);
      expect(repo.row!.locale, 'en');
      expect(refreshes, ['user-1']);
    },
  );

  test('turning nifas off clears is_postpartum on the synced row', () async {
    final repo = _FakeRepo(
      row: PregnancyProfile(
        id: 'row',
        userId: 'user-1',
        isPostpartum: true,
        postpartumStartDate: DateTime(2026, 10, 10),
      ),
    );
    await sync(repo).deactivate();
    expect(repo.row!.isPostpartum, isFalse);
    expect(repo.row!.postpartumStartDate, isNull);
    expect(refreshes, hasLength(1));
  });

  test('a failed server write is reported (false); device state and the '
      'refresh still happen', () async {
    await PregnancyStatusController.instance.activate(startWeek: 10);
    final repo = _FakeRepo(
      row: PregnancyProfile(id: 'row', userId: 'user-1'),
      fail: true,
    );
    expect(await sync(repo).deactivate(), isFalse);
    expect(PregnancyStatusController.instance.isPregnant, isFalse);
    expect(refreshes, hasLength(1));
  });

  test(
    'log birth with a picked past date: both stores get that date',
    () async {
      final repo = _FakeRepo();
      final birth = DateTime(2026, 10, 17);
      expect(await sync(repo).startNifas(birthDate: birth), isTrue);

      expect(repo.postpartumStart, birth);
      final c = PregnancyStatusController.instance;
      expect(c.nifasStartedAt, birth);
      // Dashboard day = engine elapsed calendar days (4) shown 1-based.
      expect(c.nifasDay, 5);
      expect(c.isNifasActive, isTrue);
      expect(refreshes, ['user-1']);
    },
  );

  test('a future birth date is rejected before anything changes', () async {
    final repo = _FakeRepo();
    await expectLater(
      sync(repo).startNifas(birthDate: DateTime(2026, 10, 22)),
      throwsArgumentError,
    );
    expect(PregnancyStatusController.instance.nifasStartedAt, isNull);
    expect(repo.calls, isEmpty);
    expect(refreshes, isEmpty);
  });

  test('signed out: device only, still re-plans', () async {
    final repo = _FakeRepo();
    expect(await sync(repo, userId: null).startNifas(), isTrue);
    expect(repo.calls, isEmpty);
    expect(refreshes, [null]);
  });

  test(
    'dashboard and engine share one nifas definition on every day',
    () async {
      final birth = DateTime(2026, 8, 1);
      await PregnancyStatusController.instance.startNifas(birthDate: birth);
      final profile = PregnancyProfile(
        id: '',
        userId: '',
        isPostpartum: true,
        postpartumStartDate: birth,
      );
      for (var d = 0; d <= 45; d++) {
        final now = DateTime(2026, 8, 1 + d, 23, 30);
        AppClock.now = () => now;
        final engine = PregnancyStatusEngine.getStatus(profile, now);
        expect(
          PregnancyStatusController.instance.isNifasActive,
          engine.phase == PregnancyStatusEngine.nifasPhase,
          reason: 'day $d',
        );
        expect(
          PregnancyStatusController.instance.nifasDay,
          engine.daysPostpartum! + 1,
          reason: 'day $d',
        );
      }
    },
  );

  test('markTrackingEnded with no row writes nothing', () async {
    final repo = _FakeRepo();
    await repo.markTrackingEnded('user-1');
    expect(repo.calls, isEmpty);
  });
}

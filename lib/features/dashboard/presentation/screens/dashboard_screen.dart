import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/preferences/pregnancy_status_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/widgets/rating_scale_row.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import '../../../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/cycle_segment_planner.dart';
import '../../../cycle_tracking/domain/services/cycle_status_engine.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import '../../../cycle_tracking/presentation/widgets/cycle_log_form_sheet.dart';
import '../../../cycle_tracking/presentation/widgets/daily_checkin_sheet.dart';
import '../../../cycle_tracking/presentation/widgets/start_bleeding_sheet.dart';
import '../../../dream_interpreter/presentation/screens/dream_interpreter_screen.dart';
import '../../../notifications/presentation/screens/notification_feed_screen.dart';
import '../../../prayer_tracking/domain/entities/prayer_entry.dart' as prayer;
import '../../../prayer_tracking/presentation/viewmodels/prayer_tracking_view_model.dart';
import '../../../wellbeing/data/repositories/wellbeing_repository.dart';

String _l(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

String _stateLabel(_FiqhState state) => switch (state) {
  _FiqhState.tahara => _l('Tahara', 'طهارة'),
  _FiqhState.haid => _l('Haid', 'حيض'),
  _FiqhState.istihadah => _l('Istihadah', 'استحاضة'),
  _FiqhState.needsAdvisory => _l('Needs review', 'تحتاج مراجعة'),
  // Fiqh Remediation Wave 1 (Section E): bleeding, but no Madhhab
  // SELECTED — never labeled as if a ruling were known.
  _FiqhState.madhhabUnresolved => _l(
    'Select your Madhhab',
    'يلزم اختيار المذهب',
  ),
};

/// Arabic masculine ordinals ("اليوم الأول", "اليوم الثاني", …) for "يوم"
/// (day) — covers 1..31, a comfortable margin over any real phase length
/// (the longest fixed segment is 8-ish days; even an unusually long fertile
/// or tahara span in a real cycle stays well under a month). Beyond that,
/// falls back to a cardinal phrasing rather than guessing at a compound
/// ordinal form.
const _arabicOrdinalDays = [
  'اليوم الأول',
  'اليوم الثاني',
  'اليوم الثالث',
  'اليوم الرابع',
  'اليوم الخامس',
  'اليوم السادس',
  'اليوم السابع',
  'اليوم الثامن',
  'اليوم التاسع',
  'اليوم العاشر',
  'اليوم الحادي عشر',
  'اليوم الثاني عشر',
  'اليوم الثالث عشر',
  'اليوم الرابع عشر',
  'اليوم الخامس عشر',
  'اليوم السادس عشر',
  'اليوم السابع عشر',
  'اليوم الثامن عشر',
  'اليوم التاسع عشر',
  'اليوم العشرون',
  'اليوم الحادي والعشرون',
  'اليوم الثاني والعشرون',
  'اليوم الثالث والعشرون',
  'اليوم الرابع والعشرون',
  'اليوم الخامس والعشرون',
  'اليوم السادس والعشرون',
  'اليوم السابع والعشرون',
  'اليوم الثامن والعشرون',
  'اليوم التاسع والعشرون',
  'اليوم الثلاثون',
  'اليوم الحادي والثلاثون',
];

/// "Day 2 of Tahara" / "اليوم الثاني من الطهارة" — the ring center's
/// headline. [day] is the real elapsed day *within the current phase*
/// (never the overall statistical cycle day), so it stays meaningful even
/// when the account's average cycle length is short or unusual — see
/// [_dayInActiveSegment]. Falls back to the bare phase name when there's no
/// real day-within-phase to report, rather than fabricating one.
String _phaseDayHeadline(int? day, String phaseLabel) {
  if (day == null) return phaseLabel;
  if (AppLocaleController.instance.isArabic) {
    final ordinal = day >= 1 && day <= _arabicOrdinalDays.length
        ? _arabicOrdinalDays[day - 1]
        : 'اليوم $day';
    // "اليوم الأول من الطهارة", not "...من طهارة" — "من" + an indefinite
    // noun here reads as "a day of purity" (any old one), not "day one of
    // *the* purity [phase she's in]"; the definite article is what ties it
    // back to a specific, current state. Spelling-only prefix — the ال is
    // always written this way regardless of the following letter's sun/moon
    // pronunciation rule.
    return '$ordinal من ال$phaseLabel';
  }
  return 'Day $day of $phaseLabel';
}

/// The "of N" denominator for the currently active segment — the real
/// average completed-period length for Haid (never fabricated when
/// unknown), or the segment's own scheduled duration for every other
/// phase. Shared by the ring's center headline and the stepper's active
/// node so the two numbers never disagree.
int? _activeSegmentDenominator(
  CycleSegmentPlan segmentPlan,
  int? averagePeriodLength,
) {
  final active = segmentPlan.active;
  if (active == null) return null;
  return active.id == CycleSegmentId.haid
      ? averagePeriodLength
      : active.durationDays;
}

/// The ring center's headline and optional subtext.
///
/// Bypasses [_phaseDayHeadline]'s "day X of `<phase>`" template for
/// needsAdvisory: its label ("تحتاج مراجعة" / "Needs review") is a verb
/// phrase, not a phase noun, so composing it the same way as
/// tahara/haid/istihadah produces broken grammar ("day one OF needs-
/// review"). While a confirmation window is open, it gets its own
/// headline plus a coarse (hour-level, not live-ticking — the ring
/// isn't the place for a seconds counter) ETA instead; the precise
/// live countdown stays in the banner below, where it already lives.
(String, String?) _ringCenterText({
  required _FiqhState state,
  required int? dayInActiveSegment,
  required DateTime? confirmAt,
  required CycleSegmentPlan segmentPlan,
  required int? averagePeriodLength,
}) {
  if (state == _FiqhState.needsAdvisory) {
    if (confirmAt != null) {
      final remaining = confirmAt.difference(AppClock.now());
      final eta = remaining.isNegative
          ? null
          : remaining.inHours < 1
          ? _l('Confirming soon', 'التأكيد قريباً')
          : _l(
              'Confirms in ${remaining.inHours}h',
              'تأكيد خلال ${remaining.inHours}س',
            );
      return (_l('Awaiting confirmation', 'بانتظار التأكيد'), eta);
    }
    return (_stateLabel(state), null);
  }

  final headline = _phaseDayHeadline(dayInActiveSegment, _stateLabel(state));
  final denominator = _activeSegmentDenominator(
    segmentPlan,
    averagePeriodLength,
  );
  final subtitle =
      dayInActiveSegment == null || denominator == null || denominator <= 0
      ? null
      : '$dayInActiveSegment ${_l('of', 'من')} $denominator ${_l('days', 'أيام')}';
  return (headline, subtitle);
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onProfileTap, this.viewModel});

  final VoidCallback? onProfileTap;

  /// Shared across tabs by [NiswahHomeShell] so a log saved on one tab is
  /// immediately reflected on the others — the tabs live in an
  /// [IndexedStack] and never remount, so a screen-owned instance would
  /// otherwise go stale the moment another tab saves a log. Falls back to
  /// a private instance when unset (e.g. existing tests that mount this
  /// screen standalone).
  final CycleTrackingViewModel? viewModel;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final CycleTrackingViewModel _viewModel;
  late final PrayerTrackingViewModel _prayerViewModel;
  bool _istihadahMode = false;
  _WellbeingCheckInResult? _wellbeing;

  // The fiqh state ring reads elapsed bleeding duration off the wall clock
  // (see _currentFiqhStateDetail), so it needs to be re-evaluated on a
  // timer, not just when the logs themselves change — a needsAdvisory
  // state can flip to haid purely from time passing. One-minute ticks
  // match the display's hour-level precision.
  Timer? _fiqhRefreshTimer;

  @override
  void initState() {
    super.initState();
    PregnancyStatusController.instance.load();
    _viewModel = widget.viewModel ?? CycleTrackingViewModel();
    _prayerViewModel = PrayerTrackingViewModel();
    _viewModel.loadLogs().then((_) {
      if (mounted) {
        _prayerViewModel.loadToday(userId: _viewModel.currentUserId);
      }
    });
    _loadWellbeingCheckIn();
    _fiqhRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _fiqhRefreshTimer?.cancel();
    super.dispose();
  }

  CycleLog? _todayLog() => _viewModel.logs
      .where((log) => DateUtils.isSameDay(log.date, AppClock.now()))
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _viewModel,
        _prayerViewModel,
        MadhhabController.instance,
        PregnancyStatusController.instance,
      ]),
      builder: (context, _) {
        final summary = _viewModel.summary;
        final calculation = _viewModel.cycleCalculation;
        final cycleDay = calculation.currentCycleDay;
        // The engine always runs (regardless of _istihadahMode) so every
        // state — including manual istihadah — shares the same real,
        // flow-aware day-count data; the toggle only overrides which
        // label is displayed below, never the underlying computation.
        final snapshot = calculation.hasSufficientHistory
            ? const CycleStatusEngine().evaluate(
                logs: _viewModel.logs,
                calculation: calculation,
                madhhab: MadhhabController.instance.selectedOrNull,
                now: AppClock.now(),
              )
            : const CycleStatusSnapshot(
                state: FiqhCycleState.tahara,
                confirmAt: null,
                daysIntoCurrentEpisode: null,
                cycleDayEstimate: null,
                averageCycleLength: null,
                averagePeriodLength: null,
              );
        final mappedState = switch (snapshot.state) {
          FiqhCycleState.haid => _FiqhState.haid,
          FiqhCycleState.needsAdvisory => _FiqhState.needsAdvisory,
          FiqhCycleState.tahara ||
          FiqhCycleState.insufficientHistory => _FiqhState.tahara,
          // Fiqh Remediation Wave 1 (Section E): never mapped to tahara —
          // that would silently claim purity for a currently-bleeding user
          // with no Madhhab SELECTED.
          FiqhCycleState.madhhabUnresolved => _FiqhState.madhhabUnresolved,
        };
        final state = _istihadahMode ? _FiqhState.istihadah : mappedState;
        final isCurrentlyBleeding =
            state == _FiqhState.haid ||
            state == _FiqhState.needsAdvisory ||
            state == _FiqhState.istihadah;

        return Directionality(
          textDirection: AppLocaleController.instance.isArabic
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: AppColors.tahara,
                onRefresh: _viewModel.loadLogs,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _DashboardHeader(
                        viewModel: _viewModel,
                        onNotificationsTap: () =>
                            _openFullScreen(const NotificationFeedScreen()),
                      ),
                    ),
                    if (_viewModel.isLoading || _prayerViewModel.isLoading)
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: 2,
                          child: ColoredBox(color: AppColors.tahara),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 132),
                      sliver: SliverList.list(
                        children: [
                          if (PregnancyStatusController
                              .instance
                              .isPregnant) ...[
                            _PregnancyOverview(
                              week: PregnancyStatusController
                                  .instance
                                  .currentWeek,
                              onOpenDoctor: () => _openFullScreen(
                                const DrNiswahChatScreen(
                                  mode: NiswahAssistantMode.health,
                                ),
                              ),
                              onLogBirth: () async {
                                await PregnancyStatusController.instance
                                    .startNifas();
                                final userId = NiswahSupabase
                                    .clientOrNull
                                    ?.auth
                                    .currentUser
                                    ?.id;
                                var syncedToAccount = true;
                                if (userId != null) {
                                  try {
                                    await PregnancyProfileRepository()
                                        .markPostpartumStarted(userId);
                                  } catch (error, stack) {
                                    syncedToAccount = false;
                                    AppErrorReporter.report(
                                      error,
                                      stack,
                                      context: 'DashboardScreen.onLogBirth',
                                      feature: 'pregnancy_profile',
                                    );
                                  }
                                }
                                if (!mounted) return;
                                // Local nifas tracking remains authoritative
                                // on a sync failure — the local toggle above
                                // already took effect — but the message must
                                // not claim the chat-context sync succeeded
                                // when it didn't (RR-003: no false success).
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      syncedToAccount
                                          ? _l(
                                              'Wishing you a safe delivery. Nifas tracking has started.',
                                              'نتمنى لكِ ولادة آمنة. تم بدء متابعة النفاس.',
                                            )
                                          : _l(
                                              "Wishing you a safe delivery. Nifas tracking has started on this device, but couldn't sync to your account — the chat may not be personalized yet.",
                                              'نتمنى لكِ ولادة آمنة. بدأ تتبع النفاس على هذا الجهاز، لكن تعذّرت المزامنة مع حسابك — قد لا تكون المحادثة مخصّصة بعد.',
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                          ] else if (!calculation.hasSufficientHistory ||
                              !calculation.hasPlausibleAverage) ...[
                            _InsufficientCycleDataCard(
                              onLog: () => _startBleeding(),
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            _CycleOverview(
                              summary: summary,
                              cycleDay: cycleDay!,
                              state: state,
                              isCurrentlyBleeding: isCurrentlyBleeding,
                              confirmAt: snapshot.confirmAt,
                              daysIntoCurrentEpisode:
                                  snapshot.daysIntoCurrentEpisode,
                              onTap: () => showCycleLogSheet(
                                context,
                                viewModel: _viewModel,
                                existingLog: _todayLog(),
                                initialFlow: FlowLevel.medium,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _QuickActions(
                              isCurrentlyBleeding: isCurrentlyBleeding,
                              onStart: () => _startBleeding(),
                              onEnd: () => _endBleeding(),
                              onCheckIn: () => _checkInToday(),
                              onBackfill: () => _backfillObservation(),
                            ),
                          ],
                          if (PregnancyStatusController
                              .instance
                              .isNifasActive) ...[
                            _NifasStatusCard(
                              day: PregnancyStatusController.instance.nifasDay,
                            ),
                            const SizedBox(height: 16),
                          ],
                          const SizedBox(height: 28),
                          _WellbeingCard(
                            onLog: _showWellbeingCheckIn,
                            checkIn: _wellbeing,
                          ),
                          const SizedBox(height: 16),
                          _DoctorNiswahCard(
                            onTap: () => _openFullScreen(
                              const DrNiswahChatScreen(
                                mode: NiswahAssistantMode.health,
                              ),
                            ),
                          ),
                          // The web app hides the Istihadah toggle while
                          // pregnant.
                          if (!PregnancyStatusController.instance.isPregnant &&
                              calculation.hasSufficientHistory) ...[
                            const SizedBox(height: 32),
                            _IstihadahToggle(
                              value: _istihadahMode,
                              onChanged: (value) => setState(() {
                                _istihadahMode = value;
                              }),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _FiqhStateBanner(
                                key: ValueKey(state),
                                state: state,
                                cycleDay: cycleDay!,
                                madhhab:
                                    MadhhabController
                                        .instance
                                        .selectedOrNull
                                        ?.name ??
                                    '',
                                onLogBlood: () => showCycleLogSheet(
                                  context,
                                  viewModel: _viewModel,
                                  existingLog: _todayLog(),
                                  initialFlow: FlowLevel.medium,
                                ),
                                onAskAdvisor: () => _openFullScreen(
                                  const DrNiswahChatScreen(
                                    mode: NiswahAssistantMode.fiqhAdvisory,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _PrayerStatusCard(
                            viewModel: _prayerViewModel,
                            fiqhState: state,
                          ),
                          const SizedBox(height: 16),
                          _DreamCard(
                            onTap: () =>
                                _openFullScreen(const DreamInterpreterScreen()),
                          ),
                          const SizedBox(height: 16),
                          _AiQuickAccessCard(
                            onTap: () =>
                                _openFullScreen(const DrNiswahChatScreen()),
                          ),
                          if (_viewModel.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _viewModel.errorMessage!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showWellbeingCheckIn() async {
    final result = await showModalBottomSheet<_WellbeingCheckInResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WellbeingCheckInSheet(),
    );
    if (result == null || !mounted) return;

    try {
      // The repository call is what actually gives the mental state report
      // a real history to work from — it must succeed before the quick
      // local-display prefs below are written, or a failed save could look
      // like a successful one the next time this screen loads.
      await WellbeingRepository().upsertToday(
        mood: result.mood,
        energy: result.energy,
        sleep: result.sleep,
        notes: result.notes,
      );
      final preferences = await SharedPreferences.getInstance();
      final today = AppClock.now();
      await preferences.setString(
        'dashboard_wellbeing_date',
        '${today.year}-${today.month}-${today.day}',
      );
      await preferences.setInt('dashboard_wellbeing_mood', result.mood);
      await preferences.setInt('dashboard_wellbeing_energy', result.energy);
      await preferences.setInt('dashboard_wellbeing_sleep', result.sleep);
      if (result.notes == null) {
        await preferences.remove('dashboard_wellbeing_notes');
      } else {
        await preferences.setString('dashboard_wellbeing_notes', result.notes!);
      }
      if (!mounted) return;
      setState(() => _wellbeing = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l('Your check-in was saved', 'تم حفظ حالتكِ اليوم')),
        ),
      );
    } catch (error, stack) {
      // WellbeingRepository.upsertToday() has no internal AppErrorReporter
      // call of its own (unlike CycleTrackingRepositoryImpl) — this was a
      // genuinely silent failure until now (RR-001/DI-002 pattern): the
      // user saw an honest error, but the operator had zero visibility.
      AppErrorReporter.report(
        error,
        stack,
        context: 'DashboardScreen._showWellbeingCheckIn',
        feature: 'wellbeing',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              'Could not save your check-in. Please try again.',
              'تعذر حفظ حالتكِ. حاولي مرة أخرى.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _loadWellbeingCheckIn() async {
    final preferences = await SharedPreferences.getInstance();
    final today = AppClock.now();
    final key = '${today.year}-${today.month}-${today.day}';
    if (preferences.getString('dashboard_wellbeing_date') != key || !mounted) {
      return;
    }
    final mood = preferences.getInt('dashboard_wellbeing_mood');
    final energy = preferences.getInt('dashboard_wellbeing_energy');
    final sleep = preferences.getInt('dashboard_wellbeing_sleep');
    if (mood == null || energy == null || sleep == null) return;
    setState(
      () => _wellbeing = _WellbeingCheckInResult(
        mood: mood,
        energy: energy,
        sleep: sleep,
        notes: preferences.getString('dashboard_wellbeing_notes'),
      ),
    );
  }

  void _openFullScreen(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen),
    );
  }

  /// Menstrual Data Integrity charter, Commit D — Section 6/7: the single
  /// writer for a new bleeding episode is now `bleeding_episodes`/
  /// `bleeding_observations` (via [showStartBleedingSheet]), never a
  /// direct `cycle_entries` write from this screen. `cycle_entries` is
  /// updated only as [CycleEntriesProjection]'s one-directional mirror,
  /// which the sheet itself triggers — so the dashboard reloading here is
  /// exactly the honest "prove what succeeded" step Section 7 requires,
  /// not a second, independent save.
  Future<void> _startBleeding() async {
    final started = await showStartBleedingSheet(context);
    if (started) {
      await _viewModel.loadLogs();
    }
  }

  /// Section 6/48: ending an episode needs its real id — fetched fresh
  /// rather than cached on this screen, since nothing here has tracked it
  /// so far (the dashboard's "isCurrentlyBleeding" signal still comes from
  /// the legacy `cycle_entries` derivation, which the projection keeps in
  /// sync, but does not itself carry an episode id).
  Future<void> _endBleeding() async {
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId == null) return;

    final openEpisode = await BleedingEpisodeRepositoryImpl().getOpenEpisode(
      userId,
    );
    if (openEpisode?.id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              'Could not find your active period to end it.',
              'تعذر العثور على دورتكِ النشطة لإنهائها.',
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final ended = await showEndBleedingSheet(
      context,
      episodeId: openEpisode!.id!,
      episodeStartDate: openEpisode.startDate,
    );
    if (ended) {
      await _viewModel.loadLogs();
    }
  }

  /// Commit D1 — the recurring "are you still bleeding today?" check-in,
  /// fetched against the real open episode the same way [_endBleeding]
  /// does (never assumed from the legacy Fiqh-state signal alone).
  Future<void> _checkInToday() async {
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId == null) return;

    final openEpisode = await BleedingEpisodeRepositoryImpl().getOpenEpisode(
      userId,
    );
    if (openEpisode?.id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              'Could not find your active period to check in on.',
              'تعذر العثور على دورتكِ النشطة للمتابعة.',
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final outcome = await showDailyCheckinSheet(
      context,
      episodeId: openEpisode!.id!,
      episodeStartDate: openEpisode.startDate,
    );
    if (outcome != DailyCheckinOutcome.cancelled) {
      await _viewModel.loadLogs();
    }
  }

  /// Commit D4 — "add a missing day," reachable independently of today's
  /// own check-in.
  Future<void> _backfillObservation() async {
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId == null) return;

    final openEpisode = await BleedingEpisodeRepositoryImpl().getOpenEpisode(
      userId,
    );
    if (openEpisode?.id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              'Could not find your active period.',
              'تعذر العثور على دورتكِ النشطة.',
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final saved = await showBackfillObservationSheet(
      context,
      episodeId: openEpisode!.id!,
      episodeStartDate: openEpisode.startDate,
    );
    if (saved) {
      await _viewModel.loadLogs();
    }
  }
}

/// Pregnancy tracker summary shown on the dashboard while the user has
/// "أنا حامل حالياً" active — mirroring the web app's Today pregnancy view.
class _PregnancyOverview extends StatelessWidget {
  const _PregnancyOverview({
    required this.week,
    required this.onOpenDoctor,
    required this.onLogBirth,
  });

  final int week;
  final VoidCallback onOpenDoctor;
  final VoidCallback onLogBirth;

  static (String, String) _stage(int week) => switch (week) {
    <= 4 => ('مرحلة النطفة', 'بحجم حبة الخشخاش'),
    <= 8 => ('مرحلة العلقة', 'بحجم حبة الفاصولياء'),
    <= 12 => ('مرحلة المضغة', 'بحجم حبة الليمون'),
    <= 16 => ('الثلث الأول', 'بحجم ثمرة الأفوكادو'),
    <= 26 => ('الثلث الثاني', 'بحجم ثمرة الموز'),
    _ => ('الثلث الثالث', 'بحجم ثمرة البطيخ'),
  };

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    final (stageName, sizeName) = _stage(week);
    final remainingWeeks = math.max(0, 40 - week);
    final daysToBirth = remainingWeeks * 7;
    final progressPercent = ((week / 40) * 100).round();

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        key: const Key('pregnancy-overview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Baby size card ──
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0xFFFFE4E9)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _l('PREGNANCY COMPANION', 'رفيقة الحمل'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.haid,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.child_care_rounded,
                        color: AppColors.haid,
                        size: 30,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Directionality(
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$week '),
                        TextSpan(text: _l('weeks', 'أسبوع')),
                      ],
                    ),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: AppColors.emeraldInk,
                      fontFamily: AppTypography.serifFamily,
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$stageName · $sizeName',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.haid,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _l(
                    'A personal summary combining your baby\'s growth, your body changes, and what you need for care and preparation.',
                    'ملخص شخصي يجمع نمو الجنين، تغيرات جسمك، وما تحتاجينه للعناية والاستعداد.',
                  ),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$progressPercent%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_l('Week', 'الأسبوع')} $week',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Stack(
                    children: [
                      Container(height: 10, color: const Color(0xFFFCE7EB)),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerEnd,
                        widthFactor: (week / 40).clamp(0.02, 1.0),
                        child: Container(
                          height: 10,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFBBF24), Color(0xFFE11D48)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Countdown cards ──
          _PregnancyCountdownCard(
            icon: Icons.calendar_month_outlined,
            iconColor: AppColors.tahara,
            background: const Color(0xFFEFF9F3),
            label: _l('Until birth', 'حتى الولادة'),
            value: '$daysToBirth',
            unit: _l('days approximately', 'يوم تقريباً'),
            valueColor: AppColors.tahara,
          ),
          const SizedBox(height: 16),
          _PregnancyCountdownCard(
            icon: Icons.favorite_border_rounded,
            iconColor: AppColors.haid,
            background: const Color(0xFFFFF5F6),
            label: _l('Remaining', 'المتبقي'),
            value: '$remainingWeeks',
            unit: _l('weeks to go', 'أسبوع'),
            valueColor: AppColors.haid,
          ),
          const SizedBox(height: 24),
          // ── Smart pregnancy doctor section ──
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _l('SMART PREGNANCY DOCTOR', 'طبيبة الحمل الذكية'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.haid,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _l('Smart pregnancy doctor', 'طبيبة نسوة معك عند السؤال'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.emeraldInk,
                  fontFamily: AppTypography.serifFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _l(
                  'Ask about symptoms, fetal movement, nutrition, sleep, or prayer. The answer stays safe and opens only when you need it.',
                  'اسألي عن الأعراض، حركة الجنين، التغذية، النوم أو الصلاة. الدردشة محفوظة لك وتفتح فقط عندما تحتاجينها.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PregnancyChip(
                    label: _l('Reassuring answers', 'إجابات مطمئنة'),
                  ),
                  _PregnancyChip(
                    label: _l(
                      'Prayer & fasting guidance',
                      'مراقبة الصلاة والصيام',
                    ),
                  ),
                  _PregnancyChip(
                    label: _l('Danger-sign alerts', 'تنبيه عند علامات الخطر'),
                  ),
                  _PregnancyChip(
                    label: _l(
                      'Not a doctor replacement',
                      'ليست بديلاً عن الطبيبة',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onOpenDoctor,
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: const Color(0xFFFCE7EB)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.pregnant_woman_rounded,
                        color: AppColors.haid,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _l('Tap to open the chat', 'اضغطي لفتح الدردشة'),
                      style: const TextStyle(
                        color: AppColors.haid,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onOpenDoctor,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(_l('Open the chat', 'افتحي الدردشة')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.haid,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Log birth / Nifas button ──
          FilledButton.icon(
            key: const Key('pregnancy-log-birth'),
            onPressed: onLogBirth,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(
              _l('Log birth & start Nifas', 'تسجيل الولادة وبدا النفاس'),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: AppColors.emeraldInk,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PregnancyCountdownCard extends StatelessWidget {
  const _PregnancyCountdownCard({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final String label;
  final String value;
  final String unit;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: AppLocaleController.instance.isArabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$value '),
                  TextSpan(text: unit),
                ],
              ),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: valueColor,
                fontFamily: AppTypography.serifFamily,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nifas status card shown after تسجيل الولادة — explains what changes for
/// the user during the ~40-day Nifas window.
class _NifasStatusCard extends StatelessWidget {
  const _NifasStatusCard({required this.day});

  final int day;

  @override
  Widget build(BuildContext context) {
    final remaining = math.max(0, 40 - day + 1);
    return Container(
      key: const Key('nifas-status'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFFFDE6C4)),
      ),
      child: Directionality(
        textDirection: AppLocaleController.instance.isArabic
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _l('NIFAS', 'نفاس'),
                        style: const TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 9,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _l('Nifas tracking started', 'تم بدء متابعة النفاس'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.emeraldInk,
                          fontFamily: AppTypography.serifFamily,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_l('Day', 'اليوم')} $day/40',
                  style: const TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _l(
                'Bleeding after birth is treated like Haid: salah is lifted while bleeding continues, and ghusl is required once it stops. Your cycle pattern will rebuild from your next Haid.',
                'الدم بعد الولادة حكمه حكم الحيض: الصلاة مرفوعة ما دام الدم مستمراً، ويجب الاغتسال عند انقطاعه. سيُعاد بناء نمط دورتكِ من الحيض القادم.',
              ),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                children: [
                  Container(height: 8, color: const Color(0xFFFDE6C4)),
                  FractionallySizedBox(
                    widthFactor: (day / 40).clamp(0.02, 1.0),
                    child: Container(height: 8, color: const Color(0xFFD97706)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_l('Up to', 'حتى')} $remaining ${_l('days remaining', 'يوم متبقٍ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PregnancyChip extends StatelessWidget {
  const _PregnancyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InsufficientCycleDataCard extends StatelessWidget {
  const _InsufficientCycleDataCard({required this.onLog});

  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB), width: 8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF1F3F4), width: 12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: AppColors.haid,
                        size: 24,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _l(
                          'Log your cycle to see your day',
                          'سجّلي دورتكِ لمعرفة يومكِ',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.emeraldInk,
                          fontFamily: AppTypography.serifFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _l(
                          'Two Haid starts are needed for your personal pattern.',
                          'نحتاج إلى بدايتَي حيض لحساب نمطكِ الشخصي.',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontSize: 10, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            top: 46,
            right: 25,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFF1F2),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.circle_outlined,
                  size: 18,
                  color: AppColors.haid,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: 176,
        height: 48,
        child: FilledButton.icon(
          key: const Key('today-cycle-log'),
          onPressed: onLog,
          icon: const Icon(Icons.water_drop_outlined, size: 17),
          label: Text(_l('Log cycle', 'تسجيل الدورة')),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.haid,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ],
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.viewModel,
    required this.onNotificationsTap,
  });

  final CycleTrackingViewModel viewModel;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    final name = viewModel.currentUser?.displayName;
    final greetingName = (name == null || name.trim().isEmpty)
        ? _l('Sister', 'أختي')
        : name;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l('Niswah', 'نسوة'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF5EEAD4)
                        : AppColors.emeraldInk,
                    fontFamily: AppTypography.serifFamily,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_l('WELCOME', 'أهلاً')}, $greetingName',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF99F6E4)
                        : AppColors.tahara.withValues(alpha: 0.6),
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: NotificationLogController.instance,
            builder: (context, _) {
              final unreadCount =
                  NotificationLogController.instance.unreadCount;
              return Semantics(
                button: true,
                label: unreadCount > 0
                    ? _l(
                        'Notifications, $unreadCount unread',
                        'التنبيهات، $unreadCount غير مقروءة',
                      )
                    : _l('Notifications', 'التنبيهات'),
                // Without this, the unread-count badge's own Text merges
                // into this label as an awkward newline-joined fragment
                // instead of the deliberately-composed sentence above.
                excludeSemantics: true,
                child: InkResponse(
                  onTap: onNotificationsTap,
                  radius: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF5EEAD4)
                            : AppColors.emeraldInk,
                        size: 27,
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: -2,
                          top: -3,
                          child: Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.brandSecondary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Real elapsed day-within-the-active-segment, shared by the ring's
/// progress arc and the stepper's active node so they always agree.
/// Haid is grounded in [daysIntoCurrentEpisode] (real log data); an active
/// tahara segment is positioned via [cycleDayEstimate] clamped to that
/// segment's own span — legitimate here only because it's deciding WHERE
/// within "currently not bleeding" she is, never WHETHER she's bleeding.
int? _dayInActiveSegment({
  required CycleSegmentPlan segmentPlan,
  required int? daysIntoCurrentEpisode,
  required int? cycleDayEstimate,
}) {
  final active = segmentPlan.active;
  if (active == null) return null;
  if (active.id == CycleSegmentId.haid) {
    return daysIntoCurrentEpisode;
  }
  var startOffset = 1;
  for (final segment in segmentPlan.segments) {
    if (segment.id == active.id) break;
    startOffset += segment.durationDays;
  }
  final estimate = cycleDayEstimate ?? startOffset;
  final relative = estimate - startOffset + 1;
  return relative.clamp(1, active.durationDays);
}

Color _segmentColor(CycleSegmentId id) => switch (id) {
  CycleSegmentId.haid => AppColors.haid,
  CycleSegmentId.tahara1 || CycleSegmentId.tahara2 => AppColors.tahara,
  CycleSegmentId.fertile => AppColors.nifas,
  CycleSegmentId.prePeriod => AppColors.istihadah,
  CycleSegmentId.expected => AppColors.brandSecondary,
};

String _segmentLabel(CycleSegmentId id) => switch (id) {
  CycleSegmentId.haid => _l('Haid', 'حيض'),
  CycleSegmentId.tahara1 || CycleSegmentId.tahara2 => _l('Tahara', 'طهارة'),
  CycleSegmentId.fertile => _l('Fertile', 'خصوبة'),
  CycleSegmentId.prePeriod => _l('Pre-Period', 'ما قبل الحيض'),
  CycleSegmentId.expected => _l('Expected Period', 'حيض متوقع'),
};

class _CycleOverview extends StatelessWidget {
  const _CycleOverview({
    required this.summary,
    required this.cycleDay,
    required this.state,
    required this.isCurrentlyBleeding,
    required this.onTap,
    this.confirmAt,
    this.daysIntoCurrentEpisode,
  });

  final CycleTrackingSummary summary;
  final int cycleDay;
  final _FiqhState state;

  /// Whether the fiqh state counts as "currently bleeding" — haid,
  /// needsAdvisory, or istihadah. Computed once in the parent and shared
  /// with [_QuickActions] so the two widgets never disagree about it.
  final bool isCurrentlyBleeding;
  final VoidCallback onTap;
  final DateTime? confirmAt;

  /// Real elapsed days into the current bleeding episode (from
  /// [CycleStatusEngine]) — null when not currently bleeding. Used by the
  /// pill and the stepper's Haid node so they never disagree with the
  /// ring about how far into the episode the user actually is.
  final int? daysIntoCurrentEpisode;

  @override
  Widget build(BuildContext context) {
    final cycleLength = summary.averageCycleLength!;
    // When the real average isn't known yet, fall back to the real elapsed
    // days of the current episode (not a guess at the eventual total) —
    // without this, the outer ring draws the Haid zone as a literal
    // zero-width arc (sweep = 2π × 0 / cycleLength), an invisible gap where
    // the segment should be, even though the inner progress arc still
    // correctly fills in real days via daysIntoCurrentEpisode. When not
    // currently bleeding, 0 is correct and harmless — the segment is
    // dropped entirely by CycleSegmentPlanner's own durationDays > 0 filter.
    // The visible "of N" denominator is driven separately by
    // summary.averagePeriodLength directly (see _PhaseTimeline), so this
    // value is never shown to the user as a period-length claim.
    final periodLength =
        summary.averagePeriodLength ??
        (isCurrentlyBleeding ? (daysIntoCurrentEpisode ?? 0) : 0);
    final overdue = cycleDay > cycleLength;
    final lastCycleStart = summary.lastCycleStart;
    final segmentPlan = lastCycleStart == null
        ? const CycleSegmentPlan(segments: [], activeIndex: null)
        : const CycleSegmentPlanner().plan(
            cycleLength: cycleLength,
            periodLength: periodLength,
            fertileWindow: summary.fertileWindow,
            cycleStart: lastCycleStart,
            isBleedingNow: isCurrentlyBleeding,
            cycleDayEstimate: cycleDay,
          );
    final dayInActiveSegment = _dayInActiveSegment(
      segmentPlan: segmentPlan,
      daysIntoCurrentEpisode: daysIntoCurrentEpisode,
      cycleDayEstimate: cycleDay,
    );
    return Column(
      children: [
        Semantics(
          button: true,
          label:
              '${_l('Cycle day', 'يوم الدورة')} $cycleDay، ${_stateLabel(state)}',
          // Without this, the ring's own headline/subtitle Text merges in
          // as redundant trailing fragments of this already-complete label.
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('today-cycle-ring'),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 280,
              child: _AnimatedCycleRing(
                cycleLength: cycleLength,
                periodLength: periodLength,
                currentDay: cycleDay,
                activeColor: state.color,
                segmentPlan: segmentPlan,
                dayInActiveSegment: dayInActiveSegment,
                trackColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF292929)
                    : const Color(0xFFF5F5F5),
                markerColor: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    child: Builder(
                      builder: (context) {
                        final (headline, subtitle) = _ringCenterText(
                          state: state,
                          dayInActiveSegment: dayInActiveSegment,
                          confirmAt: confirmAt,
                          segmentPlan: segmentPlan,
                          averagePeriodLength: summary.averagePeriodLength,
                        );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // AU-006: this text sits inside a fixed 280px
                            // circle with no scale-down wrapper — at large
                            // OS text-scale settings it could clip/overlap
                            // the ring, including the state name a user
                            // reads first here.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                headline,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: state.color,
                                  fontFamily: AppTypography.serifFamily,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                    letterSpacing: 0.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Container(
                              width: 32,
                              height: 1,
                              color: Theme.of(context).dividerColor,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildStateMessage(context, overdue, segmentPlan, dayInActiveSegment),
        const SizedBox(height: 24),
        _PhaseTimeline(
          segmentPlan: segmentPlan,
          dayInActiveSegment: dayInActiveSegment,
          averagePeriodLength: summary.averagePeriodLength,
        ),
      ],
    );
  }

  Widget _buildStateMessage(
    BuildContext context,
    bool overdue,
    CycleSegmentPlan segmentPlan,
    int? dayInActiveSegment,
  ) {
    final isAdvisoryState =
        state == _FiqhState.needsAdvisory || state == _FiqhState.istihadah;
    final isWaiting = isAdvisoryState && confirmAt != null;
    final needsConsult = isAdvisoryState && confirmAt == null;
    // Fiqh Remediation Wave 1 (Section E): bleeding, but no Madhhab
    // SELECTED — treated as its own "needs your input" case, distinct
    // from `needsConsult` (which means "a madhhab is selected but this
    // case needs a human"), never silently folded into tahara/haid.
    final needsMadhhabSelection = state == _FiqhState.madhhabUnresolved;
    final averagePeriodLength = summary.averagePeriodLength;
    final message = switch (state) {
      _FiqhState.haid =>
        overdue
            ? _l(
                'Cycle exceeds the recorded average',
                'تجاوزت الدورة متوسطها المسجل',
              )
            : averagePeriodLength != null && daysIntoCurrentEpisode != null
            ? '${_l('Tahara in', 'الطُهر خلال')} ${math.max(1, averagePeriodLength - daysIntoCurrentEpisode! + 1)} ${_l('days', 'أيام')}'
            : _l(
                'Tracking your period — a tahara estimate will appear once one full cycle is recorded.',
                'نتابع حيضك — سيظهر تقدير الطُهر بعد تسجيل دورة كاملة.',
              ),
      _FiqhState.needsAdvisory || _FiqhState.istihadah =>
        isWaiting
            ? _l(
                'Bleeding detected — awaiting confirmation per your madhhab.',
                'تم رصد نزيف، بانتظار التأكيد حسب مذهبك.',
              )
            : _l(
                'This bleeding pattern falls outside your madhhab\'s usual range — please consult a trusted source.',
                'نمط هذا النزيف يخرج عن الحدود المعتادة في مذهبك، يُنصح باستشارة مصدر موثوق.',
              ),
      _FiqhState.tahara => _nextSegmentMessage(segmentPlan, dayInActiveSegment),
      _FiqhState.madhhabUnresolved => _l(
        'Bleeding detected — select your Madhhab in Settings to see your Fiqh state.',
        'تم رصد نزيف — يُرجى اختيار مذهبكِ من الإعدادات لمعرفة حالتكِ الفقهية.',
      ),
    };
    final isNextSegmentArrow =
        !isWaiting && !needsConsult && !needsMadhhabSelection;
    final icon = isWaiting
        ? Icons.hourglass_top_rounded
        : needsConsult || needsMadhhabSelection
        ? Icons.info_outline_rounded
        : Icons.arrow_back_rounded;
    final iconWidget = Icon(icon, size: 18, color: state.color);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: state.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: state.color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isNextSegmentArrow
                    ? Transform.flip(flipX: true, child: iconWidget)
                    : iconWidget,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            if (isWaiting) ...[
              const SizedBox(height: 14),
              _LiveCountdown(target: confirmAt!, color: state.color),
            ],
          ],
        ),
      ),
    );
  }

  /// "{next segment} in N days" — N is days remaining in the currently
  /// active segment, using the same [dayInActiveSegment] the stepper's
  /// active node shows, so the pill and the stepper always agree.
  String _nextSegmentMessage(
    CycleSegmentPlan segmentPlan,
    int? dayInActiveSegment,
  ) {
    final active = segmentPlan.active;
    if (active == null || dayInActiveSegment == null) {
      return _l(
        'Tracking your cycle — a prediction will appear once one full '
            'cycle is recorded.',
        'نتابع دورتك — سيظهر تقدير بعد تسجيل دورة كاملة.',
      );
    }
    final activeIndex = segmentPlan.segments.indexOf(active);
    final nextSegment =
        segmentPlan.segments[(activeIndex + 1) % segmentPlan.segments.length];
    final daysRemaining = math.max(
      1,
      active.durationDays - dayInActiveSegment + 1,
    );
    return '${_segmentLabel(nextSegment.id)} ${_l('in', 'خلال')} '
        '$daysRemaining ${_l('days', 'أيام')}';
  }
}

/// Ticks every second on its own timer so a needsAdvisory countdown feels
/// alive, without forcing the rest of the dashboard to rebuild each second
/// (the dashboard's own 1-minute timer still handles the actual state
/// transition once the target is reached).
class _LiveCountdown extends StatefulWidget {
  const _LiveCountdown({required this.target, required this.color});

  final DateTime target;
  final Color color;

  @override
  State<_LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<_LiveCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.target.difference(AppClock.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = widget.target.difference(AppClock.now());
      });
    });
  }

  @override
  void didUpdateWidget(covariant _LiveCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _remaining = widget.target.difference(AppClock.now());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clamped = _remaining.isNegative ? Duration.zero : _remaining;
    final hours = clamped.inHours;
    final minutes = clamped.inMinutes % 60;
    final seconds = clamped.inSeconds % 60;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _countdownUnit(context, hours, _l('hrs', 'ساعة')),
        _countdownSeparator(),
        _countdownUnit(context, minutes, _l('min', 'دقيقة')),
        _countdownSeparator(),
        _countdownUnit(context, seconds, _l('sec', 'ثانية')),
      ],
    );
  }

  Widget _countdownSeparator() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      ':',
      style: TextStyle(
        color: widget.color,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        height: 1,
      ),
    ),
  );

  Widget _countdownUnit(BuildContext context, int value, String label) {
    return Column(
      children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.color.withValues(alpha: 0.3)),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.color,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isCurrentlyBleeding,
    required this.onStart,
    required this.onEnd,
    this.onCheckIn,
    this.onBackfill,
  });

  /// Whether the fiqh state counts as "currently bleeding" — haid,
  /// needsAdvisory, or istihadah, matching [_CycleOverview]'s definition so
  /// the two widgets never disagree about it.
  final bool isCurrentlyBleeding;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  /// Commit D1 — the recurring daily check-in, only meaningful while an
  /// episode is actually open. Null (and therefore not rendered) whenever
  /// there is no open canonical episode to check in against, even if
  /// [isCurrentlyBleeding] (the legacy Fiqh-state signal) is somehow true.
  final VoidCallback? onCheckIn;

  /// Commit D4 — "I forgot to log a day," reachable any time an episode
  /// is open, independent of today's own check-in state.
  final VoidCallback? onBackfill;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCurrentlyBleeding && onCheckIn != null) ...[
          FilledButton.icon(
            onPressed: onCheckIn,
            icon: const Icon(Icons.today_outlined, size: 18),
            label: Text(_l('Daily check-in', 'المتابعة اليومية')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.haid,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _startEndRow(context),
        if (isCurrentlyBleeding && onBackfill != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onBackfill,
            icon: const Icon(Icons.history_edu_outlined, size: 16),
            label: Text(_l('Add a missing day', 'إضافة يوم فائت')),
          ),
        ],
      ],
    );
  }

  Widget _startEndRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: isCurrentlyBleeding ? null : onStart,
            icon: const Icon(Icons.water_drop_outlined, size: 18),
            label: Text(_l('Period Started', 'بدأ الحيض')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.haid,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Theme.of(context).disabledColor
                  .withValues(alpha: 0.12),
              disabledForegroundColor: Theme.of(context).disabledColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isCurrentlyBleeding ? onEnd : null,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text(_l('Period Ended', 'انتهى الحيض')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.haid,
              side: BorderSide(
                color: isCurrentlyBleeding
                    ? const Color(0xFFFECDD3)
                    : Theme.of(context).dividerColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WellbeingCard extends StatelessWidget {
  const _WellbeingCard({required this.onLog, required this.checkIn});

  final VoidCallback onLog;
  final _WellbeingCheckInResult? checkIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBF8),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFFDDF4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _l('Mental state check-in', 'متابعة الحالة النفسية'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        // AU-003: AppColors.tahara only clears 3.74:1 —
                        // taharaText is the same hue darkened to clear the
                        // 4.5:1 bar this small (9px) text needs.
                        color: AppColors.taharaText,
                        fontSize: 9,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _l('How is your mood today?', 'كيف نفسيتكِ اليوم؟'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.emeraldInk,
                        fontFamily: AppTypography.serifFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onLog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppColors.emeraldInk,
                  side: BorderSide.none,
                  minimumSize: const Size(58, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: Text(
                  _l('Log', 'تسجيل'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _l(
              'Log mood, energy, sleep, and light symptoms to understand your pattern.',
              'دوّني مزاجكِ، طاقتكِ، نومكِ وأي أعراض خفيفة لتفهمي نمطكِ بهدوء.',
            ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _WellbeingMetric(
                  label: _l('Mood', 'المزاج'),
                  value: checkIn?.mood,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WellbeingMetric(
                  label: _l('Energy', 'طاقة'),
                  value: checkIn?.energy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WellbeingMetric(
                  label: _l('Sleep', 'نوم'),
                  value: checkIn?.sleep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLog,
              icon: const Icon(Icons.favorite_border_rounded, size: 17),
              label: Text(
                _l('Log your mental state now', 'سجلي حالتكِ النفسية الآن'),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.tahara,
                backgroundColor: Colors.white.withValues(alpha: 0.7),
                side: const BorderSide(color: Color(0xFFD1FAE5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WellbeingMetric extends StatelessWidget {
  const _WellbeingMetric({required this.label, required this.value});
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 8,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value == null ? '—' : '$value/5',
          style: const TextStyle(
            color: AppColors.emeraldInk,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _WellbeingCheckInResult {
  const _WellbeingCheckInResult({
    required this.mood,
    required this.energy,
    required this.sleep,
    this.notes,
  });

  final int mood;
  final int energy;
  final int sleep;

  /// Optional free-text note — null/empty when nothing was written, never
  /// a fabricated placeholder.
  final String? notes;
}

class _WellbeingCheckInSheet extends StatefulWidget {
  const _WellbeingCheckInSheet();

  @override
  State<_WellbeingCheckInSheet> createState() => _WellbeingCheckInSheetState();
}

class _WellbeingCheckInSheetState extends State<_WellbeingCheckInSheet> {
  int _mood = 3;
  int _energy = 3;
  int _sleep = 3;
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 0,
                    top: -6,
                    child: Semantics(
                      container: true,
                      button: true,
                      label: _l('Close', 'إغلاق'),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x16000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          // Pops with no value — the sheet's caller
                          // (_showWellbeingCheckIn) already treats a null
                          // result as "user backed out, don't save
                          // anything", the same as tapping the barrier.
                          onTap: () => Navigator.of(context).pop(),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.close_rounded,
                              color: Color(0xFF9CA3AF),
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _l('Today’s mental check-in', 'تسجيل حالتكِ النفسية اليوم'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.emeraldInk,
                  fontFamily: AppTypography.serifFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _l(
                  'This is separate from cycle and bleeding records.',
                  'هذا التسجيل مستقل عن بيانات الدورة والدم.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              RatingScaleRow(
                label: _l('Mood', 'المزاج'),
                icon: Icons.sentiment_satisfied_alt_rounded,
                iconBuilder: moodRatingIcon,
                activeColor: const Color(0xFFFB7185),
                value: _mood,
                descriptionBuilder: moodRatingDescription,
                onChanged: (value) => setState(() => _mood = value),
              ),
              const SizedBox(height: 20),
              RatingScaleRow(
                label: _l('Energy', 'الطاقة'),
                icon: Icons.bolt_rounded,
                activeColor: const Color(0xFFF59E0B),
                value: _energy,
                descriptionBuilder: energyRatingDescription,
                onChanged: (value) => setState(() => _energy = value),
              ),
              const SizedBox(height: 20),
              RatingScaleRow(
                label: _l('Sleep', 'النوم'),
                icon: Icons.bedtime_outlined,
                activeColor: const Color(0xFF0D9488),
                value: _sleep,
                descriptionBuilder: sleepRatingDescription,
                onChanged: (value) => setState(() => _sleep = value),
              ),
              const SizedBox(height: 24),
              Text(
                _l('Notes', 'ملاحظات'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.emeraldInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: _l(
                    'Anything you want to remember about today…',
                    'أي شيء تريدين تذكره عن يومكِ...',
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFF1F2F4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFF1F2F4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.tahara),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () {
                  final notes = _notesController.text.trim();
                  Navigator.of(context).pop(
                    _WellbeingCheckInResult(
                      mood: _mood,
                      energy: _energy,
                      sleep: _sleep,
                      notes: notes.isEmpty ? null : notes,
                    ),
                  );
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(_l('Save check-in', 'حفظ الحالة')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: AppColors.emeraldInk,
                  elevation: 2,
                  shadowColor: AppColors.emeraldInk.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorNiswahCard extends StatelessWidget {
  const _DoctorNiswahCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _DashboardActionCard(
    onTap: onTap,
    icon: Icons.medical_services_outlined,
    iconColor: AppColors.tahara,
    title: _l('Doctor Niswah', 'الطبيبة نسوة'),
    subtitle: _l(
      'Ask about your symptoms — suggestions based on your data',
      'اسألي عن أعراضكِ — اقتراحات مبنية على بياناتكِ',
    ),
    trailing: Icons.auto_awesome_rounded,
  );
}

class _PrayerStatusCard extends StatelessWidget {
  const _PrayerStatusCard({required this.viewModel, required this.fiqhState});

  final PrayerTrackingViewModel viewModel;
  final _FiqhState fiqhState;

  @override
  Widget build(BuildContext context) {
    final lifted = fiqhState == _FiqhState.haid;
    final names = {
      prayer.PrayerName.fajr: _l('Fajr', 'الفجر'),
      prayer.PrayerName.dhuhr: _l('Dhuhr', 'الظهر'),
      prayer.PrayerName.asr: _l('Asr', 'العصر'),
      prayer.PrayerName.maghrib: _l('Maghrib', 'المغرب'),
      prayer.PrayerName.isha: _l('Isha', 'العشاء'),
    };
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.shadowColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lifted
                          ? _l('Salah is lifted', 'الصلاة مرفوعة عنكِ')
                          : _l('Salah is obligatory', 'الصلاة واجبة عليكِ'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: lifted
                            ? const Color(0xFF881337)
                            : AppColors.emeraldInk,
                        fontFamily: AppTypography.serifFamily,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lifted
                          ? _l(
                              'Your obligations change based on your Fiqh state',
                              'تتغير عباداتكِ حسب حالتكِ الفقهية',
                            )
                          : _l(
                              'Prayer times help identify prayers affected by Haid and when Ghusl is due.',
                              'نظهر أوقات الصلاة لمعرفة الصلوات المتأثرة بالحيض وموعد الاغتسال.',
                            ),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _l('Makkah', 'مكة المكرمة'),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GridView.builder(
            itemCount: prayer.PrayerName.values.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 109,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final name = prayer.PrayerName.values[index];
              final status = lifted
                  ? _l('Lifted', 'مرفوعة')
                  : _prayerStatus(viewModel.statusFor(name));
              final time = viewModel.schedule.timeFor(name);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFCFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.shadowColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (lifted ? AppColors.haid : AppColors.tahara)
                                .withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: lifted ? AppColors.haid : AppColors.tahara,
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          name == prayer.PrayerName.fajr ||
                                  name == prayer.PrayerName.isha
                              ? Icons.nightlight_round
                              : Icons.wb_sunny_outlined,
                          color:
                              name == prayer.PrayerName.fajr ||
                                  name == prayer.PrayerName.isha
                              ? AppColors.warning
                              : AppColors.textTertiary,
                          size: 17,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      names[name]!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time == null
                          ? '—'
                          : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _prayerStatus(prayer.PrayerStatus status) => switch (status) {
    prayer.PrayerStatus.pending => _l('Upcoming', 'قادمة'),
    prayer.PrayerStatus.completed => _l('Prayed', 'صُلّيت'),
    prayer.PrayerStatus.missed => _l('Missed', 'فائتة'),
    prayer.PrayerStatus.excused => _l('Lifted', 'مرفوعة'),
  };
}

class _DreamCard extends StatelessWidget {
  const _DreamCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _DashboardActionCard(
    onTap: onTap,
    icon: Icons.nightlight_round,
    iconColor: AppColors.istihadah,
    title: _l('Dream Interpretation', 'تفسير الأحلام'),
    subtitle: _l(
      'Share your vision for an Islamic-based interpretation',
      'شاركي رؤياكِ لتفسير مبني على المنظور الإسلامي',
    ),
    trailing: Icons.chevron_right_rounded,
  );
}

class _AiQuickAccessCard extends StatelessWidget {
  const _AiQuickAccessCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _DashboardActionCard(
    onTap: onTap,
    icon: Icons.auto_awesome_rounded,
    iconColor: AppColors.istihadah,
    title: _l(
      'Ask any Fiqh or health question...',
      'اسألي أي سؤال فقهي أو صحي...',
    ),
    subtitle: _l(
      'Qadha Example: Missed Dhuhr',
      'مثال قضاء: صلاة الظهر الفائتة',
    ),
    trailing: Icons.bolt_rounded,
  );
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.onTap,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final VoidCallback onTap;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final IconData trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(28),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.shadowColor),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.emeraldInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 9,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(trailing, color: iconColor, size: 20),
          ],
        ),
      ),
    ),
  );
}

class _IstihadahToggle extends StatelessWidget {
  const _IstihadahToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.shadowColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.istihadah.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.water_drop_outlined,
              color: AppColors.istihadah,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l('Istihadah Mode', 'وضع الاستحاضة'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.emeraldInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _l(
                    'Advanced Fiqh tracking for irregular bleeding',
                    'تتبع فقهي متقدم للنزيف غير المنتظم',
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.istihadah,
            activeThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE5E7EB),
            inactiveThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _FiqhStateBanner extends StatelessWidget {
  const _FiqhStateBanner({
    super.key,
    required this.state,
    required this.cycleDay,
    required this.madhhab,
    required this.onLogBlood,
    required this.onAskAdvisor,
  });

  final _FiqhState state;
  final int cycleDay;
  final String madhhab;
  final VoidCallback onLogBlood;
  final VoidCallback onAskAdvisor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: state.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border(left: BorderSide(color: state.color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _stateLabel(state),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: state.color,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            switch (state) {
              _FiqhState.haid => _l('Salah is lifted', 'الصلاة مرفوعة عنكِ'),
              _FiqhState.tahara => _l(
                'Prayer and fasting are obligatory. You are in a state of purity.',
                'الصلاة والصيام واجبان، وأنتِ في حالة طُهر.',
              ),
              _FiqhState.istihadah => _l(
                'Please log your blood details so we can determine your Fiqh obligation.',
                'يرجى تسجيل تفاصيل الدم لتحديد حكمكِ الفقهي.',
              ),
              _FiqhState.needsAdvisory => _l(
                'This case is outside the basic tracking window and needs a case-specific review.',
                'هذه الحالة خارج نطاق الحساب الأساسي وتحتاج إلى مراجعة خاصة بالحالة.',
              ),
              // Fiqh Remediation Wave 1 (Section E): bleeding, but no
              // Madhhab SELECTED — asked explicitly, never guessed.
              _FiqhState.madhhabUnresolved => _l(
                'Select your Madhhab in Settings to see your current Fiqh obligation.',
                'يُرجى اختيار مذهبكِ من الإعدادات لمعرفة حكمكِ الفقهي الحالي.',
              ),
            },
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (state == _FiqhState.haid) ...[
            const SizedBox(height: 8),
            Text(
              _l(
                'Based on ${madhhab.toUpperCase()} madhhab',
                'بناءً على المذهب ال${madhhab.toUpperCase()}',
              ),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: state.color.withValues(alpha: 0.55),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ],
          if (state == _FiqhState.istihadah) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onLogBlood,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                _l('Log today\'s blood', 'سجلي دم اليوم'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (state == _FiqhState.needsAdvisory) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAskAdvisor,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
              label: Text(
                _l('Ask the Fiqh advisor', 'اسألي المستشارة الفقهية'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhaseTimeline extends StatelessWidget {
  const _PhaseTimeline({
    required this.segmentPlan,
    this.dayInActiveSegment,
    this.averagePeriodLength,
  });

  final CycleSegmentPlan segmentPlan;

  /// Real day-within-the-active-segment (haid: grounded in logs; active
  /// tahara: positioned via the flow-blind estimate — see
  /// [_dayInActiveSegment]). Only the active node ever uses this; every
  /// other node shows its own flat, static duration — never "day X of Y".
  final int? dayInActiveSegment;

  /// Real average completed-period length — null when no full episode has
  /// ever been recorded. The active Haid node's "of N" denominator only
  /// appears when this is non-null; it is never a fabricated placeholder.
  final int? averagePeriodLength;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 88,
      child: Stack(
        children: [
          PositionedDirectional(
            start: 16,
            end: 16,
            top: 47,
            child: Container(height: 1, color: const Color(0xFFE5E7EB)),
          ),
          // This strip is the ring's closed loop unrolled flat, cut open at
          // the one real seam in an otherwise repeating cycle — between
          // "expected" (last node) and "haid" (first node). Without a cue,
          // the two ends read as unrelated dead ends instead of the same
          // seam; a small loop glyph at each edge signals they connect.
          const PositionedDirectional(start: 2, top: 40, child: _LoopEndCue()),
          const PositionedDirectional(end: 2, top: 40, child: _LoopEndCue()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < segmentPlan.segments.length; index++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final segment = segmentPlan.segments[index];
                      final active = index == segmentPlan.activeIndex;
                      final String value;
                      final String unit;
                      if (active && dayInActiveSegment != null) {
                        value = '$dayInActiveSegment';
                        final denominator = _activeSegmentDenominator(
                          segmentPlan,
                          averagePeriodLength,
                        );
                        unit = denominator != null && denominator > 0
                            ? _l('of $denominator', 'من $denominator')
                            : _l('day', 'يوم');
                      } else {
                        value = '${segment.durationDays}';
                        unit = _l('days', 'يوم');
                      }
                      return _PhaseNode(
                        key: Key('phase-node-${segment.id.name}'),
                        value: value,
                        unit: unit,
                        label: _segmentLabel(segment.id),
                        color: _segmentColor(segment.id),
                        active: active,
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Marks one open end of [_PhaseTimeline]'s unrolled cycle-loop strip —
/// see the wrap-around comment at its call sites for why this is needed.
class _LoopEndCue extends StatelessWidget {
  const _LoopEndCue();

  @override
  Widget build(BuildContext context) => Semantics(
    label: _l('The cycle repeats', 'الدورة تتكرر'),
    child: const Icon(
      Icons.all_inclusive_rounded,
      size: 13,
      color: Color(0xFFD1D5DB),
    ),
  );
}

class _PhaseNode extends StatelessWidget {
  const _PhaseNode({
    super.key,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
    this.active = false,
  });
  final String value;
  final String unit;
  final String label;
  final Color color;
  final bool active;
  @override
  Widget build(BuildContext context) {
    // AU-002: this custom visualization otherwise renders as several
    // disconnected Text/Icon fragments to a screen reader (value, unit,
    // label, "YOU ARE HERE"). One merged, meaningful announcement per node
    // — e.g. "Haid, day 3 of 5, current phase" — replaces that fragment
    // sequence; `excludeSemantics` hides the descendant text/icon nodes
    // (including the purely decorative "current" marker dot, AU-010) so
    // they aren't announced a second time on top of this label.
    final semanticLabel = active
        ? '$label, $value $unit, ${_l('current phase', 'المرحلة الحالية')}'
        : '$label, $value $unit';

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 27,
            child: active
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _l('YOU ARE HERE', 'أنتِ هنا'),
                          maxLines: 1,
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        color: color,
                        size: 12,
                      ),
                    ],
                  )
                : null,
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: active ? 42 : 32,
                height: active ? 42 : 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFFFF1F2)
                      : const Color(0xFFF9FAFB),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? color : const Color(0xFFE5E7EB),
                    width: active ? 2.25 : 1.35,
                  ),
                ),
                // AU-006: value/unit text was rendered directly inside this
                // fixed-diameter circle with no scale-down wrapper — at
                // large OS text-scale settings it would clip against the
                // circle's edge. FittedBox matches the treatment already
                // used for "YOU ARE HERE" above.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          color: color,
                          fontSize: active ? 13 : 11,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        unit,
                        style: TextStyle(
                          color: active ? color : AppColors.textTertiary,
                          fontSize: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (active)
                Positioned(
                  right: -3,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2.25),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 18,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: color,
                fontSize: 8,
                height: 1.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  const _CycleRingPainter({
    required this.cycleLength,
    required this.periodLength,
    required this.currentDay,
    required this.activeColor,
    required this.pulse,
    required this.segmentPlan,
    required this.dayInActiveSegment,
    required this.trackColor,
    required this.markerColor,
  });

  final int cycleLength;
  final int periodLength;
  final int currentDay;
  final Color activeColor;
  final double pulse;
  final CycleSegmentPlan segmentPlan;
  final int? dayInActiveSegment;
  final Color trackColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const outerRadius = 137.0;
    const innerRadius = 114.0;
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);
    const start = -math.pi / 2;
    const outerGap = 2.0;
    final outerCircumference = math.pi * 2 * outerRadius;
    // The ring's own angular denominator: the sum of every segment it's
    // actually about to draw, not the raw statistical cycleLength. They
    // normally match, but CycleSegmentPlanner floors placement segments at
    // a minimum of 1 day each for unusually short real cycles, which can
    // push their sum past cycleLength — dividing by cycleLength in that
    // case would sweep past 360° and overlap segments onto each other.
    final ringTotalDays = segmentPlan.totalDays > 0
        ? segmentPlan.totalDays
        : cycleLength;
    var accumulated = 0.0;
    for (var i = 0; i < segmentPlan.segments.length; i++) {
      final segment = segmentPlan.segments[i];
      final sweep = math.pi * 2 * segment.durationDays / ringTotalDays;
      final isActive = i == segmentPlan.activeIndex;
      final dashed = segment.id == CycleSegmentId.expected;
      final paint = Paint()
        ..color = _segmentColor(segment.id).withValues(alpha: isActive ? 1 : .3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      if (dashed) {
        final dashSweep = 4 / outerCircumference * math.pi * 2;
        final dashGap = 2 / outerCircumference * math.pi * 2;
        var offset = 0.0;
        while (offset < sweep) {
          canvas.drawArc(
            outerRect,
            start + accumulated + offset,
            math.min(dashSweep, sweep - offset),
            false,
            paint,
          );
          offset += dashSweep + dashGap;
        }
      } else {
        final gapSweep = outerGap / outerCircumference * math.pi * 2;
        canvas.drawArc(
          outerRect,
          start + accumulated,
          math.max(0, sweep - gapSweep),
          false,
          paint,
        );
      }
      accumulated += sweep;
    }
    canvas.drawArc(
      innerRect,
      start,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16,
    );
    final overdue = currentDay > cycleLength;
    // No haid/tahara segment survived CycleSegmentPlanner's filtering (an
    // extremely short real cycle can squeeze both tahara instances to zero
    // duration with no historical period length to keep haid visible
    // either) — there is no real "current position" to point to. Drawing
    // the marker anyway would default activeSegmentStart to 0 and land it
    // at the start of whatever segment happens to be first in the list
    // (e.g. prePeriod), silently misrepresenting an unrelated phase as
    // current. Skip the progress arc and marker entirely instead.
    final hasActiveSegment = overdue || segmentPlan.activeIndex != null;
    if (hasActiveSegment) {
      double progressStartDay;
      double progressDays;
      if (overdue) {
        progressStartDay = ringTotalDays - 1.0;
        progressDays = periodLength.toDouble();
      } else {
        var activeSegmentStart = 0;
        for (var i = 0; i < segmentPlan.activeIndex!; i++) {
          activeSegmentStart += segmentPlan.segments[i].durationDays;
        }
        progressStartDay = activeSegmentStart.toDouble();
        progressDays = (dayInActiveSegment ?? 0).toDouble();
      }
      final progressStart =
          start + math.pi * 2 * progressStartDay / ringTotalDays;
      final progressSweep = math.pi * 2 * progressDays / ringTotalDays;
      canvas.drawArc(
        innerRect,
        progressStart,
        progressSweep,
        false,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 16,
      );
      final markerAngle = progressStart + progressSweep;
      final markerCenter =
          center +
          Offset(math.cos(markerAngle), math.sin(markerAngle)) * innerRadius;
      canvas.drawCircle(
        markerCenter,
        10 + 5 * pulse,
        Paint()
          ..color = activeColor.withValues(alpha: .4 - .3 * pulse)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        markerCenter,
        7,
        Paint()
          ..color = markerColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        markerCenter,
        7,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) =>
      oldDelegate.currentDay != currentDay ||
      oldDelegate.cycleLength != cycleLength ||
      oldDelegate.periodLength != periodLength ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.pulse != pulse ||
      oldDelegate.segmentPlan != segmentPlan ||
      oldDelegate.dayInActiveSegment != dayInActiveSegment ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.markerColor != markerColor;
}

class _AnimatedCycleRing extends StatefulWidget {
  const _AnimatedCycleRing({
    required this.cycleLength,
    required this.periodLength,
    required this.currentDay,
    required this.activeColor,
    required this.segmentPlan,
    required this.dayInActiveSegment,
    required this.trackColor,
    required this.markerColor,
    required this.child,
  });

  final int cycleLength;
  final int periodLength;
  final int currentDay;
  final Color activeColor;
  final CycleSegmentPlan segmentPlan;
  final int? dayInActiveSegment;
  final Color trackColor;
  final Color markerColor;
  final Widget child;

  @override
  State<_AnimatedCycleRing> createState() => _AnimatedCycleRingState();
}

class _AnimatedCycleRingState extends State<_AnimatedCycleRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      final isTesting = WidgetsBinding.instance.runtimeType.toString().contains(
        'Test',
      );
      if (!isTesting) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => CustomPaint(
      painter: _CycleRingPainter(
        cycleLength: widget.cycleLength,
        periodLength: widget.periodLength,
        currentDay: widget.currentDay,
        activeColor: widget.activeColor,
        pulse: _controller.value,
        segmentPlan: widget.segmentPlan,
        dayInActiveSegment: widget.dayInActiveSegment,
        trackColor: widget.trackColor,
        markerColor: widget.markerColor,
      ),
      child: child,
    ),
  );
}

enum _FiqhState {
  tahara(
    'Tahara',
    AppColors.tahara,
    'Prayer and fasting are obligatory. You are in a state of purity.',
  ),
  haid('Haid', AppColors.haid, 'Salah is lifted'),
  istihadah(
    'Istihadah',
    AppColors.istihadah,
    'Please log your blood details so we can determine your Fiqh obligation.',
  ),
  needsAdvisory(
    'Needs review',
    Color(0xFF9A6700),
    'This case needs a case-specific review.',
  ),
  // Fiqh Remediation Wave 1 (Section E): bleeding is occurring but no
  // Madhhab is SELECTED (UNSET or UNKNOWN) — the app must ask, never
  // guess. Same tertiary tone as `needsAdvisory`'s spirit ("this needs
  // your input"), but a distinct state so it is never confused with an
  // actual fiqh ruling.
  madhhabUnresolved(
    'Select your Madhhab',
    Color(0xFF6B7280),
    'Select your Madhhab to see your current Fiqh state.',
  );

  const _FiqhState(this.label, this.color, this.message);
  final String label;
  final Color color;
  final String message;
}

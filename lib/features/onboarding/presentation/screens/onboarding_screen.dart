import 'package:flutter/material.dart';

import '../../../../core/auth/auth_controller.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/marital_status_controller.dart';
import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../../../cycle_tracking/domain/entities/bleeding_episode.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import '../../domain/services/madhhab_suggestion_service.dart';

String _tr(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

/// Matches the order of both the English and Arabic choice lists in the
/// Madhhab step below. The 5th choice ("I don't know my Madhhab") is
/// handled separately — see [_MadhhabSubStep] — and has no entry here.
const _madhhabOrder = [
  Madhhab.hanafi,
  Madhhab.maliki,
  Madhhab.shafii,
  Madhhab.hanbali,
];

/// Fiqh Remediation Wave 1 (Section H/I/J): the Madhhab step's own small
/// state machine for the "I don't know my Madhhab" path. [choices] is the
/// normal 5-option grid; the rest are only ever reached by explicitly
/// tapping the 5th option, and every exit from them is an explicit user
/// action — nothing here ever calls `MadhhabController` on its own.
enum _MadhhabSubStep {
  choices,
  unknownExplanation,
  helpAskCountry,
  helpSuggestion,
}

/// Live Onboarding Contradiction Investigation — Location UX contract
/// (Sections 6/9): the Location step's prior behavior called
/// `PrayerLocationController.select`/`useDeviceLocation` and immediately
/// advanced to the next step with zero visible confirmation — detection
/// and persistence both genuinely worked, but nothing on screen ever told
/// the user that, which is indistinguishable from the button silently
/// doing nothing. This explicit state makes every phase visible:
/// [idle] (nothing attempted yet), [detecting] (a real GPS fix is in
/// flight — shown so a slow first fix doesn't look like a dead tap),
/// [selected] (a location — current-location or a tapped city — was just
/// confirmed; shown briefly before advancing), [error] (service
/// disabled/permission denied/other failure — already had a real
/// SnackBar message; this adds a matching on-screen state too).
enum _LocationStatus { idle, detecting, selected, error }

/// Menstrual Data Integrity charter, Commit C: the Last-Period step's own
/// small sub-flow — mirrors the Madhhab step's `_MadhhabSubStep` pattern.
/// [pickStart] shows a real calendar for the most recent bleeding start;
/// [stillHappening] asks the honest active/ended/uncertain question
/// (Section 9) instead of assuming a fixed Haid length starting that day;
/// [pickEnd] only appears after an explicit "No" and asks for a real end
/// date, never a guess.
enum _PeriodSubStep { pickStart, stillHappening, pickEnd }

/// The three honest answers to "is it still happening?" (Section 9) — a
/// 4th, [unanswered], exists only so "no episode should be created yet"
/// has a real representation distinct from any of the other three; it is
/// never itself persisted.
enum _ActiveBleedingAnswer { unanswered, active, ended, uncertain }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.initialStep = 1,
  });
  final VoidCallback onFinished;
  final int initialStep;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Streamlined onboarding flow (8 steps). Only ever shown to an already-
/// authenticated user — main.dart's root router (AUTH-002's contract)
/// gates every path here behind `auth.isAuthenticated == true`, so there
/// is deliberately no login/signup step in this state machine (AUTH-008).
/// There is also deliberately no language-selection step (AUTH-009) —
/// `AppLocaleController` (already set, pre-auth, by the SignInScreen's own
/// language toggle, or its own sensible default) is the single language
/// authority; asking again here would be pure duplication:
/// 1 Splash → 2 Madhhab → 3 Married → 4 Location
/// → 5 Last Period (active/ended/uncertain) → 6 Usual Duration (estimate)
/// → 7 Usual Cycle Length (estimate) → 8 Privacy → 9 Welcome
class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalSteps = 9;

  late int _step = widget.initialStep.clamp(1, _totalSteps);
  // Derived from the app-wide, SharedPreferences-persisted controller — not
  // a local copy — so a step re-selecting language stays in sync even if
  // this State is recreated mid-onboarding (e.g. by the router rebuilding
  // after an out-of-process email-confirmation session lands), instead of
  // silently resetting to English regardless of what was already chosen
  // and persisted (AUTH-007).
  bool get _arabic => AppLocaleController.instance.isArabic;
  String? _madhhab;
  _MadhhabSubStep _madhhabSubStep = _MadhhabSubStep.choices;
  String _madhhabHelpCountry = '';
  MadhhabSuggestion? _madhhabSuggestion;
  bool? _isMarried;
  _LocationStatus _locationStatus = _LocationStatus.idle;
  String? _confirmedLocationLabel;
  String? _locationErrorMessage;
  _PeriodSubStep _periodSubStep = _PeriodSubStep.pickStart;
  DateTime? _periodDate;
  DateTime? _periodEndDate;
  _ActiveBleedingAnswer _activeBleedingAnswer =
      _ActiveBleedingAnswer.unanswered;
  // Section 9: the usual-duration/usual-cycle-length questions are genuine
  // estimates, never forced. The slider needs *some* finite value to
  // render its thumb even before she has touched it, so these numbers are
  // purely a starting visual position — `_haidLengthAnswered`/
  // `_cycleLengthAnswered` track whether she actually interacted, and only
  // an interacted value is ever persisted as her stated estimate. Tapping
  // Continue on an untouched slider is never treated as "her answer was 5"
  // — it is treated exactly like "I'm not sure".
  double _haidLengthValue = 5;
  bool _haidLengthAnswered = false;
  double _cycleLengthValue = 28;
  bool _cycleLengthAnswered = false;
  bool _anonymous = false;
  // Hostile self-review fix (2026-09-17): _completeOnboarding is async and
  // its own Welcome-screen button had no disabled/in-flight state — a
  // rapid double-tap (or a slow first request plus an impatient retry)
  // could fire it twice concurrently. An active-episode duplicate is
  // caught by the DB's one-active-episode constraint, but an ended/
  // uncertain episode has no such uniqueness guard and would happily
  // accept two identical rows. Guards the whole completion path instead.
  bool _completingOnboarding = false;

  @override
  void initState() {
    super.initState();
    // A returning user re-routed through onboarding (e.g. after signing
    // out) already has a saved answer — show it selected instead of blank,
    // otherwise re-selecting anything (or the step just looking unanswered)
    // silently overwrites their real answer via setMarried below.
    _isMarried = MaritalStatusController.instance.isMarried;
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: AppColors.brandBackground,
      body: SafeArea(
        child: Column(
          children: [
            if (_step > 1)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _step / _totalSteps),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: Colors.black.withValues(alpha: .04),
                  color: const Color(0xFFFDA4AF),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  if (_step > 2 && _step < _totalSteps)
                    PositionedDirectional(
                      top: 12,
                      start: 12,
                      child: IconButton(
                        onPressed: () => setState(() => _step--),
                        tooltip: _t('Back', 'رجوع'),
                        icon: Icon(
                          // A chevron is not a directional glyph in
                          // Flutter's icon font — it must be swapped
                          // explicitly, or "back" points visually toward
                          // reading-end in RTL instead of reading-start.
                          _arabic
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0.08, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: ScaleTransition(
                                scale: Tween(
                                  begin: .97,
                                  end: 1.0,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: ConstrainedBox(
                          key: ValueKey(_step),
                          constraints: const BoxConstraints(maxWidth: 390),
                          child: _screen(),
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
    ),
  );

  Widget _screen() => switch (_step) {
    1 => _Splash(onNext: _next),
    // AUTH-008: step 3 used to be an embedded SignInScreen (login/signup)
    // here. It is removed — by the time any user ever reaches
    // OnboardingScreen at all, main.dart's own root router has already
    // required `auth.isAuthenticated == true` (see its own routing
    // contract doc comment); a login step inside onboarding was therefore
    // always redundant for every real path, and both forward navigation
    // (a fresh instance starting at step 1) and Back from Madhhab landed
    // an already-authenticated user on a live Sign In/Sign Up screen —
    // proven, reproducible, the exact defect the owner reported.
    //
    // AUTH-009: the old step 2 (a Language selection screen, identical in
    // purpose to the language toggle already on the pre-auth SignInScreen)
    // is also removed. `AppLocaleController` is the single, canonical
    // language authority throughout the app — it already has a real value
    // (explicitly chosen pre-auth, or its own sensible Arabic default) by
    // the time any authenticated user ever reaches this screen, so asking
    // again here was pure duplication, not a genuine second choice.
    2 => _madhhabStep(),
    3 => _Choices(
      title: _t('Are you married?', 'هل أنتِ متزوجة؟'),
      subtitle: _t(
        'This controls spouse-only pregnancy tools and reports.',
        'يُستخدم لإظهار أدوات الحمل وتقرير الزوج للمتزوجات فقط.',
      ),
      choices: _arabic ? const ['نعم', 'لا'] : const ['Yes', 'No'],
      selected: _isMarried == null
          ? {}
          : {_isMarried! ? (_arabic ? 'نعم' : 'Yes') : (_arabic ? 'لا' : 'No')},
      onToggle: (value) {
        final married = value == 'Yes' || value == 'نعم';
        setState(() => _isMarried = married);
        MaritalStatusController.instance.setMarried(married);
      },
      onNext: _isMarried == null ? null : _next,
    ),
    4 => _Location(
      status: _locationStatus,
      confirmedLabel: _confirmedLocationLabel,
      errorMessage: _locationErrorMessage,
      onSelectCity: _selectCityLocation,
      onUseCurrentLocation: _useDeviceLocation,
      onSkip: _next,
    ),
    5 => _periodStep(),
    6 => _NumberStep(
      title: _t(
        'How long does your period usually last?',
        'كم تستمر مدة حيضكِ عادةً؟',
      ),
      description: _t(
        'Just an estimate — it never replaces what you actually report day '
            'to day.',
        'مجرد تقدير — لا يحل أبداً محل ما تُبلغين عنه فعلياً يوماً بيوم.',
      ),
      value: _haidLengthValue,
      min: 1,
      max: 20,
      onChanged: (v) => setState(() {
        _haidLengthValue = v;
        _haidLengthAnswered = true;
      }),
      onNext: _next,
      onUnsure: _next,
    ),
    7 => _NumberStep(
      title: _t('How long is your usual cycle?', 'كم تستمر دورتكِ عادةً؟'),
      description: _t(
        'From the start of one period to the start of the next. Only an '
            'estimate.',
        'من بداية حيض إلى بداية الحيض التالي. مجرد تقدير.',
      ),
      value: _cycleLengthValue,
      min: 15,
      max: 90,
      onChanged: (v) => setState(() {
        _cycleLengthValue = v;
        _cycleLengthAnswered = true;
      }),
      onNext: _next,
      onUnsure: _next,
    ),
    8 => _Privacy(
      anonymous: _anonymous,
      onAnonymous: (v) => _setAnonymousMode(v),
      onNext: _next,
    ),
    _ => _Welcome(
      isBusy: _completingOnboarding,
      onComplete: _completingOnboarding ? null : () => _completeOnboarding(),
    ),
  };

  /// Section 9: replaces the removed 31-day grid + fixed-Haid-length
  /// fabrication with a real calendar and an honest active/ended/uncertain
  /// question — see [_PeriodSubStep].
  Widget _periodStep() {
    switch (_periodSubStep) {
      case _PeriodSubStep.pickStart:
        return _PeriodPickStart(
          selected: _periodDate,
          onPick: (date) => setState(() => _periodDate = date),
          onContinue: _periodDate == null
              ? null
              : () => setState(
                  () => _periodSubStep = _PeriodSubStep.stillHappening,
                ),
          onUnsure: () {
            setState(() {
              _periodDate = null;
              _activeBleedingAnswer = _ActiveBleedingAnswer.unanswered;
            });
            _next();
          },
        );

      case _PeriodSubStep.stillHappening:
        return _PeriodStillHappening(
          startDate: _periodDate!,
          onYes: () {
            setState(
              () => _activeBleedingAnswer = _ActiveBleedingAnswer.active,
            );
            _next();
          },
          onNo: () => setState(() => _periodSubStep = _PeriodSubStep.pickEnd),
          onNotSure: () {
            setState(
              () => _activeBleedingAnswer = _ActiveBleedingAnswer.uncertain,
            );
            _next();
          },
          onBack: () =>
              setState(() => _periodSubStep = _PeriodSubStep.pickStart),
        );

      case _PeriodSubStep.pickEnd:
        return _PeriodPickEnd(
          startDate: _periodDate!,
          selected: _periodEndDate,
          onPick: (date) => setState(() => _periodEndDate = date),
          onContinue: _periodEndDate == null
              ? null
              : () {
                  setState(
                    () => _activeBleedingAnswer = _ActiveBleedingAnswer.ended,
                  );
                  _next();
                },
          onUnsure: () {
            setState(() {
              _periodEndDate = null;
              _activeBleedingAnswer = _ActiveBleedingAnswer.uncertain;
            });
            _next();
          },
          onBack: () =>
              setState(() => _periodSubStep = _PeriodSubStep.stillHappening),
        );
    }
  }

  String _t(String en, String ar) => _arabic ? ar : en;

  /// Matches the order of [_madhhabOrder] above — the 4 real madhahib
  /// only. See [_madhhabGridChoices] for the grid shown to the user, which
  /// appends the 5th "I don't know" option (Fiqh Remediation Wave 1,
  /// Section G).
  List<String> get _madhhabChoices => _arabic
      ? const ['حنفي', 'مالكي', 'شافعي', 'حنبلي']
      : const ['Hanafi', 'Maliki', "Shafi'i", 'Hanbali'];

  String get _unknownMadhhabLabel =>
      _t('I don\'t know my Madhhab', 'لا أعرف مذهبي');

  List<String> get _madhhabGridChoices => [
    ..._madhhabChoices,
    _unknownMadhhabLabel,
  ];

  /// Section G/H/I/J: the Madhhab step's full sub-flow. [choices] is the
  /// normal 5-option grid (never gates Continue on anything but an
  /// explicit answer); the 5th option leads to an explanation and a
  /// choice between "Help me choose" (a real, confirmation-gated
  /// geographic suggestion, never an auto-declaration) and "I'll decide
  /// later" (persists UNKNOWN, a first-class state — never silently
  /// resolved to any specific madhhab).
  Widget _madhhabStep() {
    switch (_madhhabSubStep) {
      case _MadhhabSubStep.choices:
        return _Choices(
          title: _t('What is your Fiqh Madhhab?', 'ما مذهبكِ الفقهي؟'),
          subtitle: _t(
            'This helps us personalize Haid and prayer guidance.',
            'يساعدنا ذلك في تخصيص أحكام الحيض والصلاة.',
          ),
          choices: _madhhabGridChoices,
          selected: _madhhab == null ? {} : {_madhhab!},
          rules: _arabic
              ? const [
                  'حد أدنى 3 أيام · حد أقصى 10 أيام',
                  'لا يوجد حد أدنى · حد أقصى 15 يوماً',
                  'حد أدنى 24 ساعة · حد أقصى 15 يوماً',
                  'حد أدنى 24 ساعة · حد أقصى 15 يوماً',
                  '',
                ]
              : const [
                  '3-day min · 10-day max',
                  'No minimum · 15-day max',
                  '24-hour min · 15-day max',
                  '24-hour min · 15-day max',
                  '',
                ],
          onToggle: (v) {
            if (v == _unknownMadhhabLabel) {
              // Does NOT persist anything yet — only an explicit action in
              // the explanation step below (Section H/J) ever calls
              // MadhhabController. Tapping the option itself is not a
              // selection.
              setState(
                () => _madhhabSubStep = _MadhhabSubStep.unknownExplanation,
              );
              return;
            }
            setState(() => _madhhab = v);
            MadhhabController.instance.selectMadhhab(
              _madhhabOrder[_madhhabChoices.indexOf(v)],
            );
          },
          onNext: _madhhab == null ? null : _next,
        );

      case _MadhhabSubStep.unknownExplanation:
        return _MadhhabUnknownExplanation(
          onHelpMeChoose: () =>
              setState(() => _madhhabSubStep = _MadhhabSubStep.helpAskCountry),
          onDecideLater: () {
            MadhhabController.instance.selectUnknown();
            setState(() {
              _madhhab = _unknownMadhhabLabel;
              _madhhabSubStep = _MadhhabSubStep.choices;
            });
            _next();
          },
          onBack: () =>
              setState(() => _madhhabSubStep = _MadhhabSubStep.choices),
        );

      case _MadhhabSubStep.helpAskCountry:
        return _MadhhabHelpAskCountry(
          initialValue: _madhhabHelpCountry,
          onSubmit: (country) {
            final suggestion = const MadhhabSuggestionService().suggest(
              explicitCountry: country,
            );
            setState(() {
              _madhhabHelpCountry = country;
              _madhhabSuggestion = suggestion;
              _madhhabSubStep = _MadhhabSubStep.helpSuggestion;
            });
          },
          onBack: () => setState(
            () => _madhhabSubStep = _MadhhabSubStep.unknownExplanation,
          ),
        );

      case _MadhhabSubStep.helpSuggestion:
        return _MadhhabHelpSuggestion(
          suggestion: _madhhabSuggestion ?? MadhhabSuggestion.unresolved,
          // Section I: a suggestion is never treated as authoritative by
          // merely being displayed — SELECTED only happens on this
          // explicit confirmation.
          onConfirm: (madhhab) {
            MadhhabController.instance.selectMadhhab(madhhab);
            final label = _madhhabChoices[_madhhabOrder.indexOf(madhhab)];
            setState(() {
              _madhhab = label;
              _madhhabSubStep = _MadhhabSubStep.choices;
            });
            _next();
          },
          // Section J: no confirmation -> remains UNKNOWN, never SELECTED.
          onNoneOfThese: () {
            MadhhabController.instance.selectUnknown();
            setState(() {
              _madhhab = _unknownMadhhabLabel;
              _madhhabSubStep = _MadhhabSubStep.choices;
            });
            _next();
          },
          onTryAgain: () =>
              setState(() => _madhhabSubStep = _MadhhabSubStep.helpAskCountry),
        );
    }
  }

  void _next() => setState(() => _step = (_step + 1).clamp(1, _totalSteps));

  /// Menstrual Data Integrity charter, Commit C: previously fabricated a
  /// fixed run of daily `cycle_entries` rows (one per day of the Madhhab-
  /// capped "period length" slider, every day but the last stamped
  /// `FlowLevel.medium`) — an entirely invented flow-level observation for
  /// every day between the reported start and an assumed length, none of
  /// which the user ever actually reported. "Never do this again."
  ///
  /// Replaces that with exactly what was actually asked: if a start date
  /// was given, one `bleeding_episodes` row capturing the real reported
  /// start (and, only if she said it had ended, the real reported end) —
  /// no day-by-day flow data is invented, since onboarding never asked for
  /// any. The usual-duration/usual-cycle-length questions are genuine,
  /// skippable estimates and are stored as `cycle_baselines`, never as
  /// observed history. Both writes are best-effort — see
  /// `AuthRepositoryImpl.markOnboardingCompleted` below for the same,
  /// already-established honest tradeoff. This screen is only ever reached
  /// already authenticated (main.dart's root router requires it), so a
  /// real user id is always available whenever there is anything to save.
  Future<void> _completeOnboarding() async {
    if (_completingOnboarding) return;
    setState(() => _completingOnboarding = true);

    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId != null) {
      final periodDate = _periodDate;
      if (periodDate != null &&
          _activeBleedingAnswer != _ActiveBleedingAnswer.unanswered) {
        final ended = _activeBleedingAnswer == _ActiveBleedingAnswer.ended;
        try {
          await BleedingEpisodeRepositoryImpl().createEpisode(
            BleedingEpisode(
              userId: userId,
              status: switch (_activeBleedingAnswer) {
                _ActiveBleedingAnswer.active => EpisodeStatus.active,
                _ActiveBleedingAnswer.ended => EpisodeStatus.ended,
                _ActiveBleedingAnswer.uncertain ||
                _ActiveBleedingAnswer.unanswered => EpisodeStatus.uncertain,
              },
              startDate: periodDate,
              startPrecision: ObservationPrecision.dateOnly,
              startSource: ObservationSource.userReportedHistorical,
              endDate: ended ? _periodEndDate : null,
              endPrecision: ended ? ObservationPrecision.dateOnly : null,
              endSource: ended
                  ? ObservationSource.userReportedHistorical
                  : null,
            ),
          );
        } catch (_) {
          // Best-effort — already reported internally by the repository.
        }
      }

      if (_haidLengthAnswered || _cycleLengthAnswered) {
        try {
          await CycleBaselineRepositoryImpl().saveBaseline(
            CycleBaseline(
              userId: userId,
              usualBleedingDurationDays: _haidLengthAnswered
                  ? _haidLengthValue.round()
                  : null,
              usualCycleLengthDays: _cycleLengthAnswered
                  ? _cycleLengthValue.round()
                  : null,
            ),
          );
        } catch (_) {
          // Best-effort — already reported internally by the repository.
        }
      }
    }

    // AUTH-002: the durable, server-side completion flag — the ONLY
    // signal the root router trusts to decide onboarding is done. Written
    // here, and only here, at the real end of the flow. Best-effort: a
    // network failure must not trap the user on the Welcome screen (she
    // already answered every question), but it does mean she could see
    // onboarding again next launch if this specific write fails — an
    // honest, narrow, already-logged-out-loud tradeoff, not a silent one.
    try {
      await AuthRepositoryImpl().markOnboardingCompleted();
    } catch (_) {
      // Swallowed deliberately — see comment above. The local optimistic
      // update below still lets her proceed to the dashboard this session.
    }
    AuthController.instance.setOnboardingCompletedLocally(true);

    widget.onFinished();
  }

  /// Live Onboarding Contradiction Investigation — Location UX contract
  /// (Section 6): tapping a preset city is a real, explicit selection —
  /// persisted immediately via `PrayerLocationController.select` (already
  /// correct before this fix) — but previously advanced to the next step
  /// with no visible confirmation of *which* city had just been chosen.
  /// Now shows a brief, real "selected" state (Section 9) before
  /// advancing, matching the same contract as device-location detection
  /// below, so no location-setting action in this step is silent.
  Future<void> _selectCityLocation(PrayerLocation preset) async {
    await PrayerLocationController.instance.select(preset);
    if (!mounted) return;
    setState(() {
      _locationStatus = _LocationStatus.selected;
      _confirmedLocationLabel = prayerLocationLabel(preset, isArabic: _arabic);
    });
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) _next();
  }

  /// Live Onboarding Contradiction Investigation — Location UX contract
  /// (Sections 6/9): detection and persistence were already correct
  /// (`PrayerLocationController.useDeviceLocation` genuinely requests
  /// permission, gets a real GPS fix, and persists it) — the defect was
  /// that success advanced to the next step immediately, with **no**
  /// visible confirmation of what was detected, which looks identical to
  /// the button silently doing nothing. This now shows an explicit
  /// `detecting` state while the request is in flight (so a slow first
  /// GPS fix doesn't look like a dead tap either) and a `selected`
  /// confirmation before advancing. Failure paths already had a real
  /// SnackBar message (unchanged) — this adds a matching on-screen state
  /// so failure is visible even if the SnackBar is missed/dismissed.
  Future<void> _useDeviceLocation() async {
    setState(() {
      _locationStatus = _LocationStatus.detecting;
      _locationErrorMessage = null;
    });
    try {
      await PrayerLocationController.instance.useDeviceLocation();
      if (!mounted) return;
      setState(() {
        _locationStatus = _LocationStatus.selected;
        _confirmedLocationLabel = _tr('Current location', 'الموقع الحالي');
      });
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) _next();
    } on LocationServiceDisabled {
      _showLocationError(
        _tr(
          'Turn on location services to use your current location.',
          'فعّلي خدمة الموقع لاستخدام موقعكِ الحالي.',
        ),
      );
    } on LocationPermissionDenied {
      _showLocationError(
        _tr(
          'Location permission denied — pick a city instead.',
          'تم رفض إذن الموقع، يمكنكِ اختيار مدينة بدلاً من ذلك.',
        ),
      );
    } catch (_) {
      _showLocationError(
        _tr(
          'Unable to get your location right now.',
          'تعذر تحديد موقعكِ الآن.',
        ),
      );
    }
  }

  void _showLocationError(String message) {
    if (!mounted) return;
    setState(() {
      _locationStatus = _LocationStatus.error;
      _locationErrorMessage = message;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Best-effort: onboarding doesn't block progress on this write — the
  /// Settings toggle (profile_screen.dart) offers a retry path if it fails.
  Future<void> _setAnonymousMode(bool value) async {
    setState(() => _anonymous = value);
    try {
      final repository = AuthRepositoryImpl();
      final currentUser = await repository.currentUser;
      if (currentUser == null) return;
      await repository.updateProfile(
        displayName: currentUser.displayName ?? '',
        email: currentUser.email,
        anonymousMode: value,
      );
    } catch (_) {
      // Swallowed — see doc comment above.
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.onNext});
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Niswah',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: 48,
          color: const Color(0xFF9F1239),
          fontFamily: AppTypography.serifFamily,
        ),
      ),
      const SizedBox(height: 13),
      Text(
        _tr('YOUR CYCLE. YOUR FAITH. YOUR SPACE.', 'دورتكِ. دينكِ. مساحتكِ.'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: const Color(0xFFFB7185),
          fontSize: 10,
          letterSpacing: 2.1,
          fontWeight: FontWeight.w700,
          fontFamily: AppLocaleController.instance.isArabic
              ? AppTypography.arabicFamily
              : null,
        ),
      ),
      const SizedBox(height: 42),
      FilledButton(
        onPressed: onNext,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE11D48),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
          shape: const StadiumBorder(),
        ),
        child: Text(_tr('Get Started', 'ابدئي')),
      ),
    ],
  );
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.title,
    required this.subtitle,
    required this.choices,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    this.rules,
  });
  final String title, subtitle;
  final List<String> choices;
  final Set<String> selected;
  final List<String>? rules;
  final ValueChanged<String> onToggle;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(title),
      const SizedBox(height: 8),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 28),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: choices.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
        ),
        itemBuilder: (_, i) => _SelectCard(
          title: choices[i],
          subtitle: rules?[i] ?? '',
          selected: selected.contains(choices[i]),
          onTap: () => onToggle(choices[i]),
        ),
      ),
      const SizedBox(height: 28),
      _Continue(onPressed: onNext),
    ],
  );
}

/// Fiqh Remediation Wave 1, Section H: the calm, non-punitive explanation
/// shown after tapping "I don't know my Madhhab" — never pressures a
/// guess, and never implies UNKNOWN is a lesser or incomplete answer.
class _MadhhabUnknownExplanation extends StatelessWidget {
  const _MadhhabUnknownExplanation({
    required this.onHelpMeChoose,
    required this.onDecideLater,
    required this.onBack,
  });
  final VoidCallback onHelpMeChoose;
  final VoidCallback onDecideLater;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('No problem', 'لا بأس')),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: AppColors.shadowColor, blurRadius: 20),
          ],
        ),
        child: Text(
          _tr(
            'We can help you find a likely school based on where you live '
                '— it\'s always just a suggestion, and only becomes your choice '
                'once you confirm it yourself. No Madhhab will ever be assumed '
                'for you without your choosing it.',
            'يمكن لنسوة مساعدتكِ في معرفة المذهب الشائع في منطقتكِ — وهو '
                'دائماً مجرد اقتراح، ولا يصبح خيارك إلا بعد تأكيدكِ له بنفسكِ. '
                'لن يُفترض لكِ أي مذهب دون اختياركِ.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 26),
      _Continue(
        label: _tr('Help me choose', 'ساعديني في الاختيار'),
        onPressed: onHelpMeChoose,
        strong: true,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: onDecideLater,
        child: Text(_tr('I\'ll decide later', 'سأقرر لاحقاً')),
      ),
      TextButton(
        onPressed: onBack,
        child: Text(_tr('Back to choices', 'العودة للخيارات')),
      ),
    ],
  );
}

/// Fiqh Remediation Wave 1, Section I: a lightweight, single-question
/// country input — deliberately not the full Location step (city/GPS),
/// which comes later in onboarding and is unavailable yet at this step.
/// Feeds [MadhhabSuggestionService] directly; nothing here is persisted as
/// a Madhhab choice.
class _MadhhabHelpAskCountry extends StatefulWidget {
  const _MadhhabHelpAskCountry({
    required this.initialValue,
    required this.onSubmit,
    required this.onBack,
  });
  final String initialValue;
  final ValueChanged<String> onSubmit;
  final VoidCallback onBack;
  @override
  State<_MadhhabHelpAskCountry> createState() => _MadhhabHelpAskCountryState();
}

class _MadhhabHelpAskCountryState extends State<_MadhhabHelpAskCountry> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Which country do you live in?', 'في أي دولة تسكنين؟')),
      const SizedBox(height: 8),
      Text(
        _tr(
          'Used only to suggest a likely Madhhab — never to decide it for '
              'you.',
          'تُستخدم فقط لاقتراح مذهب محتمل — ولا تُستخدم أبداً لتحديده نيابةً '
              'عنكِ.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _controller,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: _tr('e.g. Egypt', 'مثال: مصر'),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        // Rebuilds so the Continue button's enabled state below reflects
        // the current text — without this it stays disabled/stale after
        // the first frame, since Continue's onPressed is otherwise only
        // ever evaluated at this State's last build.
        onChanged: (_) => setState(() {}),
        onSubmitted: (value) => widget.onSubmit(value.trim()),
      ),
      const SizedBox(height: 22),
      _Continue(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => widget.onSubmit(_controller.text.trim()),
      ),
      const SizedBox(height: 10),
      TextButton(onPressed: widget.onBack, child: Text(_tr('Back', 'رجوع'))),
    ],
  );
}

/// Fiqh Remediation Wave 1, Sections I/J: shows the geographic suggestion
/// (if any) and requires an explicit confirmation per school before it
/// ever becomes a SELECTED state — never a declaration on its own.
class _MadhhabHelpSuggestion extends StatelessWidget {
  const _MadhhabHelpSuggestion({
    required this.suggestion,
    required this.onConfirm,
    required this.onNoneOfThese,
    required this.onTryAgain,
  });
  final MadhhabSuggestion suggestion;
  final ValueChanged<Madhhab> onConfirm;
  final VoidCallback onNoneOfThese;
  final VoidCallback onTryAgain;

  static String _madhhabName(Madhhab madhhab) => switch (madhhab) {
    Madhhab.hanafi => _tr('Hanafi', 'الحنفي'),
    Madhhab.maliki => _tr('Maliki', 'المالكي'),
    Madhhab.shafii => _tr("Shafi'i", 'الشافعي'),
    Madhhab.hanbali => _tr('Hanbali', 'الحنبلي'),
  };

  @override
  Widget build(BuildContext context) {
    if (!suggestion.isResolved) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Title(
            _tr(
              'We don\'t have a suggestion for that yet',
              'لا يتوفر اقتراح لهذه المنطقة بعد',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _tr(
              'That\'s alright — you can try a different spelling, or '
                  'simply decide later. Nothing has been assumed for you.',
              'لا بأس بذلك — يمكنكِ تجربة تهجئة مختلفة، أو تأجيل القرار '
                  'ببساطة. لم يُفترض لكِ شيء.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _Continue(
            label: _tr('Try again', 'المحاولة مجدداً'),
            onPressed: onTryAgain,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onNoneOfThese,
            child: Text(_tr('I\'ll decide later', 'سأقرر لاحقاً')),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(_tr('A suggestion for you', 'اقتراح لكِ')),
        const SizedBox(height: 8),
        if (suggestion.regionNote != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              suggestion.regionNote!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        // Section J: this is only ever a suggestion until she taps one of
        // these — displaying it never itself changes any stored state.
        for (final madhhab in suggestion.likelyMadhahib)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => onConfirm(madhhab),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _tr(
                    'Yes, ${_madhhabName(madhhab)} is my Madhhab',
                    'نعم، مذهبي هو ${_madhhabName(madhhab)}',
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onNoneOfThese,
          child: Text(
            _tr(
              'None of these — I\'ll decide later',
              'لا شيء من هذا — سأقرر لاحقاً',
            ),
          ),
        ),
      ],
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({
    required this.status,
    required this.confirmedLabel,
    required this.errorMessage,
    required this.onSelectCity,
    required this.onUseCurrentLocation,
    required this.onSkip,
  });
  final _LocationStatus status;
  final String? confirmedLabel;
  final String? errorMessage;
  final ValueChanged<PrayerLocation> onSelectCity;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onSkip;

  bool get _busy =>
      status == _LocationStatus.detecting || status == _LocationStatus.selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Where are you located?', 'أين تسكنين؟')),
      const SizedBox(height: 8),
      Text(
        _tr(
          'Used only to calculate accurate prayer times.',
          'نستخدم موقعكِ فقط لحساب مواقيت الصلاة بدقة.',
        ),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 18),
      // Live Onboarding Contradiction Investigation (Sections 6/9): the
      // one always-visible status region for this step — every location-
      // setting action (device detection or a city tap) reports here, so
      // nothing can look like a silent no-op the way the original
      // immediate-advance behavior did.
      _LocationStatusBanner(status: status, confirmedLabel: confirmedLabel),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _busy ? null : onUseCurrentLocation,
        icon: status == _LocationStatus.detecting
            ? const NiswahLoadingIndicator(
                size: NiswahLoadingSize.small,
                contrast: NiswahLoadingContrast.dark,
              )
            : const Icon(Icons.navigation_rounded),
        label: Text(_tr('Use current location', 'استخدام موقعي الحالي')),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: const Color(0xFFFFF1F2),
          foregroundColor: AppColors.haid,
        ),
      ),
      const SizedBox(height: 22),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          _tr('POPULAR CITIES', 'مدن شائعة'),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 9,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in PrayerLocationController.presets)
            ActionChip(
              label: Text(
                prayerLocationLabel(
                  preset,
                  isArabic: AppLocaleController.instance.isArabic,
                ),
              ),
              onPressed: _busy ? null : () => onSelectCity(preset),
            ),
        ],
      ),
      const SizedBox(height: 22),
      TextButton(
        onPressed: _busy ? null : onSkip,
        child: Text(_tr('Skip for now', 'تخطي الآن')),
      ),
    ],
  );
}

/// Live Onboarding Contradiction Investigation (Sections 6/9): the single
/// always-visible confirmation region — renders nothing for [idle] (no
/// action attempted yet, no reason to occupy space), a real in-flight
/// spinner + "detecting" text for [detecting], a checkmark + the exact
/// resolved label for [selected], and the same error text already shown
/// in the SnackBar for [error] (so the failure is visible even if the
/// SnackBar is missed or already dismissed).
class _LocationStatusBanner extends StatelessWidget {
  const _LocationStatusBanner({
    required this.status,
    required this.confirmedLabel,
  });
  final _LocationStatus status;
  final String? confirmedLabel;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _LocationStatus.idle:
        return const SizedBox.shrink();
      case _LocationStatus.detecting:
        return _banner(
          color: AppColors.textSecondary,
          background: const Color(0xFFF3F4F6),
          icon: const NiswahLoadingIndicator(
            size: NiswahLoadingSize.small,
            contrast: NiswahLoadingContrast.dark,
          ),
          text: _tr('Detecting your location…', 'جارٍ تحديد موقعكِ…'),
        );
      case _LocationStatus.selected:
        return _banner(
          color: AppColors.tahara,
          background: const Color(0xFFECFDF5),
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.tahara,
            size: 20,
          ),
          text: _tr(
            'Location confirmed: ${confirmedLabel ?? ''}',
            'تم تحديد موقعكِ: ${confirmedLabel ?? ''}',
          ),
        );
      case _LocationStatus.error:
        return _banner(
          color: const Color(0xFF9F1239),
          background: const Color(0xFFFFF1F2),
          icon: const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFF9F1239),
            size: 20,
          ),
          text: _tr(
            'Location not detected — try again or pick a city below.',
            'تعذر تحديد الموقع — حاولي مجدداً أو اختاري مدينة أدناه.',
          ),
        );
    }
  }

  Widget _banner({
    required Color color,
    required Color background,
    required Widget icon,
    required String text,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Formats a date the same short way in both locales (e.g. "Sep 10, 2026")
/// — deliberately locale-neutral rather than pulling in `intl` for this
/// single onboarding label.
String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// Section 10: a real, OS-standard calendar (`showDatePicker`) in place of
/// the old fixed 31-day grid — supports month/year navigation, dates
/// further back than 31 days, leap years, RTL, accessibility, and large
/// text scale for free. `lastDate: DateTime.now()` prevents ever selecting
/// a future start date.
class _PeriodPickStart extends StatelessWidget {
  const _PeriodPickStart({
    required this.selected,
    required this.onPick,
    required this.onContinue,
    required this.onUnsure,
  });
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onContinue;
  final VoidCallback onUnsure;

  Future<void> _openPicker(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selected ?? now,
      firstDate: DateTime(now.year - 2, now.month, now.day),
      lastDate: now,
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('When did your last period start?', 'متى بدأ آخر حيض لديكِ؟')),
      const SizedBox(height: 8),
      Text(
        _tr(
          'The real calendar date — however long ago that was.',
          'التاريخ الفعلي — مهما كان قديماً.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => _openPicker(context),
        icon: const Icon(Icons.calendar_month_rounded),
        label: Text(
          selected == null
              ? _tr('Select the date', 'اختاري التاريخ')
              : _formatDate(selected!),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 24),
      _Continue(onPressed: onContinue),
      TextButton(
        onPressed: onUnsure,
        child: Text(_tr('I’m not sure', 'لست متأكدة')),
      ),
    ],
  );
}

/// Section 9: replaces the removed fixed-Haid-length fabrication with the
/// honest question itself — never assumes a currently-bleeding state just
/// because a start date was reported.
class _PeriodStillHappening extends StatelessWidget {
  const _PeriodStillHappening({
    required this.startDate,
    required this.onYes,
    required this.onNo,
    required this.onNotSure,
    required this.onBack,
  });
  final DateTime startDate;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback onNotSure;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Is it still happening?', 'هل ما زال مستمراً؟')),
      const SizedBox(height: 8),
      Text(
        _tr(
          'You told us it started ${_formatDate(startDate)}.',
          'أخبرتِنا أنه بدأ في ${_formatDate(startDate)}.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 28),
      _Continue(
        label: _tr('Yes, still going', 'نعم، ما زال مستمراً'),
        onPressed: onYes,
        strong: true,
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onNo,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(_tr('No, it has stopped', 'لا، لقد توقف')),
        ),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: onNotSure,
        child: Text(_tr('I’m not sure', 'لست متأكدة')),
      ),
      TextButton(onPressed: onBack, child: Text(_tr('Back', 'رجوع'))),
    ],
  );
}

/// Section 9's NO branch: a real end-date calendar, never a guess —
/// `firstDate: startDate` keeps end >= start enforced at the picker level
/// too (matching the DB's own check constraint).
class _PeriodPickEnd extends StatelessWidget {
  const _PeriodPickEnd({
    required this.startDate,
    required this.selected,
    required this.onPick,
    required this.onContinue,
    required this.onUnsure,
    required this.onBack,
  });
  final DateTime startDate;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onContinue;
  final VoidCallback onUnsure;
  final VoidCallback onBack;

  Future<void> _openPicker(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selected ?? now,
      firstDate: startDate,
      lastDate: now,
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('When did it stop?', 'متى توقف؟')),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => _openPicker(context),
        icon: const Icon(Icons.calendar_month_rounded),
        label: Text(
          selected == null
              ? _tr('Select the date', 'اختاري التاريخ')
              : _formatDate(selected!),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 24),
      _Continue(onPressed: onContinue),
      TextButton(
        onPressed: onUnsure,
        child: Text(
          _tr('I’m not sure exactly when', 'لست متأكدة تماماً من الموعد'),
        ),
      ),
      TextButton(onPressed: onBack, child: Text(_tr('Back', 'رجوع'))),
    ],
  );
}

class _NumberStep extends StatelessWidget {
  const _NumberStep({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onNext,
    required this.onUnsure,
  });
  final String title, description;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final VoidCallback onNext;
  // Section 9: this whole question is a non-forced estimate — "I'm not
  // sure" is always available alongside Continue, never hidden behind it.
  final VoidCallback onUnsure;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(title),
      const SizedBox(height: 8),
      Text(
        description,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 45),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${value.round()}',
              style: const TextStyle(
                fontSize: 68,
                color: Color(0xFFFB7185),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: _tr(' days', ' أيام'),
              style: TextStyle(fontSize: 20, color: const Color(0x66BE123C)),
            ),
          ],
        ),
        style: TextStyle(fontFamily: AppTypography.serifFamily),
      ),
      const SizedBox(height: 24),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: (max - min).round(),
        activeColor: const Color(0xFFFB7185),
        inactiveColor: const Color(0xFFFFF1F2),
        onChanged: onChanged,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text('${min.round()}'), Text('${max.round()}')],
      ),
      const SizedBox(height: 36),
      _Continue(onPressed: onNext),
      TextButton(
        onPressed: onUnsure,
        child: Text(_tr('I’m not sure', 'لست متأكدة')),
      ),
    ],
  );
}

class _Privacy extends StatelessWidget {
  const _Privacy({
    required this.anonymous,
    required this.onAnonymous,
    required this.onNext,
  });
  final bool anonymous;
  final ValueChanged<bool> onAnonymous;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Anonymous Mode', 'الوضع المجهول')),
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF881337),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            // A Material ancestor is needed here — without it, this
            // SwitchListTile paints its ink splashes against the colored
            // Container above instead of onto its own layer, which Flutter
            // flags as invisible-ink and refuses to render on interaction.
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: anonymous,
                onChanged: onAnonymous,
                activeTrackColor: const Color(0xFFFDA4AF),
                title: Text(
                  _tr('Hide my identity', 'إخفاء هويتي'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                secondary: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFDA4AF),
                ),
              ),
            ),
            Text(
              _tr(
                'Hide identifying details throughout the community while keeping your health data private.',
                'أخفي بياناتكِ التعريفية في المجتمع مع الحفاظ على خصوصية بياناتكِ الصحية.',
              ),
              style: const TextStyle(
                color: Color(0xAAFFF1F2),
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _Continue(onPressed: onNext),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onComplete, this.isBusy = false});
  final VoidCallback? onComplete;
  // Hostile self-review fix (2026-09-17): completion writes a real
  // episode/baseline — a disabled, in-flight state prevents a rapid
  // double-tap from firing the async completion twice.
  final bool isBusy;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF1F2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: Color(0xFFFB7185),
          size: 38,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        _tr('You’re all set!', 'كل شيء جاهز!'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
          color: const Color(0xFF881337),
          fontFamily: AppTypography.serifFamily,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _tr(
          'Your personalized cycle, Fiqh, wellbeing, and privacy experience is ready.',
          'تجربتكِ المخصصة للدورة والفقه والرفاه والخصوصية جاهزة.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFFFE4E6)),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 16,
          children: [
            _Feature(Icons.auto_awesome_rounded, _tr('Niswah AI', 'نسوة AI')),
            _Feature(Icons.insights_rounded, _tr('Insights', 'الرؤى')),
            _Feature(Icons.menu_book_rounded, _tr('Journeys', 'الرحلات')),
            _Feature(Icons.shield_outlined, _tr('Privacy', 'الخصوصية')),
          ],
        ),
      ),
      const SizedBox(height: 28),
      isBusy
          ? const SizedBox(
              height: 54,
              child: Center(
                child: NiswahLoadingIndicator(
                  size: NiswahLoadingSize.small,
                  contrast: NiswahLoadingContrast.dark,
                ),
              ),
            )
          : _Continue(
              label: _tr('Get Started', 'ابدئي'),
              onPressed: onComplete,
              strong: true,
            ),
    ],
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.displayMedium?.copyWith(
      fontFamily: AppTypography.serifFamily,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF4B3430),
    ),
  );
}

class _Continue extends StatelessWidget {
  const _Continue({
    required this.onPressed,
    this.label = 'Continue',
    this.strong = false,
  });
  final VoidCallback? onPressed;
  final String label;
  final bool strong;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      backgroundColor: strong
          ? const Color(0xFFE11D48)
          : const Color(0xFFFB7185),
      disabledBackgroundColor: const Color(0xFFF3F4F6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    child: Text(
      label == 'Continue' ? _tr('Continue', 'متابعة') : label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  // Fiqh Remediation Wave 1 — Pre-E4 Verification (Section 2): this tile's
  // selected state was previously conveyed only visually (color/border/
  // checkmark) — a real accessibility gap, matching the pattern already
  // fixed for FloatingNavBar's tabs (floating_nav_bar.dart). `excludeSemantics:
  // true` stops the child Text's own label from merging in and doubling the
  // announcement (e.g. "Hanafi, Hanafi, button").
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: subtitle.isEmpty ? title : '$title, $subtitle',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF1F2) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFDA4AF) : AppColors.shadowColor,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // FittedBox(scaleDown) matches the same fixed-dimension/large-
            // text-scale treatment already applied to the dashboard (AU-006)
            // — this grid cell has a fixed aspect ratio, so title+subtitle
            // text would otherwise overflow it at large OS text-scale
            // settings instead of shrinking to fit.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF881337)
                          : AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 8,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const PositionedDirectional(
                top: 0,
                end: 0,
                child: Icon(
                  Icons.check_rounded,
                  color: Color(0xFFFB7185),
                  size: 17,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 125,
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFFB7185), size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF881337),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

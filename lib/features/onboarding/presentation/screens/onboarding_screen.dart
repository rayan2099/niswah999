import 'dart:async';

import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

import '../../../../core/auth/auth_controller.dart';
import '../../../../core/data/app_features.dart';
import '../../../../core/data/iso_countries.dart';
import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/marital_status_controller.dart';
import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../cycle_tracking/data/local/pending_bleeding_operation_store.dart';
import '../../../cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
import '../../../cycle_tracking/domain/entities/bleeding_episode.dart';
import '../../../madhhab/presentation/widgets/madhhab_selector.dart';
import '../../../madhhab_resolution/presentation/widgets/madhhab_resolution_flow.dart';

String _tr(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

/// Manual QA fix (2026-10-11), Part 2: classifies a
/// `record_onboarding_menstrual_history` RPC failure as deterministic —
/// retrying sends the exact same request and gets the exact same
/// rejection every time — versus merely transient (network, timeout,
/// anything else), which a real retry can plausibly resolve. Top-level
/// and pure so it's directly unit-testable without a real Supabase
/// client/session (widget tests never reach this call at all, since they
/// have no authenticated session to trigger it with).
///
/// Today the one known deterministic case is `bleeding_episodes`'
/// `bleeding_episodes_one_open_per_user` unique-violation (Postgres
/// `23505`) — she already has a real, previously-saved open episode, so a
/// new "last period started on X" answer can never be inserted as a
/// second one. Confirmed as the actual cause of a real manual-QA failure
/// on staging (2026-10-11): the test account had an open episode from an
/// earlier successful onboarding completion during the same testing
/// session, and a subsequent re-run hit this exact constraint.
bool isNonRetryableDuplicateEpisodeError(Object error) =>
    error is PostgrestException &&
    error.code == '23505' &&
    error.message.contains('bleeding_episodes_one_open_per_user');

/// Display-only (never used for parsing/input): renders a plain int using
/// Eastern Arabic-Indic numerals, matching the "الخطوة ٢ من ٤" style the
/// onboarding redesign's step indicator uses in Arabic.
String _arabicIndicDigits(int value) {
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return value.toString().split('').map((d) {
    final i = int.tryParse(d);
    return i == null ? d : eastern[i];
  }).join();
}

/// PR #4 hardening, Blocker 6: no medically-motivated bound on how long
/// ago a real bleeding start can be reported — a technical bound is still
/// required by `showDatePicker`'s own API, so this is deliberately
/// generous rather than the previous 2-year window, which contradicted
/// this same step's own "however long ago that was" copy.
DateTime _earliestReportableDate(DateTime now) =>
    DateTime(now.year - 100, now.month, now.day);

/// Manual QA fix (2026-10-11), Part 2: the stock `showDatePicker` inherits
/// the app's rose-seeded `ColorScheme.fromSeed` (app_theme.dart), and
/// Material 3 tints every elevated surface with `surfaceTintColor` derived
/// from that same seed — the actual cause of the calendar looking "heavy
/// pink/beige" rather than a clean, premium white. `surfaceTintColor:
/// Colors.transparent` removes that tint; the rest of this theme override
/// gives the dialog its own calm, high-contrast palette (white surface,
/// the onboarding accent for the selected day/buttons) without touching
/// the app-wide theme or any functional date-selection behavior.
Future<DateTime?> _showOnboardingDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: firstDate,
  lastDate: lastDate,
  builder: (context, child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.onboardingAccent,
          onPrimary: Colors.white,
          surface: AppColors.onboardingSurface,
          onSurface: AppColors.onboardingPrimaryText,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: AppColors.onboardingSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          headerBackgroundColor: AppColors.onboardingSurface,
          headerForegroundColor: AppColors.onboardingPrimaryText,
          weekdayStyle: const TextStyle(
            color: AppColors.onboardingSecondaryText,
            fontWeight: FontWeight.w600,
          ),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.onboardingPrimaryText,
          ),
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.onboardingAccent
                : null,
          ),
          todayForegroundColor: const WidgetStatePropertyAll(
            AppColors.onboardingAccent,
          ),
          todayBorder: const BorderSide(color: AppColors.onboardingAccent),
          yearForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.onboardingPrimaryText,
          ),
          yearBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.onboardingAccent
                : null,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onboardingAccent,
          ),
        ),
      ),
      child: child!,
    );
  },
);

/// Fiqh Remediation Wave 1 (Section H/I/J): the Madhhab step's own small
/// state machine for the "I don't know my Madhhab" path. [choices] is the
/// normal 5-option grid; the rest are only ever reached by explicitly
/// tapping the 5th option, and every exit from them is an explicit user
/// action — nothing here ever calls `MadhhabController` on its own.
enum _MadhhabSubStep {
  choices,
  unknownExplanation,
  // Manual QA wave (2026-10-12): the entire country → region → suggestion
  // → manual-select sub-flow collapsed into one case rendering the
  // shared `MadhhabResolutionFlow` widget — that widget now owns its own
  // internal sub-step state (previously four separate enum values here:
  // helpAskCountry/helpAskRegion/helpSuggestion/helpManualSelect), the
  // same component the in-app Madhhab change flow uses.
  helpFlow,
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
///
/// Onboarding/server hardening (proposed, finding #4): [endedEndUnknown]
/// is "No, it has stopped" followed by "I'm not sure exactly when". It
/// used to be folded into [uncertain], which saved an OPEN episode ("may
/// still be bleeding") — the opposite of what she said. The episode model
/// has no "ended, end date unknown" state (the contract requires an
/// `end_date` for `ended`), so this answer creates no episode at all; only
/// her baseline estimates, if any, are saved.
enum _ActiveBleedingAnswer {
  unanswered,
  active,
  ended,
  uncertain,
  endedEndUnknown,
}

/// Onboarding/server hardening (proposed, findings #2/#3): whether two
/// queued onboarding submissions carry the same answers. Provenance
/// (`startSource`/`endSource`, derived from "today") and the UTC offset are
/// ignored — the same answer given on a later day is still the same answer.
@visibleForTesting
bool sameOnboardingAnswers(Map<String, dynamic> a, Map<String, dynamic> b) {
  Map<String, dynamic>? answers(Object? raw) {
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw)
      ..remove('startSource')
      ..remove('endSource');
  }

  const equality = DeepCollectionEquality();
  return equality.equals(answers(a['episode']), answers(b['episode'])) &&
      equality.equals(answers(a['baseline']), answers(b['baseline']));
}

/// Onboarding/server hardening (proposed, finding #14): a usual bleeding
/// duration must be shorter than the usual cycle length (the time from one
/// start to the next includes the bleeding itself). Mirrors the
/// `cycle_baselines_duration_below_cycle_check` constraint. Returns null
/// when the pair is plausible or either value is missing.
@visibleForTesting
String? baselinePairError({
  required int? durationDays,
  required int? cycleLengthDays,
  required bool arabic,
}) {
  if (durationDays == null || cycleLengthDays == null) return null;
  if (durationDays < cycleLengthDays) return null;
  return arabic
      ? 'مدة نزول الدم ($durationDays أيام) يجب أن تكون أقل من طول الدورة '
            '($cycleLengthDays يومًا).'
      : 'Bleeding that lasts $durationDays days has to be shorter than a '
            '$cycleLengthDays-day cycle.';
}

/// Onboarding redesign, Part 3: the optional "improve predictions?" sub-flow
/// living entirely at step 6. [ask] is the gate itself; [duration]/
/// [cycleLength] are only ever reached after an explicit "yes" and ask the
/// two Part-2-clarified questions one at a time, each independently
/// skippable via its own "I'm not sure".
enum _PredictionsSubStep { ask, duration, cycleLength }

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

/// Streamlined onboarding flow. Only ever shown to an already-
/// authenticated user — main.dart's root router (AUTH-002's contract)
/// gates every path here behind `auth.isAuthenticated == true`, so there
/// is deliberately no login/signup step in this state machine (AUTH-008).
/// There is also deliberately no language-selection step (AUTH-009) —
/// `AppLocaleController` (already set, pre-auth, by the SignInScreen's own
/// language toggle, or its own sensible default) is the single language
/// authority; asking again here would be pure duplication:
/// 1 Splash → 2 Madhhab → 3 Married → 4 Location
/// → 5 Last Period (active/ended/uncertain)
/// → 6 Predictions (optional gate; only if accepted: Usual Duration then
///   Usual Cycle Length, both still individually skippable) → 7 Privacy
/// → 8 Welcome
///
/// Onboarding redesign, Part 3/9 (progressive onboarding): step 6 used to
/// be two unconditional estimate questions (Usual Duration, Usual Cycle
/// Length). They are now gated behind one explicit "want to improve your
/// predictions?" choice — skipping it is a first-class, fully-supported
/// path (basic tracking continues to work; only predictions are limited
/// until there's enough real observed data). Because all three screens
/// (the gate + the two estimates) share step index 6 via
/// [_PredictionsSubStep], never advancing [_step] itself, the deferred
/// questions never inflate the step count shown to her (Part 8) — the
/// progress indicator is driven by [_essentialStepCount], not by how many
/// literal screens a given path happens to pass through.
class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalSteps = 8;
  // Splash (1) and Welcome (_totalSteps) are not "questions" — the visible
  // step label only counts 2..(_totalSteps - 1).
  static const int _essentialStepCount = _totalSteps - 2;

  late int _step = widget.initialStep.clamp(1, _totalSteps);
  // Derived from the app-wide, SharedPreferences-persisted controller — not
  // a local copy — so a step re-selecting language stays in sync even if
  // this State is recreated mid-onboarding (e.g. by the router rebuilding
  // after an out-of-process email-confirmation session lands), instead of
  // silently resetting to English regardless of what was already chosen
  // and persisted (AUTH-007).
  bool get _arabic => AppLocaleController.instance.isArabic;
  _MadhhabSubStep _madhhabSubStep = _MadhhabSubStep.choices;
  // Onboarding fixes wave (2026-10-11), Part 1: upbringing context (where
  // she was raised), never current residence — a clearer signal for a
  // Madhhab suggestion than where she happens to live today. Transient
  // onboarding-flow input to MadhhabSuggestionService, not yet persisted
  // as its own backend field: the durable result of this screen is the
  // Madhhab selection itself (already persisted via MadhhabController),
  // not the upbringing-country signal that led to it.
  IsoCountry? _upbringingCountry;
  bool? _isMarried;
  _LocationStatus _locationStatus = _LocationStatus.idle;
  String? _confirmedLocationLabel;
  String? _locationErrorMessage;
  _PeriodSubStep _periodSubStep = _PeriodSubStep.pickStart;
  DateTime? _periodDate;
  DateTime? _periodEndDate;
  _ActiveBleedingAnswer _activeBleedingAnswer =
      _ActiveBleedingAnswer.unanswered;
  _PredictionsSubStep _predictionsSubStep = _PredictionsSubStep.ask;
  // Section 9: the usual-duration/usual-cycle-length questions are genuine
  // estimates, never forced. Null means genuinely unanswered — never a
  // silent default (PR #4 hardening, Blocker 6: previously a Slider
  // needed *some* value to render its thumb even before she touched it,
  // which meant a hard min/max that could reject a real but unusual
  // answer; a plain numeric field has no such problem and simply starts
  // empty).
  int? _haidLengthValue;
  int? _cycleLengthValue;
  bool _anonymous = false;
  // Hostile self-review fix (2026-09-17): _completeOnboarding is async and
  // its own Welcome-screen button had no disabled/in-flight state — a
  // rapid double-tap (or a slow first request plus an impatient retry)
  // could fire it twice concurrently. An active-episode duplicate is
  // caught by the DB's one-active-episode constraint, but an ended/
  // uncertain episode has no such uniqueness guard and would happily
  // accept two identical rows. Guards the whole completion path instead.
  bool _completingOnboarding = false;
  // PR #4 hardening, Blocker 3; manual QA fix round 3 (2026-10-11), Part
  // 3: a real save failure for menstrual data she explicitly supplied
  // must never be silently swallowed while onboarding still completes as
  // if it were recorded. Non-null blocks completion and surfaces an
  // honest, specific error — retry, or go back and review the answer
  // actually in conflict; deliberately never a "continue without saving
  // this" bypass for required data.
  String? _onboardingSaveError;
  // Manual QA wave (2026-10-12): non-null only when
  // record_onboarding_menstrual_history reports a genuine
  // episode_conflict — she already has an open episode with a
  // *different* start date than what she just entered. Never raised as
  // an exception by the RPC (a real, anticipatable product situation,
  // not a failure), so handled as its own state rather than folded into
  // [_onboardingSaveError]'s generic retry/review flow: the baseline may
  // already be saved, and the only two honest resolutions are deferring
  // to the existing episode (it is never silently closed/overwritten to
  // force this through) or going back to change what she entered.
  DateTime? _onboardingConflictingEpisodeStartDate;
  // PR #4 completion wave, Fix A: generated once for this screen instance
  // and reused unchanged on every retry of _completeOnboarding — this is
  // exactly what lets record_onboarding_menstrual_history recognize a
  // retry as the *same* logical action (response lost, app killed
  // mid-request, a genuine double-tap) instead of a new submission.
  //
  // Hardening 1: a widget-state field alone only survives a retry *while
  // this screen instance stays alive* — it does not survive the process
  // itself being killed after the RPC already reached and committed on
  // the server but before the response came back. A fresh app launch
  // would otherwise build a brand-new OnboardingScreen with a brand-new
  // id, indistinguishable from a genuinely new submission. So this is no
  // longer unconditionally fresh: initState checks
  // PendingBleedingOperationStore for an onboardingHistory operation left
  // over from exactly that failure and reuses its id instead, via
  // _resolveOnboardingOperationId below.
  String _onboardingOperationId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    // A returning user re-routed through onboarding (e.g. after signing
    // out) already has a saved answer — show it selected instead of blank,
    // otherwise re-selecting anything (or the step just looking unanswered)
    // silently overwrites their real answer via setMarried below.
    // Onboarding/server hardening (proposed, finding #13): only a real
    // saved answer is pre-selected; a first-time user starts unanswered.
    _isMarried = MaritalStatusController.instance.answer;
    unawaited(_resolveOnboardingOperationId());
  }

  /// Hardening 1: if the previous attempt's request reached the server (or
  /// may have) but this screen never lived to see the response — the
  /// process was killed in between — a pending onboardingHistory operation
  /// is still sitting in [PendingBleedingOperationStore]. Reusing its id
  /// means a later _completeOnboarding call here can never create a
  /// *second* logical submission: record_onboarding_menstrual_history's own
  /// idempotency check recognizes the same client_operation_id and returns
  /// the original episode_id/baseline_id instead of inserting again,
  /// regardless of whatever she re-answers on this fresh instance of the
  /// screen. (The independent, UI-free path — reconciling a pending
  /// operation without her ever reopening onboarding at all — is
  /// [BleedingEpisodeRepositoryImpl.reconcilePendingOperations], wired into
  /// app start/resume in main.dart.)
  Future<void> _resolveOnboardingOperationId() async {
    final pending = await PendingBleedingOperationStore.getPendingByType(
      PendingBleedingOperationType.onboardingHistory,
    );
    if (pending == null || !mounted) return;
    setState(() {
      _onboardingOperationId = pending.operationId;
    });
  }

  /// Onboarding redesign, Part 8: the predictions gate + its two optional
  /// estimate screens all live at `_step == 6` via [_predictionsSubStep],
  /// so stepping "back" out of either estimate screen moves one sub-step
  /// back (cycle length -> duration -> the gate) instead of leaving step 6
  /// entirely — consistent with every other sub-flow in this file, where
  /// the global chevron only ever moves within the current step's own
  /// sub-flow before it moves to the previous top-level step.
  void _goBack() {
    if (_step == 6) {
      switch (_predictionsSubStep) {
        case _PredictionsSubStep.cycleLength:
          setState(() => _predictionsSubStep = _PredictionsSubStep.duration);
          return;
        case _PredictionsSubStep.duration:
          setState(() => _predictionsSubStep = _PredictionsSubStep.ask);
          return;
        case _PredictionsSubStep.ask:
          break;
      }
    }
    setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: AppColors.onboardingBackground,
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
                  backgroundColor: AppColors.onboardingBorder,
                  color: AppColors.onboardingAccent,
                ),
              ),
            // Onboarding redesign, Part 8: "Step N of Y" counts only the
            // essential top-level steps — the deferred predictions estimate
            // screens share step 6's own index (see _goBack above), so they
            // never advance this number.
            if (_step >= 2 && _step < _totalSteps)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _tr(
                    'Step ${_step - 1} of $_essentialStepCount',
                    'الخطوة ${_arabicIndicDigits(_step - 1)} من '
                        '${_arabicIndicDigits(_essentialStepCount)}',
                  ),
                  style: const TextStyle(
                    color: AppColors.onboardingSecondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
                        onPressed: _goBack,
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
    6 => _predictionsStep(),
    7 => _Privacy(
      anonymous: _anonymous,
      onAnonymous: (v) => _setAnonymousMode(v),
      onNext: _next,
    ),
    _ => _Welcome(
      isBusy: _completingOnboarding,
      saveError: _onboardingSaveError,
      conflictingEpisodeStartDate: _onboardingConflictingEpisodeStartDate,
      onComplete: _completingOnboarding ? null : () => _completeOnboarding(),
      onReviewAnswers: _completingOnboarding
          ? null
          : _reviewAnswersAfterSaveFailure,
      onKeepExistingEpisode: _completingOnboarding
          ? null
          : () => _keepExistingEpisodeAndContinue(),
    ),
  };

  /// Onboarding redesign, Part 3: the optional predictions gate + its two
  /// clarified estimate questions (Part 2's corrected wording). Declining
  /// the gate — or "I'm not sure" on either estimate — advances to Privacy
  /// exactly as before; nothing here is ever forced, and neither estimate
  /// is asked unless she explicitly opted in.
  Widget _predictionsStep() {
    switch (_predictionsSubStep) {
      case _PredictionsSubStep.ask:
        return _PredictionsGate(
          onAccept: () => setState(
            () => _predictionsSubStep = _PredictionsSubStep.duration,
          ),
          // Onboarding/server hardening (proposed, finding #12): skipping
          // means "don't use estimates" — anything she scrolled to before
          // coming back here is discarded, not silently saved.
          onSkip: () {
            setState(() {
              _haidLengthValue = null;
              _cycleLengthValue = null;
            });
            _next();
          },
        );
      case _PredictionsSubStep.duration:
        return _NumberWheelStep(
          // Bug fix (confirmed manual QA, 2026-10-11): duration and cycle
          // length are both `_NumberWheelStep` at the same tree position
          // (step 6 never changes while moving between predictions
          // sub-steps, so the ancestor `ConstrainedBox(key: ValueKey(_step))`
          // doesn't remount either). With no Key of their own, Flutter's
          // element reconciliation treated the two screens as "the same
          // widget updated" and reused the single `_NumberWheelStepState`
          // — including its displayed/touched value — across both
          // questions, so whatever she chose for duration visibly carried
          // into the cycle-length wheel. A distinct key per question forces
          // a fresh State (seeded fresh from that question's own
          // initialValue) on every sub-step transition.
          key: const ValueKey('predictions_duration'),
          // Part 2: distinct from cycle length — this is the count of
          // bleeding days themselves, first day to last day of one episode.
          title: _tr(
            'How many days does your bleeding usually last?',
            'كم يومًا يستمر نزول دم الحيض لديكِ عادةً؟',
          ),
          description: _tr(
            'From the first day bleeding starts to the last day. For '
                'example: 5 days.',
            'من أول يوم يبدأ فيه نزول الدم إلى آخر يوم. مثلًا: ٥ أيام.',
          ),
          initialValue: _haidLengthValue,
          maxValue: 20,
          validate: (v) => baselinePairError(
            durationDays: v,
            cycleLengthDays: _cycleLengthValue,
            arabic: _arabic,
          ),
          onChanged: (v) => setState(() => _haidLengthValue = v),
          onNext: () => setState(
            () => _predictionsSubStep = _PredictionsSubStep.cycleLength,
          ),
          onUnsure: () {
            setState(() {
              _haidLengthValue = null;
              _predictionsSubStep = _PredictionsSubStep.cycleLength;
            });
          },
        );
      case _PredictionsSubStep.cycleLength:
        return _NumberWheelStep(
          key: const ValueKey('predictions_cycle_length'),
          // Part 2: distinct from bleeding duration — this is the gap
          // between two bleeding starts, not the bleeding itself.
          title: _tr(
            'How many days between the start of one period and the start '
                'of the next?',
            'كم يومًا بين بداية حيضكِ وبداية الحيض التالي؟',
          ),
          description: _tr(
            'Counted from the first day of bleeding to the first day it '
                'starts again. For example: 28 days.',
            'نحسب من أول يوم لنزول الدم إلى أول يوم لنزوله مرة أخرى. مثلًا: '
                '٢٨ يومًا.',
          ),
          initialValue: _cycleLengthValue,
          maxValue: 90,
          validate: (v) => baselinePairError(
            durationDays: _haidLengthValue,
            cycleLengthDays: v,
            arabic: _arabic,
          ),
          onChanged: (v) => setState(() => _cycleLengthValue = v),
          onNext: _next,
          onUnsure: () {
            setState(() => _cycleLengthValue = null);
            _next();
          },
        );
    }
  }

  /// Section 9: replaces the removed 31-day grid + fixed-Haid-length
  /// fabrication with a real calendar and an honest active/ended/uncertain
  /// question — see [_PeriodSubStep].
  Widget _periodStep() {
    switch (_periodSubStep) {
      case _PeriodSubStep.pickStart:
        return _PeriodPickStart(
          selected: _periodDate,
          // Onboarding/server hardening (proposed, finding #11): a new start
          // date invalidates the end date and the "still happening?" answer
          // given for the old one — otherwise a stale end before the new
          // start stays selected and the whole save is rejected.
          onPick: (date) => setState(() {
            if (_periodDate != date) {
              _periodEndDate = null;
              _activeBleedingAnswer = _ActiveBleedingAnswer.unanswered;
            }
            _periodDate = date;
          }),
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
              _activeBleedingAnswer = _ActiveBleedingAnswer.endedEndUnknown;
            });
            _next();
          },
          onBack: () =>
              setState(() => _periodSubStep = _PeriodSubStep.stillHappening),
        );
    }
  }

  String _t(String en, String ar) => _arabic ? ar : en;

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
        // Requirement 1/5: the shared MadhhabSelector, also used by
        // Settings and the resolution screen — identical names,
        // descriptions, and "I don't know" option everywhere, replacing
        // this step's own previously hand-typed choice list and rule
        // text (see the deleted _madhhabChoices/_madhhabGridChoices).
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Title(_t('What is your Fiqh Madhhab?', 'ما مذهبكِ الفقهي؟')),
            const SizedBox(height: 8),
            Text(
              _t(
                'This helps us personalize Haid and prayer guidance.',
                'يساعدنا ذلك في تخصيص أحكام الحيض والصلاة.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 28),
            MadhhabSelector(
              state: MadhhabController.instance.state,
              selected: MadhhabController.instance.selectedOrNull,
              onSelectMadhhab: (m) async {
                // No confirmation dialog here (unlike Settings/the
                // resolution screen): onboarding's Madhhab step runs
                // before any bleeding history can possibly exist (Last
                // Period is a later step), so Requirement 2's "may
                // affect previously recorded data" warning can never
                // honestly apply yet — showing it here would be a false
                // alarm, not a safeguard.
                await MadhhabController.instance.selectMadhhab(
                  m,
                  source: 'onboarding',
                );
                if (mounted) setState(() {});
              },
              onSelectUnknown: () {
                // Does NOT persist anything yet — only an explicit
                // action in the explanation step below (Section H/J)
                // ever calls MadhhabController. Tapping the option
                // itself is not a selection.
                setState(
                  () => _madhhabSubStep = _MadhhabSubStep.unknownExplanation,
                );
              },
            ),
            const SizedBox(height: 28),
            _Continue(
              // Manual QA fix (2026-10-11), Part 1A root cause: this used
              // to gate on `MadhhabController.isSelected`, which is `true`
              // only for `MadhhabSelectionState.selected` — deliberately
              // narrow everywhere else it's used (profile_screen.dart,
              // cycle_log_form_sheet.dart need a real madhhab to apply
              // Fiqh rules with, so "unknown" must stay "not selected"
              // there). But here it meant a returning visitor who'd
              // already chosen "لا أعرف" and navigated back to this grid
              // (her prior choice correctly shown active on the tile) saw
              // Continue stuck disabled, as if her answer weren't
              // complete. "لا أعرف" is a complete, valid answer for
              // onboarding purposes — gate on the broader state instead.
              onPressed:
                  MadhhabController.instance.state !=
                      MadhhabSelectionState.unset
                  ? _next
                  : null,
            ),
          ],
        );

      case _MadhhabSubStep.unknownExplanation:
        return _MadhhabUnknownExplanation(
          onHelpMeChoose: () =>
              setState(() => _madhhabSubStep = _MadhhabSubStep.helpFlow),
          onDecideLater: () async {
            await MadhhabController.instance.selectUnknown(
              source: 'onboarding',
            );
            setState(() => _madhhabSubStep = _MadhhabSubStep.choices);
            _next();
          },
          onBack: () =>
              setState(() => _madhhabSubStep = _MadhhabSubStep.choices),
        );

      case _MadhhabSubStep.helpFlow:
        // Manual QA wave (2026-10-12): the country question, picker,
        // region refinement, suggestion, and manual-select steps are now
        // the one shared `MadhhabResolutionFlow` — the exact same
        // component the in-app Madhhab change flow (Profile/Settings,
        // Log-my-Haidh) uses, not a separate copy. Only how the result
        // gets persisted stays onboarding-specific: direct
        // `MadhhabController` calls, since onboarding's Madhhab step runs
        // before any bleeding history can exist, so the "replacing an
        // existing selection" warning dialog can never honestly apply
        // here (unchanged reasoning from the original `.choices` case
        // above).
        return MadhhabResolutionFlow(
          initialCountry: _upbringingCountry,
          onCountryChanged: (country) => _upbringingCountry = country,
          onSelectMadhhab: (madhhab, {required viaSuggestion}) async {
            _upbringingCountry = null;
            await MadhhabController.instance.selectMadhhab(
              madhhab,
              source: viaSuggestion
                  ? 'onboarding_suggested_confirmed'
                  : 'onboarding',
            );
            setState(() => _madhhabSubStep = _MadhhabSubStep.choices);
            _next();
          },
          onSelectUnknown: () async {
            _upbringingCountry = null;
            await MadhhabController.instance.selectUnknown(
              source: 'onboarding',
            );
            setState(() => _madhhabSubStep = _MadhhabSubStep.choices);
            _next();
          },
          onExitFirstStep: () => setState(
            () => _madhhabSubStep = _MadhhabSubStep.unknownExplanation,
          ),
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
  /// PR #4 hardening, Blocker 3: the previous version caught an
  /// episode/baseline save failure and silently completed onboarding
  /// anyway — a user who explicitly reported real menstrual history could
  /// finish believing it was recorded when Niswah had actually lost it.
  /// A genuine failure here now blocks completion outright and surfaces
  /// an honest, actionable error (see `_Welcome`'s error state) with a
  /// real retry — `_completingOnboarding`'s guard and the stable
  /// `_periodDate`/`_haidLengthValue`/`_cycleLengthValue` state make a
  /// retry safe to just call this method again unchanged. Only
  /// `markOnboardingCompleted` below remains best-effort, matching its
  /// own long-standing rationale (a flag write failing must not trap her
  /// on the Welcome screen after everything else genuinely saved).
  Future<void> _completeOnboarding() async {
    if (_completingOnboarding) return;
    setState(() {
      _completingOnboarding = true;
      _onboardingSaveError = null;
      _onboardingConflictingEpisodeStartDate = null;
    });

    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId != null) {
      final periodDate = _periodDate;
      // Finding #4: "stopped, not sure when" is not an episode we can
      // record truthfully (see [_ActiveBleedingAnswer.endedEndUnknown]).
      final hasEpisode =
          periodDate != null &&
          (_activeBleedingAnswer == _ActiveBleedingAnswer.active ||
              _activeBleedingAnswer == _ActiveBleedingAnswer.ended ||
              _activeBleedingAnswer == _ActiveBleedingAnswer.uncertain);
      final hasBaseline = _haidLengthValue != null || _cycleLengthValue != null;

      if (hasEpisode || hasBaseline) {
        final utcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

        BleedingEpisode? episode;
        if (hasEpisode) {
          final ended = _activeBleedingAnswer == _ActiveBleedingAnswer.ended;
          // PR #4 hardening, Blocker 4: provenance follows which date was
          // actually reported, not which screen reported it — a real
          // "today" answer through onboarding is exactly as live as one
          // through the dashboard's Start Bleeding sheet.
          final localToday = BleedingEpisodeRepositoryImpl.localToday(
            utcOffsetMinutes,
          );
          final startSource = ObservationSource.classify(
            reportedDate: periodDate,
            localToday: localToday,
          );
          final periodEndDate = _periodEndDate;
          final endSource = (ended && periodEndDate != null)
              ? ObservationSource.classify(
                  reportedDate: periodEndDate,
                  localToday: localToday,
                )
              : null;

          episode = BleedingEpisode(
            userId: userId,
            lifecycleStatus: ended
                ? LifecycleStatus.ended
                : LifecycleStatus.open,
            continuationCertainty: ended
                ? null
                : switch (_activeBleedingAnswer) {
                    _ActiveBleedingAnswer.active =>
                      ContinuationCertainty.confirmed,
                    _ActiveBleedingAnswer.uncertain =>
                      ContinuationCertainty.uncertain,
                    _ActiveBleedingAnswer.ended ||
                    _ActiveBleedingAnswer.unanswered ||
                    _ActiveBleedingAnswer.endedEndUnknown =>
                      ContinuationCertainty.confirmed,
                  },
            startDate: periodDate,
            startPrecision: ObservationPrecision.dateOnly,
            startSource: startSource,
            endDate: ended ? periodEndDate : null,
            endPrecision: ended ? ObservationPrecision.dateOnly : null,
            endSource: endSource,
          );
        }

        final baseline = hasBaseline
            ? CycleBaseline(
                userId: userId,
                usualBleedingDurationDays: _haidLengthValue,
                usualCycleLengthDays: _cycleLengthValue,
              )
            : null;

        // Hardening 1: persisted *before* the RPC is ever sent — the same
        // pattern as the Start/End Bleeding sheets (PendingBleedingOperationStore).
        // If the process dies between the server committing and this app
        // ever seeing the response, this record is what lets a future
        // reconciliation (either this same screen's own initState reusing
        // the id, or reconcilePendingOperations running independently at
        // app start/resume) recognize and complete the *same* logical
        // submission instead of risking a second one.
        final params = <String, dynamic>{
          'utcOffsetMinutes': utcOffsetMinutes,
          if (episode != null)
            'episode': {
              'lifecycleStatus': episode.lifecycleStatus.value,
              if (episode.continuationCertainty != null)
                'continuationCertainty': episode.continuationCertainty!.value,
              'startDate': episode.startDate.toIso8601String(),
              'startPrecision': episode.startPrecision.value,
              'startSource': episode.startSource.value,
              if (episode.endDate != null)
                'endDate': episode.endDate!.toIso8601String(),
              if (episode.endPrecision != null)
                'endPrecision': episode.endPrecision!.value,
              if (episode.endSource != null)
                'endSource': episode.endSource!.value,
            },
          if (baseline != null)
            'baseline': {
              if (baseline.usualBleedingDurationDays != null)
                'usualBleedingDurationDays': baseline.usualBleedingDurationDays,
              if (baseline.usualCycleLengthDays != null)
                'usualCycleLengthDays': baseline.usualCycleLengthDays,
            },
        };

        // Onboarding/server hardening (proposed, finding #3): an operation
        // id stands for ONE set of answers. If what is queued under it
        // (from a failed earlier attempt, possibly already committed on the
        // server with its response lost) differs from what she is
        // submitting now, record_onboarding_menstrual_history would treat
        // this as a retry and hand back the old rows as if her changed
        // answer had saved. Drop the stale queued submission and use a
        // fresh id; an unchanged answer keeps the id so a genuine retry
        // stays idempotent.
        await _settleQueuedOnboardingOperation(userId, params);

        await PendingBleedingOperationStore.savePending(
          PendingBleedingOperation(
            operationId: _onboardingOperationId,
            type: PendingBleedingOperationType.onboardingHistory,
            params: params,
            createdAt: DateTime.now(),
          ),
          userId: userId,
        );

        // PR #4 completion wave, Fix A: one atomic, idempotent RPC for
        // everything she answered — either all of it saves, or none of
        // it does. A retry (same _onboardingOperationId) can never
        // duplicate an already-saved episode/baseline or leave one saved
        // while the other silently vanished. Manual QA wave (2026-10-12):
        // the RPC now reconciles with an existing open episode (reuses
        // it if the date matches, reports a typed conflict if it
        // doesn't) instead of throwing a raw uniqueness violation — the
        // baseline always saves independently either way.
        try {
          final result = await BleedingEpisodeRepositoryImpl()
              .recordOnboardingHistory(
                clientOperationId: _onboardingOperationId,
                utcOffsetMinutes: utcOffsetMinutes,
                episode: episode,
                baseline: baseline,
              );

          if (result.episodeConflict) {
            // A real, honest situation, not a failure: her baseline (if
            // any) is already saved above. The episode part is left
            // exactly as it was — never silently closed/overwritten —
            // pending her own choice below.
            //
            // Logging/sync hardening (proposed): this submission is now
            // settled (the server answered; the baseline part — if any —
            // is saved). Its operation id must NOT be reused for her next
            // attempt: record_onboarding_menstrual_history's baseline part
            // is idempotent by that id, so a resubmission with changed
            // answers would silently get the OLD baseline back. Drop the
            // settled operation and give the next attempt a fresh id.
            await PendingBleedingOperationStore.clearPending(
              _onboardingOperationId,
              userId: userId,
            );
            if (!mounted) return;
            setState(() {
              _completingOnboarding = false;
              _onboardingOperationId = const Uuid().v4();
              _onboardingConflictingEpisodeStartDate =
                  result.conflictingEpisodeStartDate;
            });
            return;
          }

          await PendingBleedingOperationStore.clearPending(
            _onboardingOperationId,
            userId: userId,
          );
        } catch (error, stack) {
          // Manual QA fix (2026-10-11), Part 2 root cause: this used to
          // be `catch (_)` — the real PostgrestException (code, message,
          // the failing table/constraint) was discarded entirely, which
          // is exactly why only a generic message was ever available to
          // diagnose a real failure. Reported through the app's one
          // existing error funnel (never the record's own content — only
          // the exception and an opaque context string), and classified:
          // a 23505 unique-violation on bleeding_episodes' one-open-
          // episode-per-user constraint means she already has an open
          // episode — a real, previously-saved one, not data loss. The
          // message below names this specific cause so "go back and
          // review your answers" (the real resolution path — change the
          // conflicting Last Period answer) makes sense to her.
          AppErrorReporter.report(
            error,
            stack,
            context: '_OnboardingScreenState._completeOnboarding',
            feature: 'onboarding',
          );
          final isDuplicateOpenEpisode = isNonRetryableDuplicateEpisodeError(
            error,
          );
          if (!mounted) return;
          setState(() {
            _completingOnboarding = false;
            _onboardingSaveError = isDuplicateOpenEpisode
                ? _t(
                    'You already have a cycle being tracked, so this '
                        "start date couldn't be saved as a new entry. "
                        'Your other answers are still here.',
                    'لديكِ بالفعل دورة قيد التتبع، لذا تعذر حفظ تاريخ '
                        'البداية هذا كسجل جديد. إجاباتكِ الأخرى ما زالت '
                        'محفوظة.',
                  )
                : _t(
                    "We couldn't save the information you entered. Your "
                        'answers are still here — you can try again.',
                    'تعذر حفظ المعلومات التي أدخلتِها. إجاباتكِ ما زالت '
                        'محفوظة هنا — يمكنكِ المحاولة مجدداً.',
                  );
          });
          return;
        }
      } else {
        // Onboarding/server hardening (proposed, finding #2): nothing to
        // save any more (e.g. she changed a failed "started X" answer to
        // "I'm not sure"). A submission still queued from the failed
        // attempt must not be replayed later by background sync.
        await _settleQueuedOnboardingOperation(userId, null);
      }
    }

    await _finishOnboarding();
  }

  /// Onboarding/server hardening (proposed, findings #2/#3): reconciles
  /// the queued onboarding submission with the answers she is submitting
  /// now ([params], or null when there is nothing to save). A queued
  /// submission with the same answers is kept (its id is reused, so the
  /// retry stays idempotent); anything else is dropped so
  /// `reconcilePendingOperations` can never replay an answer she changed
  /// or withdrew, and a changed answer gets a fresh operation id.
  Future<void> _settleQueuedOnboardingOperation(
    String userId,
    Map<String, dynamic>? params,
  ) async {
    final queued = await PendingBleedingOperationStore.getPendingByType(
      PendingBleedingOperationType.onboardingHistory,
      userId: userId,
    );
    if (queued != null) {
      if (params != null && sameOnboardingAnswers(queued.params, params)) {
        _onboardingOperationId = queued.operationId;
        return;
      }
      await PendingBleedingOperationStore.clearPending(
        queued.operationId,
        userId: userId,
      );
      if (queued.operationId == _onboardingOperationId) {
        _onboardingOperationId = const Uuid().v4();
      }
    }
  }

  /// Manual QA fix round 3 (2026-10-11), Part 3 — explicit product
  /// decision: a required-data save failure must never offer a generic
  /// "continue without saving this" escape hatch, which could let her
  /// reach Dashboard with menstrual tracking data she explicitly
  /// provided silently missing. Replaces that affordance with a genuine
  /// resolution path instead: back to the exact question most likely
  /// responsible (Last Period — the only onboarding-completion write
  /// that can conflict with data that already exists), where she can
  /// change her answer (e.g. "I'm not sure" instead of a specific start
  /// date) or confirm it's still what she means, then walk forward again.
  /// Her already-entered predictions/privacy answers are untouched local
  /// state, so walking forward again is fast, not a real repeat of
  /// onboarding.
  void _reviewAnswersAfterSaveFailure() {
    setState(() {
      _onboardingSaveError = null;
      _onboardingConflictingEpisodeStartDate = null;
      _completingOnboarding = false;
      _step = 5;
      _periodSubStep = _PeriodSubStep.pickStart;
    });
  }

  /// Manual QA wave (2026-10-12) — the conflict resolution the RPC
  /// itself refuses to guess at: she's choosing to trust her existing
  /// open episode over the (different) date she just entered during
  /// onboarding. Nothing is overwritten or closed to get here — the
  /// existing episode is untouched, exactly as the RPC left it; this
  /// only finishes onboarding (the baseline, if any, already saved
  /// alongside the conflict result itself).
  Future<void> _keepExistingEpisodeAndContinue() async {
    setState(() {
      _completingOnboarding = true;
      _onboardingConflictingEpisodeStartDate = null;
    });
    await _finishOnboarding();
  }

  Future<void> _finishOnboarding() async {
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
      final location = await PrayerLocationController.instance
          .useDeviceLocation();
      if (!mounted) return;
      setState(() {
        _locationStatus = _LocationStatus.selected;
        _confirmedLocationLabel = prayerLocationLabel(
          location,
          isArabic: _arabic,
        );
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
          color: AppColors.onboardingPrimaryText,
          fontFamily: AppTypography.serifFamily,
        ),
      ),
      const SizedBox(height: 13),
      Text(
        _tr('YOUR CYCLE. YOUR FAITH. YOUR SPACE.', 'دورتكِ. دينكِ. مساحتكِ.'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.onboardingAccent,
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
          backgroundColor: AppColors.onboardingPrimaryText,
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
  });
  final String title, subtitle;
  final List<String> choices;
  final Set<String> selected;
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
          subtitle: '',
          selected: selected.contains(choices[i]),
          onTap: () => onToggle(choices[i]),
        ),
      ),
      const SizedBox(height: 28),
      _Continue(onPressed: onNext),
    ],
  );
}

/// Onboarding redesign, Part 3: the optional entry point to the two
/// estimate questions. Declining is a fully-supported, equally-valid path —
/// the copy here is deliberately reassuring, not a soft push toward "yes".
class _PredictionsGate extends StatelessWidget {
  const _PredictionsGate({required this.onAccept, required this.onSkip});
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(
        _tr(
          'Would you like to add some information to improve predictions?',
          'هل ترغبين في إضافة معلومات لتحسين التوقعات؟',
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.onboardingSurface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: AppColors.shadowColor, blurRadius: 20),
          ],
        ),
        child: Text(
          _tr(
            'You can start tracking right away either way. Answering a '
                'couple of quick questions now just helps Niswah estimate '
                'your next period sooner — if you skip it, basic tracking '
                'still works, and predictions improve on their own as you '
                'log real periods.',
            'يمكنكِ بدء المتابعة فورًا في كل الحالات. الإجابة عن سؤالين '
                'سريعين الآن تساعد نسوة على تقدير حيضكِ القادم بشكل أسرع — '
                'وإذا تخطيتِ ذلك، تستمر المتابعة الأساسية بشكل طبيعي، '
                'وتتحسن التوقعات تلقائيًا مع كل تسجيل فعلي.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.onboardingSecondaryText,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 26),
      _Continue(
        label: _tr(
          'Yes, help me improve predictions',
          'نعم، ساعديني في تحسين التوقعات',
        ),
        onPressed: onAccept,
        strong: true,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: onSkip,
        child: Text(_tr('Skip for now', 'تخطي الآن')),
      ),
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
          color: AppColors.onboardingSurface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: AppColors.shadowColor, blurRadius: 20),
          ],
        ),
        // Onboarding redesign, Part 5: the task's own specified reassurance
        // copy — tracking continues normally, Madhhab is only ever asked
        // again when a Fiqh-guidance feature genuinely needs it.
        child: Text(
          _tr(
            'It’s okay if you don’t know your Madhhab yet. You can keep '
                'tracking your cycle as usual, and we’ll ask you to choose a '
                'Madhhab when personalized Fiqh guidance is needed.',
            'لا بأس إذا كنتِ لا تعرفين مذهبكِ الآن. يمكنكِ متابعة دورتكِ '
                'كالمعتاد، وسنطلب منكِ تحديد المذهب عند الحاجة إلى إرشاد '
                'فقهي مخصص.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.onboardingSecondaryText,
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
          backgroundColor: AppColors.onboardingSelectedBg,
          foregroundColor: AppColors.onboardingPrimaryText,
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
          color: AppColors.onboardingSecondaryText,
          background: AppColors.onboardingBorder,
          icon: const NiswahLoadingIndicator(
            size: NiswahLoadingSize.small,
            contrast: NiswahLoadingContrast.dark,
          ),
          text: _tr('Detecting your location…', 'جارٍ تحديد موقعكِ…'),
        );
      case _LocationStatus.selected:
        return _banner(
          color: AppColors.tahara,
          background: AppColors.success.withValues(alpha: 0.08),
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
          color: AppColors.error,
          background: AppColors.error.withValues(alpha: 0.08),
          icon: const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
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
    final picked = await _showOnboardingDatePicker(
      context: context,
      initialDate: selected ?? now,
      firstDate: _earliestReportableDate(now),
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
    final picked = await _showOnboardingDatePicker(
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

/// Onboarding redesign, Part 4: normalizes Arabic-Indic digits (٠-٩, and the
/// Extended/Persian variant ۰-۹) to ASCII as they're typed, instead of
/// silently dropping them. Root cause (confirmed against the Flutter SDK
/// source): the formatter this replaces,
/// `FilteringTextInputFormatter.digitsOnly`, is `RegExp(r'[0-9]')` — ASCII
/// only — so on a device whose keyboard types Eastern Arabic numerals, every
/// keystroke was deleted before `onChanged` ever fired. `int.tryParse` also
/// only understands ASCII digits, so normalizing here (not just allowing the
/// characters through) is what actually fixes parsing, not merely display.
/// PR #4 hardening, Blocker 6: replaces the old Slider-based `_NumberStep`,
/// whose hard min/max ("2-10/15 days", "15-90 days") could reject a real
/// but unusual answer — a technical/UX bound, not a medical judgment this
/// wave is authorized to make. [minValue]/[maxValue] are a generous
/// technical sanity bound (catch a mistyped 500, not reject a real but
/// unusual answer), not a clinical judgment.
///
/// Onboarding fixes wave (2026-10-11), Part 6: replaces the previous
/// small numeric text field (which had its own now-fixed Arabic-Indic
/// normalization bug, and separately leaked its value into the next
/// question — see the Key fix at the two call sites in [_predictionsStep])
/// with a discrete vertical number wheel. A wheel has no keyboard, no
/// typed-digit numeral system to get wrong, and structurally can only ever
/// produce one exact integer — the entire class of bugs the text field had
/// doesn't exist here. [CupertinoPicker] fires
/// `HapticFeedback.selectionClick()` on every item change on its own, so
/// "haptic feedback if existing infrastructure supports it cleanly" is
/// satisfied for free, not something this widget re-implements.
class _NumberWheelStep extends StatefulWidget {
  const _NumberWheelStep({
    super.key,
    required this.title,
    required this.description,
    required this.initialValue,
    required this.onChanged,
    required this.onNext,
    required this.onUnsure,
    this.maxValue = 99,
    this.validate,
  });
  final String title, description;
  final int? initialValue;
  final ValueChanged<int?> onChanged;
  final VoidCallback onNext;
  final VoidCallback onUnsure;
  final int maxValue;

  /// Onboarding/server hardening (proposed, finding #14): returns a message
  /// when the chosen value is impossible together with her other answer
  /// (e.g. bleeding longer than the whole cycle). Continue stays disabled
  /// while it returns non-null.
  final String? Function(int value)? validate;
  static const int minValue = 1;

  @override
  State<_NumberWheelStep> createState() => _NumberWheelStepState();
}

class _NumberWheelStepState extends State<_NumberWheelStep> {
  // Part 6: "prefer an unselected state initially" — the wheel itself
  // always has to center on *some* row (that's how a wheel works), but
  // [_touched] is what actually decides whether that row counts as a real
  // answer. It starts true only when we're rendering a previously-entered
  // value (e.g. navigating back to this question) — never for a freshly
  // empty question, even though the wheel still visually centers on the
  // midpoint row. `onChanged`/Continue never treat the untouched midpoint
  // as if she'd chosen it.
  late int _displayedValue =
      widget.initialValue ?? (_NumberWheelStep.minValue + widget.maxValue) ~/ 2;
  late bool _touched = widget.initialValue != null;
  late final FixedExtentScrollController _scrollController =
      FixedExtentScrollController(
        initialItem: _displayedValue - _NumberWheelStep.minValue,
      );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSelected(int index) {
    final value = _NumberWheelStep.minValue + index;
    setState(() {
      _displayedValue = value;
      _touched = true;
    });
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.maxValue - _NumberWheelStep.minValue + 1;
    final unit = _tr('days', 'أيام');
    final validationError = _touched
        ? widget.validate?.call(_displayedValue)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(widget.title),
        const SizedBox(height: 8),
        Text(
          widget.description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.onboardingSecondaryText,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        // Manual QA fix round 3 (2026-10-11): a low-alpha
        // `selectionOverlay` still visibly dulled the centered digit in
        // practice (confirmed from a real screenshot: 9/10/11/[blank
        // pink]/13/14/15 — "12" unreadable). Root cause, confirmed
        // against the CupertinoPicker SDK source
        // (packages/flutter/lib/src/cupertino/picker.dart): `children`
        // and `selectionOverlay` are both painted inside the *same*
        // Stack, with `selectionOverlay` added last — it is *always* the
        // topmost layer, by construction, regardless of its own alpha.
        // There is no opacity value that both reads as a clear highlight
        // and never visually competes with the text underneath it.
        //
        // Fixed architecturally instead of cosmetically: the highlight
        // box is now a sibling `Container` placed BEFORE the
        // `CupertinoPicker` in our own outer `Stack`, and
        // `selectionOverlay: null` disables the picker's own (always-on-
        // top) overlay slot entirely. The picker's own background stays
        // transparent, so our highlight box shows through everywhere
        // except where the picker's own row text (now genuinely the
        // topmost layer in *this* Stack) paints over it — the text can
        // never be obscured, by construction, not by tuning a color.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Semantics(
            label: _touched
                ? '$_displayedValue $unit'
                : _tr('No value selected yet', 'لم يتم اختيار قيمة بعد'),
            value: _touched ? '$_displayedValue' : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 168,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Behind the wheel — a compact, clearly-visible
                      // highlight. Neutral outline until she actually
                      // interacts (never implies a confirmed answer); a
                      // soft accent fill + border once touched. Can use a
                      // normal, fully-legible-strength fill now, since it
                      // structurally can never sit in front of the digit.
                      Container(
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: _touched
                              ? AppColors.onboardingSelectedBg
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _touched
                                ? AppColors.onboardingAccent
                                : AppColors.onboardingBorder,
                            width: 1.5,
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _scrollController,
                        builder: (context, _) {
                          final currentIndex = _scrollController.hasClients
                              ? _scrollController.offset / 42
                              : (_displayedValue - _NumberWheelStep.minValue)
                                    .toDouble();
                          return CupertinoPicker(
                            scrollController: _scrollController,
                            itemExtent: 42,
                            backgroundColor: Colors.transparent,
                            diameterRatio: 1.3,
                            // Disabled entirely — see the fix note above.
                            // The highlight is drawn separately, behind
                            // this picker, not through this slot.
                            selectionOverlay: null,
                            onSelectedItemChanged: _handleSelected,
                            children: List.generate(itemCount, (i) {
                              final value = _NumberWheelStep.minValue + i;
                              // Fades rows by their live distance from center
                              // — the center row always reads clearly, rows
                              // further away get progressively lighter,
                              // regardless of touched state.
                              final distance = (i - currentIndex).abs().clamp(
                                0.0,
                                3.0,
                              );
                              final fade = 1.0 - (distance / 3.0) * 0.75;
                              return Center(
                                child: Text(
                                  '$value',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: distance < 0.5
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color:
                                        (_touched
                                                ? AppColors
                                                      .onboardingPrimaryText
                                                : AppColors
                                                      .onboardingSecondaryText)
                                            .withValues(alpha: fade),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unit,
                        style: const TextStyle(
                          color: AppColors.onboardingSecondaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!_touched) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.unfold_more_rounded,
                              size: 14,
                              color: AppColors.onboardingSecondaryText
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                // Manual QA's own specified Arabic hint.
                                _tr(
                                  'Swipe to choose the number of days',
                                  'مرّري لاختيار عدد الأيام',
                                ),
                                style: TextStyle(
                                  color: AppColors.onboardingSecondaryText
                                      .withValues(alpha: 0.7),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (validationError != null) ...[
          const SizedBox(height: 12),
          Text(
            validationError,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.onboardingAccent,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
        // Part 7's exact specified hierarchy: wheel, "I'm not sure", then
        // the Continue CTA last.
        TextButton(
          onPressed: widget.onUnsure,
          child: Text(_tr('I’m not sure', 'لست متأكدة')),
        ),
        const SizedBox(height: 8),
        _Continue(
          onPressed: _touched && validationError == null ? widget.onNext : null,
        ),
      ],
    );
  }
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
          color: AppColors.onboardingPrimaryText,
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
                activeTrackColor: AppColors.mutedRose,
                title: Text(
                  _tr('Hide my identity', 'إخفاء هويتي'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                secondary: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.mutedRose,
                ),
              ),
            ),
            Text(
              _tr(
                'Hide identifying details throughout the community while keeping your health data private.',
                'أخفي بياناتكِ التعريفية في المجتمع مع الحفاظ على خصوصية بياناتكِ الصحية.',
              ),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
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
  const _Welcome({
    required this.onComplete,
    this.isBusy = false,
    this.saveError,
    this.conflictingEpisodeStartDate,
    this.onReviewAnswers,
    this.onKeepExistingEpisode,
  });
  final VoidCallback? onComplete;
  // Hostile self-review fix (2026-09-17): completion writes a real
  // episode/baseline — a disabled, in-flight state prevents a rapid
  // double-tap from firing the async completion twice.
  final bool isBusy;
  // PR #4 hardening, Blocker 3; manual QA fix round 3 (2026-10-11), Part
  // 3: non-null when a real save of required onboarding data genuinely
  // failed — a generic transient-failure message (the RPC itself no
  // longer raises the one deterministic case this used to special-case;
  // see [conflictingEpisodeStartDate] for that). There is deliberately
  // no "continue without saving this" affordance for this — that would
  // risk reaching Dashboard with menstrual data she explicitly provided
  // silently missing. The only two paths out are a real retry, or going
  // back to review/change the answer.
  final String? saveError;
  // Manual QA wave (2026-10-12): non-null only for the RPC's typed
  // episode_conflict — a genuinely different situation from [saveError]
  // (nothing failed; she already has an open episode with this other
  // start date, and the RPC correctly refused to guess which one is
  // "right"). Mutually exclusive with [saveError] in practice.
  final DateTime? conflictingEpisodeStartDate;
  final VoidCallback? onReviewAnswers;
  final VoidCallback? onKeepExistingEpisode;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          color: AppColors.onboardingSelectedBg,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: AppColors.onboardingAccent,
          size: 28,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        // Part 11's exact specified completion copy.
        _tr('You’re ready to get started', 'أصبحتِ جاهزة للبدء'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: AppColors.onboardingPrimaryText,
          fontFamily: AppTypography.serifFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _tr(
          'You can start tracking your cycle, and we’ll learn its pattern '
              'gradually with every log.',
          'يمكنكِ البدء بتسجيل دورتكِ، وسنتعرف على نمطها تدريجيًا مع كل '
              'تسجيل.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onboardingSecondaryText,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _tr('This is what Niswah gives you', 'هذا ما تقدمه لكِ نسوة'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onboardingSecondaryText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 8),
      // Onboarding fixes wave (2026-10-11), Part 8/9: the real product
      // feature registry (kAppFeatures, also used by SignInScreen's own
      // pre-auth showcase) instead of 4 generic placeholder items — "this
      // is what Niswah gives you now", not an undersold abstraction.
      // Compacted (manual QA, 2026-10-11 Part 1B): the completion CTA must
      // never sit below the fold — this grid was the single biggest
      // contributor to the screen's height.
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.onboardingSelectedBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.onboardingBorder),
        ),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: kAppFeatures.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.1,
          ),
          itemBuilder: (_, i) {
            final feature = kAppFeatures[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: AppColors.onboardingSurface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.onboardingBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: feature.iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      feature.icon,
                      color: feature.iconColor,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _tr(feature.labelEn, feature.labelAr),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onboardingPrimaryText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      if (saveError != null || conflictingEpisodeStartDate != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Text(
            // Manual QA wave (2026-10-12): a conflict is a real,
            // anticipatable situation, not a failure — the message
            // names the existing episode's own date (never fabricated,
            // always the RPC's own reconciliation result) so "keep my
            // existing cycle" below makes sense as a real, informed
            // choice.
            conflictingEpisodeStartDate != null
                ? _tr(
                    'You already have a cycle being tracked, starting '
                        '${_formatDate(conflictingEpisodeStartDate!)} — '
                        "different from the date you just entered. We "
                        "haven't changed either one.",
                    'لديكِ بالفعل دورة قيد التتبع بدأت في '
                        '${_formatDate(conflictingEpisodeStartDate!)} — '
                        'وهو يختلف عن التاريخ الذي أدخلتِه للتو. لم نغيّر '
                        'أيًا منهما.',
                  )
                : saveError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
      const SizedBox(height: 20),
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
              // Part 11's exact specified primary action copy. Manual QA
              // fix round 3 (2026-10-11), Part 3 — explicit product
              // decision: retry is always the primary action for a
              // required-data failure, whether or not an identical retry
              // would succeed. "Go back and review answers" below is
              // what actually resolves the deterministic case (changing
              // the answer that's in genuine conflict) — hiding retry
              // isn't necessary once that real path exists. A genuine
              // episode conflict (2026-10-12) isn't a failure at all, so
              // its own primary action is the explicit, informed choice
              // to keep the existing episode and finish — never a retry
              // of an identical request that would report the exact
              // same conflict again.
              label: conflictingEpisodeStartDate != null
                  ? _tr(
                      'Keep my existing cycle and continue',
                      'الاحتفاظ بدورتي الحالية والمتابعة',
                    )
                  : saveError == null
                  ? _tr('Start tracking', 'ابدئي المتابعة')
                  : _tr('Try again', 'المحاولة مجدداً'),
              onPressed: conflictingEpisodeStartDate != null
                  ? onKeepExistingEpisode
                  : onComplete,
              strong: true,
            ),
      // Manual QA fix round 3 (2026-10-11), Part 3: replaces the
      // previous "Continue without saving this" — deliberately removed
      // for a required-data failure, since it could let her reach
      // Dashboard with menstrual data she explicitly provided silently
      // missing. "Go back and review answers" is a genuine resolution
      // path instead, not a bypass — offered for a conflict too, so
      // changing what she entered (instead of keeping the existing
      // episode) is always available.
      if ((saveError != null || conflictingEpisodeStartDate != null) &&
          onReviewAnswers != null)
        TextButton(
          onPressed: onReviewAnswers,
          child: Text(
            _tr('Go back and review your answers', 'العودة ومراجعة الإجابات'),
          ),
        ),
    ],
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  // Onboarding redesign, Part 7: was `displayMedium` (28px) — oversized for
  // a per-step question heading and visually competing with the content
  // below it. `headlineMedium` (20px) keeps a clear heading/input
  // relationship without dominating the screen.
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontFamily: AppTypography.serifFamily,
      fontWeight: FontWeight.w700,
      color: AppColors.onboardingPrimaryText,
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final activeColor = strong
        ? AppColors.onboardingPrimaryText
        : AppColors.onboardingPrimaryAction;
    // Manual QA fix (2026-10-11), Part 1A: the enabled state previously
    // differed from disabled by color alone, which read as "ambiguously
    // disabled" rather than clearly tappable. A soft colored glow (only
    // when enabled) plus a touch of real elevation gives it a second,
    // independent visual cue — never color alone.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: activeColor,
          disabledBackgroundColor: AppColors.onboardingDisabled,
          disabledForegroundColor: AppColors.onboardingSecondaryText,
          elevation: enabled ? 2 : 0,
          shadowColor: activeColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label == 'Continue' ? _tr('Continue', 'متابعة') : label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: enabled ? Colors.white : null,
          ),
        ),
      ),
    );
  }
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
          color: selected
              ? AppColors.onboardingSelectedBg
              : AppColors.onboardingSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.onboardingAccent
                : AppColors.onboardingBorder,
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
                          ? AppColors.onboardingPrimaryText
                          : AppColors.onboardingSecondaryText,
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
                        color: AppColors.onboardingSecondaryText,
                        fontSize: 11,
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
                  color: AppColors.onboardingAccent,
                  size: 17,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

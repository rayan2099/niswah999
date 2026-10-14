import 'package:flutter/material.dart';

import '../../../core/localization/app_locale_controller.dart';
import '../../../core/preferences/madhhab_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import '../../madhhab/presentation/widgets/madhhab_change_confirmation.dart';
import '../../madhhab/presentation/widgets/madhhab_selector.dart';
import 'widgets/madhhab_resolution_flow.dart';

String _tr(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Madhhab Resolution Gate wave (2026-09-16), completing `AUTH-010`'s
/// originally-shipped "I don't know my Madhhab" assistance behavior, which
/// the owner tested and found not robust enough (a single free-text
/// residence-country question that often returned "لا يتوفر اقتراح لهذه
/// المنطقة بعد" with no further path forward). This is the ONE canonical
/// resolver — for every context that needs a real Madhhab resolved, not a
/// duplicated copy of this logic per screen (Section 17 of the charter).
///
/// Deliberately not wired into onboarding's own existing "help me choose"
/// step this wave (out of scope — that step already has its own tested,
/// working assistance path from `AUTH-010`'s original remediation; this
/// wave's required wiring is Log-my-Haidh and Settings only, per the
/// charter's own explicit "do not wire unrelated surfaces... unless
/// already trivial" instruction).
enum MadhhabResolutionContext {
  onboarding,
  haidhLogging,
  settings,
  fiqhAdvisor,
}

/// Which step [showMadhhabResolutionFlow] opens on — still the exact same
/// screen/logic either way (Section 17's "one authority," not a fork), just
/// skipping the intro's own "do you know it?" question when the caller
/// already knows the answer (e.g. Settings' two distinct buttons — Section
/// 16 — each already say which branch the user wants).
enum MadhhabResolutionStart { intro, knownPicker, guided }

/// Opens the resolution flow and returns `true` only if the user's Madhhab
/// genuinely became [MadhhabSelectionState.selected] before the flow
/// closed — `false` for every other outcome (dismissed, backed all the way
/// out, or explicitly "still not sure", which persists
/// [MadhhabSelectionState.unknown] but never [MadhhabSelectionState.selected]).
/// Callers that need to gate a Madhhab-dependent action (e.g. Haidh
/// logging) must treat only a `true` result as permission to proceed.
Future<bool> showMadhhabResolutionFlow(
  BuildContext context, {
  required MadhhabResolutionContext entryContext,
  MadhhabResolutionStart start = MadhhabResolutionStart.intro,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          MadhhabResolutionScreen(entryContext: entryContext, start: start),
    ),
  );
  return result ?? false;
}

// Manual QA wave (2026-10-12): was `{ intro, knownPicker, confirm,
// guidedQ1, guidedQ2, guidedResult }` — the three guided-flow steps
// (country, country-restated-as-family, result) were this screen's own
// duplicate of exactly the country→suggestion/manual sub-flow onboarding
// already had, right down to asking two separate country questions
// ("where did you learn your religion" / "what does your family follow")
// with free-text chips and a confidence-warning dead end before manual
// selection. Collapsed to one `guided` step rendering the shared
// `MadhhabResolutionFlow` — the same component onboarding uses.
enum _Step { intro, knownPicker, confirm, guided }

class MadhhabResolutionScreen extends StatefulWidget {
  const MadhhabResolutionScreen({
    super.key,
    required this.entryContext,
    this.start = MadhhabResolutionStart.intro,
  });
  final MadhhabResolutionContext entryContext;
  final MadhhabResolutionStart start;

  /// Test-only observability for the direct-vs-suggested-confirmed
  /// distinction (Section 12 of the charter): `'direct'` for a manual pick
  /// from the 4-school list, `'suggested_confirmed'` only when an explicit
  /// "yes, use X" follows a guided suggestion. Deliberately never persisted
  /// to `SharedPreferences`/the server — `MadhhabController`'s own 3-state
  /// model (unset/unknown/selected) is the sole authoritative persisted
  /// value (Section 20: minimize persistence of anything beyond what's
  /// genuinely needed); this exists only so a test can prove the two code
  /// paths are genuinely distinct, not to add a new persisted field. Lives
  /// on the public widget class (not the private State) so a test file in
  /// a different library can actually read it.
  @visibleForTesting
  static String? lastConfirmedSelectionSource;

  @override
  State<MadhhabResolutionScreen> createState() =>
      _MadhhabResolutionScreenState();
}

class _MadhhabResolutionScreenState extends State<MadhhabResolutionScreen> {
  late _Step _step;
  Madhhab? _pendingConfirm;
  String? _selectionSource; // 'direct' | 'suggested_confirmed', see lastConfirmedSelectionSource above.
  _Step _confirmReturnStep = _Step.intro;

  /// The step this screen actually opened on (Section 16: Settings' two
  /// buttons skip the intro's own question, having already answered it by
  /// which button was tapped) — back-navigation from here must exit the
  /// screen entirely, never loop back to an intro the user never saw.
  late final _Step _entryStep;

  @override
  void initState() {
    super.initState();
    _entryStep = switch (widget.start) {
      MadhhabResolutionStart.intro => _Step.intro,
      MadhhabResolutionStart.knownPicker => _Step.knownPicker,
      MadhhabResolutionStart.guided => _Step.guided,
    };
    _step = _entryStep;
  }

  /// Routes through the one canonical transition/confirmation path
  /// (`setMadhhabWithConfirmation`) instead of calling
  /// `MadhhabController` directly — this screen is reached post-onboarding
  /// (Settings' "Help me choose", the Log-my-Haidh gate), where a prior
  /// selection (or an UNKNOWN with real historical logs behind it) can
  /// genuinely exist, so Requirement 2's light/full notices must be able
  /// to fire here exactly as they do from Settings' own direct grid. Only
  /// pops with a result once the change is actually confirmed/applied —
  /// a cancelled dialog leaves her on this screen to reconsider, not
  /// incorrectly treated as a completed selection.
  Future<void> _confirmSelection(
    Madhhab madhhab, {
    required String source,
  }) async {
    final applied = await setMadhhabWithConfirmation(
      context,
      newMadhhab: madhhab,
      source: 'resolution_$source',
    );
    if (!applied) return;
    MadhhabResolutionScreen.lastConfirmedSelectionSource = source;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _stillNotSure() async {
    final applied = await setMadhhabWithConfirmation(
      context,
      newMadhhab: null,
      source: 'resolution_still_not_sure',
    );
    if (!applied) return;
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  /// Moves back one internal step, called directly by the AppBar's own
  /// back button below — deliberately NOT routed through `Navigator.pop`/
  /// `PopScope`, since a `PopScope(canPop: false)` gate (needed while the
  /// user is mid-flow, so a hardware back/swipe-back doesn't silently
  /// abandon her partway through) would block every pop attempt uniformly,
  /// including this screen's own genuine exits (`_confirmSelection`/
  /// `_stillNotSure` below, both of which must pop with a real result from
  /// deep, non-entry steps). Keeping internal back-navigation entirely
  /// separate from the Navigator's own pop machinery avoids that conflict:
  /// a hardware back/swipe-back at any non-entry step simply exits the
  /// whole flow (standard, predictable behavior for a step flow with its
  /// own visible back arrow for internal navigation), while this method
  /// handles the arrow tap.
  void _goBackOneStep() {
    setState(() {
      _step = switch (_step) {
        _Step.intro => _entryStep,
        _Step.knownPicker => _entryStep,
        _Step.confirm => _confirmReturnStep,
        _Step.guided => _entryStep,
      };
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.brandBackground,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Manual QA wave (2026-10-12): while `_step == _Step.guided`, the
      // shared `MadhhabResolutionFlow` owns its own internal back
      // navigation (each of its own internal steps has its own visible
      // "Back" button) — this screen's single AppBar back arrow would
      // otherwise be a second, conflicting way to go back from the same
      // screen.
      leading: (_step == _entryStep || _step == _Step.guided)
          ? null
          : BackButton(onPressed: _goBackOneStep),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildStep(),
        ),
      ),
    ),
  );

  Widget _buildStep() {
    switch (_step) {
      case _Step.intro:
        return _IntroStep(
          entryContext: widget.entryContext,
          onKnowsMadhhab: () => setState(() => _step = _Step.knownPicker),
          onNeedsHelp: () => setState(() => _step = _Step.guided),
        );
      case _Step.knownPicker:
        return _KnownPickerStep(
          onSelected: (madhhab) => setState(() {
            _pendingConfirm = madhhab;
            _selectionSource = 'direct';
            _confirmReturnStep = _Step.knownPicker;
            _step = _Step.confirm;
          }),
          onStillNotSure: _stillNotSure,
        );
      case _Step.confirm:
        return _ConfirmStep(
          madhhab: _pendingConfirm!,
          onConfirm: () => _confirmSelection(
            _pendingConfirm!,
            source: _selectionSource ?? 'direct',
          ),
          onBack: () => setState(() => _step = _confirmReturnStep),
        );
      case _Step.guided:
        // Manual QA wave (2026-10-12): the Required Fix's "one shared
        // Madhhab recommendation/change flow everywhere" — the exact
        // same `MadhhabResolutionFlow` onboarding uses, not a parallel
        // copy. Persistence stays context-specific: this screen's own
        // `_confirmSelection`/`_stillNotSure` (pop-with-result,
        // `lastConfirmedSelectionSource` for tests) route the result
        // through `setMadhhabWithConfirmation`, so Requirement 2's light/
        // full notices still fire here exactly as they would from
        // Settings' own direct grid — see `_confirmSelection`'s own doc
        // comment above.
        return MadhhabResolutionFlow(
          // Preserves the pre-unification distinction: 'suggested_confirmed'
          // only for an actual confirmed geographic suggestion, 'direct'
          // for a manual pick from the fallback grid — no suggestion was
          // ever shown to confirm in that case.
          onSelectMadhhab: (madhhab, {required viaSuggestion}) =>
              _confirmSelection(
                madhhab,
                source: viaSuggestion ? 'suggested_confirmed' : 'direct',
              ),
          onSelectUnknown: _stillNotSure,
          onExitFirstStep: () => setState(() => _step = _entryStep),
        );
    }
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({
    required this.entryContext,
    required this.onKnowsMadhhab,
    required this.onNeedsHelp,
  });
  final MadhhabResolutionContext entryContext;
  final VoidCallback onKnowsMadhhab;
  final VoidCallback onNeedsHelp;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(
        entryContext == MadhhabResolutionContext.haidhLogging
            ? _tr('Before logging your Haidh', 'قبل تسجيل حيضك')
            : _tr('Your Fiqh Madhhab', 'مذهبك الفقهي'),
      ),
      const SizedBox(height: 16),
      _Card(
        child: Text(
          _tr(
            'Some rulings about Haidh differ between schools of Fiqh, so we '
                'need to know which one you follow to show you the right '
                'guidance.',
            'بعض أحكام الحيض تختلف باختلاف المذهب، ولذلك نحتاج معرفة المذهب '
                'الذي تتبعينه حتى نقدم لكِ أحكاماً مناسبة.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 26),
      _PrimaryButton(
        label: _tr('I know my Madhhab', 'أعرف مذهبي'),
        onPressed: onKnowsMadhhab,
      ),
      const SizedBox(height: 10),
      _SecondaryButton(
        label: _tr("I don't know — help me", 'لا أعرف مذهبي — ساعديني'),
        onPressed: onNeedsHelp,
      ),
    ],
  );
}

class _KnownPickerStep extends StatelessWidget {
  const _KnownPickerStep({required this.onSelected, required this.onStillNotSure});
  final ValueChanged<Madhhab> onSelected;
  final VoidCallback onStillNotSure;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('What is your Fiqh Madhhab?', 'ما هو مذهبك الفقهي؟')),
      const SizedBox(height: 22),
      // Requirement 1/5: the shared MadhhabSelector, also used by
      // onboarding and Settings. This step never pre-highlights a
      // tile — it's a fresh pick within this flow, not a reflection of
      // MadhhabController's current state (which every entry point to
      // this screen already guarantees is unset/unknown anyway).
      MadhhabSelector(
        state: MadhhabSelectionState.unset,
        selected: null,
        onSelectMadhhab: onSelected,
        onSelectUnknown: onStillNotSure,
      ),
    ],
  );
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.madhhab,
    required this.onConfirm,
    required this.onBack,
  });
  final Madhhab madhhab;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  static String _name(Madhhab m) => switch (m) {
    Madhhab.hanafi => _tr('Hanafi', 'الحنفي'),
    Madhhab.maliki => _tr('Maliki', 'المالكي'),
    Madhhab.shafii => _tr("Shafi'i", 'الشافعي'),
    Madhhab.hanbali => _tr('Hanbali', 'الحنبلي'),
  };

  @override
  Widget build(BuildContext context) {
    final name = _name(madhhab);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(
          _tr(
            'Use the $name school in Niswah\'s rulings?',
            'هل تريدين استخدام المذهب $name في أحكام نسوة؟',
          ),
        ),
        const SizedBox(height: 26),
        _PrimaryButton(
          label: _tr('Yes, use $name', 'نعم، استخدمي $name'),
          onPressed: onConfirm,
        ),
        const SizedBox(height: 10),
        _SecondaryButton(label: _tr('Back', 'العودة'), onPressed: onBack),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.roseInk),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(color: AppColors.shadowColor, blurRadius: 20),
      ],
    ),
    child: child,
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      backgroundColor: AppColors.brandPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
    child: Text(label),
  );
}


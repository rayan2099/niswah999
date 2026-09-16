import 'package:flutter/material.dart';

import '../../../core/data/iso_countries.dart';
import '../../../core/localization/app_locale_controller.dart';
import '../../../core/preferences/madhhab_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import '../../onboarding/domain/services/madhhab_suggestion_service.dart';

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

enum _Step { intro, knownPicker, confirm, guidedQ1, guidedQ2, guidedResult }

enum _CountryAnswerKind { specific, multiple, unknown, preferNotToSay }

class _CountryAnswer {
  const _CountryAnswer.specific(this.country)
    : kind = _CountryAnswerKind.specific;
  const _CountryAnswer.multiple()
    : kind = _CountryAnswerKind.multiple,
      country = null;
  const _CountryAnswer.unknown()
    : kind = _CountryAnswerKind.unknown,
      country = null;
  const _CountryAnswer.preferNotToSay()
    : kind = _CountryAnswerKind.preferNotToSay,
      country = null;

  final _CountryAnswerKind kind;
  final IsoCountry? country;
}

enum _GuidedResultKind { single, multiple, insufficient }

class _GuidedResult {
  const _GuidedResult.single(Madhhab madhhab, this.note)
    : kind = _GuidedResultKind.single,
      candidates = const [],
      _single = madhhab;
  const _GuidedResult.multiple(this.candidates, this.note)
    : kind = _GuidedResultKind.multiple,
      _single = null;
  const _GuidedResult.insufficient()
    : kind = _GuidedResultKind.insufficient,
      candidates = const [],
      note = null,
      _single = null;

  final _GuidedResultKind kind;
  final List<Madhhab> candidates;
  final String? note;
  final Madhhab? _single;

  Madhhab get single => _single!;
}

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
  bool _showingAllSchoolsForManualPick = false;

  _CountryAnswer? _upbringingAnswer;
  _CountryAnswer? _familyAnswer;
  _GuidedResult? _guidedResult;

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
      MadhhabResolutionStart.guided => _Step.guidedQ1,
    };
    _step = _entryStep;
  }

  Future<void> _confirmSelection(
    Madhhab madhhab, {
    required String source,
  }) async {
    MadhhabResolutionScreen.lastConfirmedSelectionSource = source;
    await MadhhabController.instance.selectMadhhab(madhhab);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _stillNotSure() async {
    await MadhhabController.instance.selectUnknown();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  _GuidedResult _toGuidedResult(MadhhabSuggestion suggestion) =>
      suggestion.likelyMadhahib.length == 1
      ? _GuidedResult.single(
          suggestion.likelyMadhahib.single,
          suggestion.regionNote,
        )
      : _GuidedResult.multiple(
          suggestion.likelyMadhahib,
          suggestion.regionNote,
        );

  /// Signal hierarchy (Sections 5/9): religious upbringing outranks
  /// family/community; current residence is never used here at all — it is
  /// deliberately the weakest signal in the charter's own hierarchy, and
  /// omitting it entirely trivially guarantees it can never, by itself,
  /// produce a suggestion (Section 8's Canada/Saudi-Arabia examples).
  _GuidedResult _resolveGuided() {
    const service = MadhhabSuggestionService();
    final upbringing = _upbringingAnswer;
    if (upbringing?.kind == _CountryAnswerKind.specific) {
      final suggestion = service.suggest(
        explicitCountry: upbringing!.country!.nameEn,
      );
      if (suggestion.isResolved) return _toGuidedResult(suggestion);
    }
    final family = _familyAnswer;
    if (family?.kind == _CountryAnswerKind.specific) {
      final suggestion = service.suggest(
        explicitCountry: family!.country!.nameEn,
      );
      if (suggestion.isResolved) return _toGuidedResult(suggestion);
    }
    return const _GuidedResult.insufficient();
  }

  void _onUpbringingAnswered(_CountryAnswer answer) {
    setState(() {
      _upbringingAnswer = answer;
      if (answer.kind == _CountryAnswerKind.specific) {
        const service = MadhhabSuggestionService();
        final suggestion = service.suggest(
          explicitCountry: answer.country!.nameEn,
        );
        if (suggestion.isResolved) {
          _guidedResult = _toGuidedResult(suggestion);
          _step = _Step.guidedResult;
          return;
        }
      }
      _step = _Step.guidedQ2;
    });
  }

  void _onFamilyAnswered(_CountryAnswer answer) {
    setState(() {
      _familyAnswer = answer;
      _guidedResult = _resolveGuided();
      _step = _Step.guidedResult;
    });
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
        _Step.knownPicker =>
          _showingAllSchoolsForManualPick ? _Step.guidedResult : _entryStep,
        _Step.confirm => _confirmReturnStep,
        _Step.guidedQ1 => _entryStep,
        _Step.guidedQ2 => _Step.guidedQ1,
        _Step.guidedResult =>
          _familyAnswer != null ? _Step.guidedQ2 : _Step.guidedQ1,
      };
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.brandBackground,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: _step == _entryStep
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
          onKnowsMadhhab: () => setState(() {
            _showingAllSchoolsForManualPick = false;
            _step = _Step.knownPicker;
          }),
          onNeedsHelp: () => setState(() => _step = _Step.guidedQ1),
        );
      case _Step.knownPicker:
        return _KnownPickerStep(
          onSelected: (madhhab) => setState(() {
            _pendingConfirm = madhhab;
            _selectionSource = 'direct';
            _confirmReturnStep = _Step.knownPicker;
            _step = _Step.confirm;
          }),
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
      case _Step.guidedQ1:
        return _CountryQuestionStep(
          title: _tr(
            'Where did you learn most of your religious practice?',
            'أين تعلّمتِ أغلب أحكامك الدينية؟',
          ),
          onAnswered: _onUpbringingAnswered,
          onBack: () => setState(() => _step = _Step.intro),
        );
      case _Step.guidedQ2:
        return _CountryQuestionStep(
          title: _tr(
            'What country or community does your family mostly follow in religious matters?',
            'ما البلد أو المجتمع الذي تتبع عائلتك غالباً في أمور الدين؟',
          ),
          onAnswered: _onFamilyAnswered,
          onBack: () => setState(() => _step = _Step.guidedQ1),
        );
      case _Step.guidedResult:
        // Section 11's own "Yes, use X" action on a suggestion IS the
        // explicit confirmation itself — routing it through the generic
        // _ConfirmStep as well would ask the exact same question twice in
        // a row with identical wording. That second screen is reserved for
        // the *direct* manual-pick path (Section 3), which genuinely needs
        // its own separate confirmation step.
        return _GuidedResultStep(
          result: _guidedResult!,
          onUseSingle: () => _confirmSelection(
            _guidedResult!.single,
            source: 'suggested_confirmed',
          ),
          onUseCandidate: (madhhab) =>
              _confirmSelection(madhhab, source: 'suggested_confirmed'),
          onShowOtherSchools: () => setState(() {
            _showingAllSchoolsForManualPick = true;
            _step = _Step.knownPicker;
          }),
          onStillNotSure: _stillNotSure,
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
  const _KnownPickerStep({required this.onSelected});
  final ValueChanged<Madhhab> onSelected;

  static String _name(Madhhab m) => switch (m) {
    Madhhab.hanafi => _tr('Hanafi', 'حنفي'),
    Madhhab.maliki => _tr('Maliki', 'مالكي'),
    Madhhab.shafii => _tr("Shafi'i", 'شافعي'),
    Madhhab.hanbali => _tr('Hanbali', 'حنبلي'),
  };

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('What is your Fiqh Madhhab?', 'ما هو مذهبك الفقهي؟')),
      const SizedBox(height: 22),
      for (final madhhab in Madhhab.values) ...[
        _ChoiceCard(label: _name(madhhab), onTap: () => onSelected(madhhab)),
        const SizedBox(height: 10),
      ],
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

class _CountryQuestionStep extends StatefulWidget {
  const _CountryQuestionStep({
    required this.title,
    required this.onAnswered,
    required this.onBack,
  });
  final String title;
  final ValueChanged<_CountryAnswer> onAnswered;
  final VoidCallback onBack;

  @override
  State<_CountryQuestionStep> createState() => _CountryQuestionStepState();
}

class _CountryQuestionStepState extends State<_CountryQuestionStep> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    final filtered = _query.trim().isEmpty
        ? kIsoCountries
        : kIsoCountries
              .where(
                (c) =>
                    c.nameEn.toLowerCase().contains(
                      _query.trim().toLowerCase(),
                    ) ||
                    c.nameAr.contains(_query.trim()),
              )
              .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(widget.title),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: Text(
                _tr('Lived in more than one country', 'عشت في أكثر من دولة'),
              ),
              onPressed: () =>
                  widget.onAnswered(const _CountryAnswer.multiple()),
            ),
            ActionChip(
              label: Text(_tr("I don't know", 'لا أعرف')),
              onPressed: () =>
                  widget.onAnswered(const _CountryAnswer.unknown()),
            ),
            ActionChip(
              label: Text(_tr('Prefer not to say', 'أفضل عدم الإجابة')),
              onPressed: () =>
                  widget.onAnswered(const _CountryAnswer.preferNotToSay()),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: _tr('Search for a country', 'ابحثي عن دولة'),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filtered.length,
            itemBuilder: (_, index) {
              final country = filtered[index];
              return ListTile(
                title: Text(arabic ? country.nameAr : country.nameEn),
                onTap: () =>
                    widget.onAnswered(_CountryAnswer.specific(country)),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _SecondaryButton(label: _tr('Back', 'رجوع'), onPressed: widget.onBack),
      ],
    );
  }
}

class _GuidedResultStep extends StatelessWidget {
  const _GuidedResultStep({
    required this.result,
    required this.onUseSingle,
    required this.onUseCandidate,
    required this.onShowOtherSchools,
    required this.onStillNotSure,
  });
  final _GuidedResult result;
  final VoidCallback onUseSingle;
  final ValueChanged<Madhhab> onUseCandidate;
  final VoidCallback onShowOtherSchools;
  final VoidCallback onStillNotSure;

  static String _name(Madhhab m) => switch (m) {
    Madhhab.hanafi => _tr('Hanafi', 'الحنفي'),
    Madhhab.maliki => _tr('Maliki', 'المالكي'),
    Madhhab.shafii => _tr("Shafi'i", 'الشافعي'),
    Madhhab.hanbali => _tr('Hanbali', 'الحنبلي'),
  };

  @override
  Widget build(BuildContext context) {
    switch (result.kind) {
      case _GuidedResultKind.single:
        final name = _name(result.single);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Title(
              _tr(
                'The $name school may be closest to the religious '
                    'environment you described.',
                'قد يكون المذهب $name الأقرب للبيئة الدينية التي نشأتِ فيها.',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _tr(
                'This is only a suggestion — nothing is set until you '
                    'choose it yourself.',
                'هذا اقتراح فقط ولن نعتمد أي مذهب إلا بعد اختياركِ.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 22),
            _PrimaryButton(
              label: _tr('Yes, use $name', 'نعم، استخدمي المذهب $name'),
              onPressed: onUseSingle,
            ),
            const SizedBox(height: 10),
            _SecondaryButton(
              label: _tr('Show other schools', 'عرض المذاهب الأخرى'),
              onPressed: onShowOtherSchools,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onStillNotSure,
              child: Text(_tr('Still not sure', 'ما زلت غير متأكدة')),
            ),
          ],
        );
      case _GuidedResultKind.multiple:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Title(
              _tr(
                'More than one school is common in the environment you '
                    'described.',
                'أكثر من مذهب شائع في البيئة التي وصفتِها.',
              ),
            ),
            const SizedBox(height: 18),
            for (final candidate in result.candidates) ...[
              _ChoiceCard(
                label: _name(candidate),
                onTap: () => onUseCandidate(candidate),
              ),
              const SizedBox(height: 10),
            ],
            TextButton(
              onPressed: onStillNotSure,
              child: Text(_tr('Still not sure', 'ما زلت غير متأكدة')),
            ),
          ],
        );
      case _GuidedResultKind.insufficient:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Title(
              _tr(
                "The current information isn't enough for a confident "
                    'suggestion, and that\'s alright.',
                'المعلومات الحالية لا تكفي لاقتراح مذهب بثقة، وهذا طبيعي.',
              ),
            ),
            const SizedBox(height: 22),
            _PrimaryButton(
              label: _tr('Choose manually', 'اختيار المذهب يدوياً'),
              onPressed: onShowOtherSchools,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onStillNotSure,
              child: Text(_tr('Still not sure', 'ما زلت غير متأكدة')),
            ),
          ],
        );
    }
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

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.shadowColor),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

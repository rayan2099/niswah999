import 'package:flutter/material.dart';

import '../../../../core/data/iso_countries.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import '../../../madhhab/presentation/widgets/madhhab_selector.dart';
import '../../../onboarding/domain/services/madhhab_suggestion_service.dart';

String _tr(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Manual QA wave (2026-10-12): onboarding and the in-app Madhhab change
/// flow (`MadhhabResolutionScreen`, reached from Profile/Settings' "Help
/// me choose" and the Log-my-Haidh gate) had drifted into two completely
/// separate implementations of "turn a country into a Madhhab
/// suggestion." Onboarding's (upbringing-country question → searchable
/// picker → suggestion/manual-selector) was the one actually fixed this
/// session (no dead-end for an unreviewed mapping, ISO-code search,
/// region refinement); the in-app flow still asked the old two-question
/// "where did you learn your religion / what does your family follow"
/// pair with free-text chips, and dead-ended on
/// "المعلومات الحالية لا تكفي لاقتراح مذهب بثقة" before manual selection.
///
/// This is the one extracted, shared body for that entire
/// country→suggestion/manual sub-flow — the Required Fix's "shared
/// upbringing-country question / country picker / optional region
/// refinement / MadhhabSuggestionService / reviewed-unreviewed branching
/// / manual selector." It owns none of what's deliberately
/// context-specific: how the *result* gets persisted (onboarding calls
/// `MadhhabController` directly; Settings/Log-my-Haidh route through
/// `setMadhhabWithConfirmation` so the existing change-warning dialogs —
/// Requirement 2 — still fire when relevant), and nothing about what
/// comes before or after it in whichever screen embeds it.
///
/// [onSelectMadhhab]/[onSelectUnknown] are called with the resolved
/// choice — this widget never persists anything itself. [onExitFirstStep]
/// is called only when she backs out of the very first step (the country
/// question) — every other internal step (region, manual-select) handles
/// its own back navigation internally, so the embedding screen never
/// needs its own back button while this flow is showing.
class MadhhabResolutionFlow extends StatefulWidget {
  const MadhhabResolutionFlow({
    super.key,
    required this.onSelectMadhhab,
    required this.onSelectUnknown,
    required this.onExitFirstStep,
    this.initialCountry,
    this.onCountryChanged,
  });

  // [viaSuggestion] is true only when she confirmed an actual displayed
  // geographic suggestion ("Use <school>") — false for a pick from the
  // manual-select grid (no suggestion was ever shown to confirm). Lets
  // an embedding screen's own audit trail (e.g. `madhhab_history`'s
  // `source`) distinguish a confirmed suggestion from a direct manual
  // pick, exactly as the pre-unification resolution screen already did.
  final void Function(Madhhab madhhab, {required bool viaSuggestion})
  onSelectMadhhab;
  final VoidCallback onSelectUnknown;
  final VoidCallback onExitFirstStep;
  final IsoCountry? initialCountry;
  // Optional: lets an embedding screen remember her country choice across
  // leaving this flow entirely (e.g. backing out via [onExitFirstStep])
  // and re-entering later via a fresh [initialCountry] — this widget's
  // own internal state doesn't survive that round trip on its own.
  final ValueChanged<IsoCountry>? onCountryChanged;

  @override
  State<MadhhabResolutionFlow> createState() => _MadhhabResolutionFlowState();
}

enum _FlowStep { country, region, suggestion, manualSelect }

class _MadhhabResolutionFlowState extends State<MadhhabResolutionFlow> {
  late _FlowStep _step = _FlowStep.country;
  late IsoCountry? _country = widget.initialCountry;
  List<String> _regionOptions = const [];
  MadhhabSuggestion? _suggestion;

  void _submitCountry(IsoCountry country) {
    setState(() => _country = country);
    widget.onCountryChanged?.call(country);
    // Part 3: purely data-driven — only asks a follow-up region question
    // when the reviewed mapping actually has more than one region-level
    // entry for this country (today, only India). Never a hardcoded
    // per-country UI branch.
    final regions = const MadhhabSuggestionService().regionsFor(
      country.code,
    );
    if (regions.isNotEmpty) {
      setState(() {
        _regionOptions = regions;
        _step = _FlowStep.region;
      });
    } else {
      _resolve(country);
    }
  }

  /// The single place that turns a country (+ optional region) into a
  /// suggestion and routes to the right next step — an unresolved
  /// suggestion (no APPROVED mapping, or "my region isn't listed") always
  /// goes straight to manual selection, never an error/retry dead-end.
  void _resolve(IsoCountry country, {String? region}) {
    final suggestion = const MadhhabSuggestionService().suggest(
      explicitCountryCode: country.code,
      explicitCity: region,
    );
    setState(() {
      _suggestion = suggestion;
      _step = suggestion.isResolved
          ? _FlowStep.suggestion
          : _FlowStep.manualSelect;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _FlowStep.country:
        return _UpbringingCountryStep(
          initialValue: _country,
          onSubmit: _submitCountry,
          onBack: widget.onExitFirstStep,
        );
      case _FlowStep.region:
        return _UpbringingRegionStep(
          regions: _regionOptions,
          onSelectRegion: (region) => _resolve(_country!, region: region),
          // Part 3: the engine is explicitly allowed to return
          // insufficient evidence — "my region isn't listed" simply
          // re-resolves country-only, which (honestly) may still come up
          // unresolved for a country whose only mapping entries are
          // region-specific, routing straight to manual selection.
          onRegionNotListed: () => _resolve(_country!),
          onBack: () => setState(() => _step = _FlowStep.country),
        );
      case _FlowStep.suggestion:
        return _MadhhabGeographicSuggestionStep(
          suggestion: _suggestion!,
          onConfirm: (madhhab) =>
              widget.onSelectMadhhab(madhhab, viaSuggestion: true),
          onChooseAnother: () =>
              setState(() => _step = _FlowStep.manualSelect),
          onStillDontKnow: widget.onSelectUnknown,
        );
      case _FlowStep.manualSelect:
        return _MadhhabManualSelectStep(
          onSelectMadhhab: (madhhab) =>
              widget.onSelectMadhhab(madhhab, viaSuggestion: false),
          onSelectUnknown: widget.onSelectUnknown,
        );
    }
  }
}

/// Asks for the country she grew up in — upbringing context, not current
/// residence — a more meaningful signal for a Madhhab suggestion than
/// where she lives today. The country field itself is a tappable summary
/// that opens a polished searchable modal sheet ([_CountryPickerSheet])
/// rather than an inline list, and can be reopened at any time to change
/// the answer without navigating backward through the flow.
class _UpbringingCountryStep extends StatefulWidget {
  const _UpbringingCountryStep({
    required this.initialValue,
    required this.onSubmit,
    required this.onBack,
  });
  final IsoCountry? initialValue;
  final ValueChanged<IsoCountry> onSubmit;
  final VoidCallback onBack;
  @override
  State<_UpbringingCountryStep> createState() => _UpbringingCountryStepState();
}

class _UpbringingCountryStepState extends State<_UpbringingCountryStep> {
  late IsoCountry? _selected = widget.initialValue;

  Future<void> _openPicker() async {
    final result = await showModalBottomSheet<IsoCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.onboardingSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CountryPickerSheet(initialSelected: _selected),
    );
    if (result != null && mounted) setState(() => _selected = result);
  }

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    final selected = _selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(
          _tr(
            'Which country did you grow up in for most of your childhood?',
            'ما هي الدولة التي وُلدتِ وعشتِ فيها معظم سنوات نشأتك؟',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _tr(
            'This helps us suggest the Madhhab most likely associated with '
                'the context you grew up in. You can always change it '
                'later.',
            'يساعدنا ذلك في اقتراح المذهب الأقرب للسياق الذي نشأتِ فيه، '
                'ويمكنك تغييره دائمًا.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.onboardingSecondaryText,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 22),
        InkWell(
          onTap: _openPicker,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.onboardingSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.onboardingBorder),
            ),
            child: Row(
              children: [
                if (selected != null) ...[
                  Text(
                    isoFlagEmoji(selected.code),
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    selected == null
                        ? _tr('Select country', 'اختيار الدولة')
                        : (arabic ? selected.nameAr : selected.nameEn),
                    style: TextStyle(
                      color: selected == null
                          ? AppColors.onboardingSecondaryText
                          : AppColors.onboardingPrimaryText,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Icon(
                  Icons.unfold_more_rounded,
                  color: AppColors.onboardingSecondaryText,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        _Continue(
          onPressed: selected == null ? null : () => widget.onSubmit(selected),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: widget.onBack, child: Text(_tr('Back', 'رجوع'))),
      ],
    );
  }
}

/// Only ever shown for a country whose reviewed mapping has more than one
/// region-level entry (today, only India/Kerala) — a plain list of the
/// candidate regions, plus an honest "my region isn't listed" escape that
/// never blocks her.
class _UpbringingRegionStep extends StatelessWidget {
  const _UpbringingRegionStep({
    required this.regions,
    required this.onSelectRegion,
    required this.onRegionNotListed,
    required this.onBack,
  });
  final List<String> regions;
  final ValueChanged<String> onSelectRegion;
  final VoidCallback onRegionNotListed;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Which region did you grow up in?', 'في أي منطقة نشأتِ؟')),
      const SizedBox(height: 8),
      Text(
        _tr(
          'This region has more than one common Madhhab, so narrowing it '
              'down helps us suggest more accurately.',
          'لهذه المنطقة أكثر من مذهب شائع، لذا فإن تحديدها يساعدنا على '
              'اقتراح أدق.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onboardingSecondaryText,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 22),
      for (final region in regions)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onSelectRegion(region),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(region),
            ),
          ),
        ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: onRegionNotListed,
        child: Text(_tr('My region isn\'t listed', 'منطقتي غير مدرجة')),
      ),
      const SizedBox(height: 10),
      TextButton(onPressed: onBack, child: Text(_tr('Back', 'رجوع'))),
    ],
  );
}

/// The polished searchable country picker, reused anywhere a country
/// needs picking from [kIsoCountries] — no duplicate country dataset.
/// Search matches Arabic name, English name, or ISO code (e.g.
/// "السعودية" / "Saudi Arabia" / "SA" all find the same entry). No
/// preselected/recommended shortlist — the full alphabetical list is
/// shown until she searches.
class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.initialSelected});
  final IsoCountry? initialSelected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
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
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? kIsoCountries
        : kIsoCountries
              .where(
                (c) =>
                    c.nameEn.toLowerCase().contains(query) ||
                    c.nameAr.contains(_query.trim()) ||
                    c.code.toLowerCase() == query,
              )
              .toList();
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.onboardingBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                textAlign: TextAlign.start,
                decoration: InputDecoration(
                  hintText: _tr('Search for a country', 'ابحثي عن الدولة'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.onboardingBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.onboardingBorder,
                    ),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _tr('No countries found', 'لا توجد نتائج'),
                        style: const TextStyle(
                          color: AppColors.onboardingSecondaryText,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final country = filtered[index];
                        final isSelected = country == widget.initialSelected;
                        return ListTile(
                          leading: Text(
                            isoFlagEmoji(country.code),
                            style: const TextStyle(fontSize: 22),
                          ),
                          title: Text(arabic ? country.nameAr : country.nameEn),
                          selected: isSelected,
                          selectedTileColor: AppColors.onboardingSelectedBg,
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.onboardingAccent,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(country),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converts an ISO 3166-1 alpha-2 code to its flag emoji via Unicode
/// Regional Indicator Symbols (U+1F1E6 = 'A') — no separate flag dataset
/// needed alongside [kIsoCountries].
String isoFlagEmoji(String isoCode) {
  if (isoCode.length != 2) return '';
  const base = 0x1F1E6;
  final chars = isoCode.toUpperCase().codeUnits.map((c) {
    final offset = c - 'A'.codeUnitAt(0);
    if (offset < 0 || offset > 25) return null;
    return String.fromCharCode(base + offset);
  });
  if (chars.any((c) => c == null)) return '';
  return chars.join();
}

/// Shows an APPROVED geographic suggestion and requires an explicit
/// confirmation per school before it ever becomes a selected state — never
/// a declaration on its own. Only ever reached when [suggestion.isResolved]
/// — an unresolved suggestion routes straight to [_MadhhabManualSelectStep]
/// instead, so this widget has no error/dead-end branch.
class _MadhhabGeographicSuggestionStep extends StatelessWidget {
  const _MadhhabGeographicSuggestionStep({
    required this.suggestion,
    required this.onConfirm,
    required this.onChooseAnother,
    required this.onStillDontKnow,
  });
  final MadhhabSuggestion suggestion;
  final ValueChanged<Madhhab> onConfirm;
  final VoidCallback onChooseAnother;
  final VoidCallback onStillDontKnow;

  static String _madhhabName(Madhhab madhhab) => switch (madhhab) {
    Madhhab.hanafi => _tr('Hanafi', 'الحنفي'),
    Madhhab.maliki => _tr('Maliki', 'المالكي'),
    Madhhab.shafii => _tr("Shafi'i", 'الشافعي'),
    Madhhab.hanbali => _tr('Hanbali', 'الحنبلي'),
  };

  /// Governance model (Knowledge-Base Source-Verification wave,
  /// 2026-10-13): wording must never claim certainty, and must read
  /// identically regardless of whether [suggestion.evidenceStatus] is
  /// `'SOURCE_VERIFIED'` (independently checked against real public
  /// sources) or `'SCHOLAR_REVIEWED'` (an actual qualified scholar's
  /// sign-off) — the tier of trust behind a suggestion is an internal
  /// data-quality distinction, never surfaced to the user as a stronger
  /// or weaker certainty claim either way.
  String _headline() {
    if (suggestion.likelyMadhahib.length == 1) {
      final name = _madhhabName(suggestion.likelyMadhahib.single);
      return _tr(
        'Based on the country where you grew up, $name may be the '
            'closest fit.',
        'بناءً على البلد الذي نشأتِ فيه، قد يكون المذهب $name هو الأقرب.',
      );
    }
    return _tr(
      'Based on the country where you grew up, these Madhahib may be '
          'the closest fit:',
      'بناءً على البلد الذي نشأتِ فيه، قد تكون هذه المذاهب هي الأقرب:',
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(suggestion.isResolved, 'reached with an unresolved suggestion');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(_headline()),
        const SizedBox(height: 8),
        Text(
          _tr(
            'This is a suggestion based on available sources — you can '
                'choose another Madhhab, or choose "I don\'t know".',
            'هذا اقتراح مبني على المصادر المتاحة، ويمكنك اختيار مذهب آخر '
                'أو اختيار "لا أعرف".',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.onboardingSecondaryText,
            fontSize: 12,
          ),
        ),
        if (suggestion.regionNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              suggestion.regionNote!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onboardingSecondaryText,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 16),
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
                    'Use ${_madhhabName(madhhab)}',
                    'استخدام ${_madhhabName(madhhab)}',
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onChooseAnother,
          child: Text(_tr('Choose another Madhhab', 'اختيار مذهب آخر')),
        ),
        TextButton(
          onPressed: onStillDontKnow,
          child: Text(_tr('I still don\'t know', 'ما زلت لا أعرف')),
        ),
      ],
    );
  }
}

/// The honest "no suggestion available" landing — reached when the
/// selected country (or region) has no APPROVED mapping entry. The
/// country selection itself always succeeded; only the recommendation is
/// unavailable, so this is never framed as an error and never offers a
/// "try again" — it goes straight to the same shared [MadhhabSelector]
/// grid every direct-pick entry point uses. Every caller of this flow
/// already guarantees [MadhhabSelectionState.unset] or
/// [MadhhabSelectionState.unknown] (never [MadhhabSelectionState.selected])
/// before reaching here, so the grid never needs to reflect/highlight an
/// existing choice.
class _MadhhabManualSelectStep extends StatelessWidget {
  const _MadhhabManualSelectStep({
    required this.onSelectMadhhab,
    required this.onSelectUnknown,
  });
  final ValueChanged<Madhhab> onSelectMadhhab;
  final VoidCallback onSelectUnknown;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(
        _tr('Choose the Madhhab you follow', 'اختاري المذهب الذي تتبعينه'),
      ),
      const SizedBox(height: 8),
      Text(
        _tr(
          'You can choose your own Madhhab, or choose "I don\'t know".',
          'يمكنك اختيار مذهبك بنفسك أو اختيار "لا أعرف".',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onboardingSecondaryText,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 24),
      MadhhabSelector(
        state: MadhhabSelectionState.unset,
        selected: null,
        onSelectMadhhab: onSelectMadhhab,
        onSelectUnknown: onSelectUnknown,
      ),
    ],
  );
}

/// Local copies of onboarding's own `_Title`/`_Continue` presentational
/// wrappers — same `AppColors.onboarding*` tokens, so the visual result is
/// identical, without making onboarding_screen.dart's private widgets
/// importable from here (Dart's `_`-prefix is file-private, not just
/// name-mangled) or relocating 40+ unrelated call sites in that file to
/// use a newly-public version.
class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
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
  const _Continue({required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.onboardingPrimaryAction.withValues(
                    alpha: 0.35,
                  ),
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
          backgroundColor: AppColors.onboardingPrimaryAction,
          disabledBackgroundColor: AppColors.onboardingDisabled,
          disabledForegroundColor: AppColors.onboardingSecondaryText,
          elevation: enabled ? 2 : 0,
          shadowColor: AppColors.onboardingPrimaryAction.withValues(
            alpha: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _tr('Continue', 'متابعة'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: enabled ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}

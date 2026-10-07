import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../domain/madhhab_descriptions.dart';

/// The single, shared Madhhab picker grid — Requirement 1/5's "one
/// consistent component and one consistent source of truth," replacing
/// the three independent implementations previously hand-rolled in
/// onboarding, Settings, and the resolution screen. Reuses the tile
/// layout from Settings' former `_MadhhabGrid` (Stack + FittedBox
/// (scaleDown) + PositionedDirectional check icon), the only one of the
/// three that had already been fixed for 200%-text-scale overflow.
class MadhhabSelector extends StatelessWidget {
  const MadhhabSelector({
    required this.state,
    required this.selected,
    required this.onSelectMadhhab,
    required this.onSelectUnknown,
    this.suggested,
    this.onLearnMore,
    super.key,
  });

  final MadhhabSelectionState state;

  /// Non-null only when [state] is [MadhhabSelectionState.selected].
  final Madhhab? selected;
  final ValueChanged<Madhhab> onSelectMadhhab;
  final VoidCallback onSelectUnknown;

  /// A madhhab suggested based on the user's country (Requirement 6).
  /// Rendered as a small eyebrow label on that tile only — the tile stays
  /// a normal, fully-tappable option, never pre-selected and never
  /// visually locked, so a suggestion is never mistaken for a
  /// determination.
  final Madhhab? suggested;

  /// Optional "ⓘ" affordance opening a short bottom sheet with the
  /// madhhab's [MadhhabDescription.longNoteEn]/[longNoteAr] — keeps the
  /// grid itself free of jurisprudential jargon by default.
  final ValueChanged<Madhhab>? onLearnMore;

  bool get _unknownSelected => state == MadhhabSelectionState.unknown;

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    final descriptions = kMadhhabDisplayOrder.map(describeMadhhab).toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: descriptions.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 122,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        if (index == descriptions.length) {
          return _Tile(
            name: arabic ? kUnknownMadhhabLabelAr : kUnknownMadhhabLabelEn,
            rule: '',
            active: _unknownSelected,
            onTap: onSelectUnknown,
          );
        }
        final description = descriptions[index];
        final isSuggested = suggested == description.madhhab;
        return _Tile(
          name: arabic ? description.nameAr : description.nameEn,
          rule: arabic ? description.shortRuleAr : description.shortRuleEn,
          active: state == MadhhabSelectionState.selected &&
              selected == description.madhhab,
          suggestedLabel: isSuggested
              ? (arabic
                    ? 'المذهب المقترح بناءً على بلدك'
                    : 'Madhhab suggested based on your country')
              : null,
          onLearnMore: onLearnMore == null
              ? null
              : () => onLearnMore!(description.madhhab),
          onTap: () => onSelectMadhhab(description.madhhab),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.name,
    required this.rule,
    required this.active,
    required this.onTap,
    this.suggestedLabel,
    this.onLearnMore,
  });

  final String name;
  final String rule;
  final bool active;
  final VoidCallback onTap;
  final String? suggestedLabel;
  final VoidCallback? onLearnMore;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: rule.isEmpty ? name : '$name, $rule',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF1F2) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: active ? const Color(0xFFFFCDD5) : AppColors.shadowColor,
            ),
          ),
          child: Stack(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.topStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (suggestedLabel != null) ...[
                      Text(
                        suggestedLabel!,
                        style: const TextStyle(
                          color: AppColors.brandSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      name,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF881337)
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (rule.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        rule,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (active)
                const PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: Icon(
                    Icons.check_rounded,
                    color: AppColors.brandSecondary,
                    size: 17,
                  ),
                ),
              if (onLearnMore != null)
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: GestureDetector(
                    onTap: onLearnMore,
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.textTertiary,
                      size: 15,
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

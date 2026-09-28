import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/evidence_provenance.dart';

/// F7 — the one shared widget every provenance-aware surface uses to
/// show which [EvidenceProvenance] class a value belongs to. Always
/// icon + text, never color alone, so the distinction survives
/// grayscale/color-blind rendering and reaches a screen reader via
/// [Semantics.label] built from the long-form sentence, not just the
/// short chip text.
///
/// [FittedBox]-wrapped so the badge shrinks rather than overflows at
/// 200% text scale — the charter's explicit accessibility bar — instead
/// of clipping or wrapping the parent row.
class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge({
    super.key,
    required this.provenance,
    this.dense = false,
  });

  final EvidenceProvenance provenance;

  /// A smaller variant for tight contexts (calendar day cells) — still
  /// icon + text, never icon-only, since an icon alone is not
  /// necessarily distinguishable at a glance without the label.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    final color = _colorFor(provenance);
    final child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: provenance.isTentative ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(dense ? 6 : 8),
        border: Border.all(
          color: color.withValues(alpha: provenance.isTentative ? 0.5 : 0.9),
          style: provenance == EvidenceProvenance.predicted
              ? BorderStyle.none
              : BorderStyle.solid,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(provenance.icon, size: dense ? 10 : 13, color: color),
          SizedBox(width: dense ? 3 : 5),
          Flexible(
            child: Text(
              provenance.shortLabel(arabic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: dense ? 8 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: provenance.longLabel(arabic),
      excludeSemantics: true,
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
  }

  static Color _colorFor(EvidenceProvenance provenance) => switch (provenance) {
    EvidenceProvenance.userObserved => AppColors.tahara,
    EvidenceProvenance.userReportedHistorical => AppColors.info,
    EvidenceProvenance.userReportedEstimate => AppColors.istihadah,
    EvidenceProvenance.predicted => AppColors.textSecondary,
    EvidenceProvenance.legacyUnverified => AppColors.warning,
    EvidenceProvenance.missingUncertain => AppColors.textTertiary,
  };
}

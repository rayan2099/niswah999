import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/evidence_provenance.dart';
import 'correction_sheet.dart';
import 'daily_checkin_sheet.dart' show showBackfillObservationSheet;
import 'provenance_badge.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

String _flowLabel(ObservationFlow flow) => switch (flow) {
  ObservationFlow.uncertain => _t("I'm not sure", 'لست متأكدة'),
  ObservationFlow.none => _t('None', 'لا يوجد'),
  ObservationFlow.spotting => _t('Spotting', 'تبقيع'),
  ObservationFlow.light => _t('Light', 'خفيف'),
  ObservationFlow.medium => _t('Medium', 'متوسط'),
  ObservationFlow.heavy => _t('Heavy', 'غزير'),
};

/// F8 — the canonical calendar's "tap a date to inspect it" surface.
/// Shows every observation reported for [day] (Commit D2: multiple
/// same-day observations are a deliberate, preserved feature — never
/// collapsed here), which one is the effective (current) value, and
/// which are superseded revisions still visible for [revision history]
/// inspection. Offers correcting the current value and backfilling a
/// missing one, reusing the app's own existing, already-hardened
/// [showCorrectObservationSheet]/[showBackfillObservationSheet] flows
/// rather than a second, parallel write path.
///
/// Returns true if the caller should reload canonical data from the
/// server — never assumes the legacy projection will reflect the
/// change.
Future<bool> showObservationDetailSheet(
  BuildContext context, {
  required DateTime day,
  required BleedingEpisode? episodeForDay,
  required List<BleedingObservation> observationsForDay,
  required BleedingEpisodeRepositoryImpl repository,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ObservationDetailSheet(
      day: day,
      episodeForDay: episodeForDay,
      observationsForDay: observationsForDay,
    ),
  );
  return result ?? false;
}

class _ObservationDetailSheet extends StatelessWidget {
  const _ObservationDetailSheet({
    required this.day,
    required this.episodeForDay,
    required this.observationsForDay,
  });

  final DateTime day;
  final BleedingEpisode? episodeForDay;
  final List<BleedingObservation> observationsForDay;

  bool get _arabic => AppLocaleController.instance.isArabic;

  BleedingObservation? get _effective {
    final supersededIds = observationsForDay
        .map((o) => o.supersedesId)
        .whereType<String>()
        .toSet();
    return observationsForDay
        .where((o) => !supersededIds.contains(o.id))
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final effective = _effective;
    // Oldest first, so the chain reads as a real history — the
    // original report, then each correction after it.
    final chain = [...observationsForDay]
      ..sort((a, b) {
        final at = a.reportedAt ?? a.observedDate;
        final bt = b.reportedAt ?? b.observedDate;
        return at.compareTo(bt);
      });

    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 20,
            end: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDate(day, _arabic),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: AppTypography.serifFamily,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (chain.isEmpty)
                  _EmptyDayNotice(hasEpisode: episodeForDay != null)
                else ...[
                  if (chain.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _t(
                          'Revision history — oldest first',
                          'سجل التعديلات — الأقدم أولاً',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  for (final observation in chain)
                    _ObservationTile(
                      observation: observation,
                      isEffective: observation.id == effective?.id,
                    ),
                ],
                const SizedBox(height: 20),
                if (effective != null)
                  FilledButton.icon(
                    onPressed: () async {
                      final saved = await showCorrectObservationSheet(
                        context,
                        target: effective,
                      );
                      if (context.mounted && saved) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(_t('Correct this entry', 'تصحيح هذا الإدخال')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppColors.tahara,
                    ),
                  )
                else if (episodeForDay != null)
                  FilledButton.icon(
                    onPressed: () async {
                      final saved = await showBackfillObservationSheet(
                        context,
                        episodeId: episodeForDay!.id!,
                        episodeStartDate: episodeForDay!.startDate,
                        initialDate: day,
                      );
                      if (context.mounted && saved) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(_t('Add missing entry', 'إضافة إدخال مفقود')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppColors.tahara,
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_t('Close', 'إغلاق')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime day, bool arabic) {
    const monthsEn = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const monthsAr = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final month = arabic ? monthsAr[day.month - 1] : monthsEn[day.month - 1];
    return arabic
        ? '${day.day} $month ${day.year}'
        : '$month ${day.day}, ${day.year}';
  }
}

class _ObservationTile extends StatelessWidget {
  const _ObservationTile({
    required this.observation,
    required this.isEffective,
  });

  final BleedingObservation observation;
  final bool isEffective;

  @override
  Widget build(BuildContext context) {
    final provenance = provenanceForObservation(observation);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEffective
            ? AppColors.tahara.withValues(alpha: 0.06)
            : AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEffective
              ? AppColors.tahara.withValues(alpha: 0.4)
              : AppColors.shadowColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _flowLabel(observation.flow),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: isEffective
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                    color: isEffective
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              if (isEffective)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tahara,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _t('Current', 'الحالي'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Text(
                  _t('Superseded', 'مُستبدَل'),
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ProvenanceBadge(provenance: provenance, dense: true),
          if (observation.notes != null && observation.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              observation.notes!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyDayNotice extends StatelessWidget {
  const _EmptyDayNotice({required this.hasEpisode});
  final bool hasEpisode;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceHover,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        const Icon(Icons.event_note_outlined, color: AppColors.textSecondary),
        const SizedBox(height: 8),
        Text(
          hasEpisode
              ? _t(
                  'No entry recorded for this day yet.',
                  'لا يوجد إدخال مسجَّل لهذا اليوم بعد.',
                )
              : _t(
                  "This day isn't part of any recorded period. If bleeding "
                      'started here, use "Start Bleeding" from the '
                      'dashboard.',
                  'هذا اليوم ليس جزءاً من أي دورة مسجَّلة. إذا بدأ النزيف '
                      'هنا فعلاً، استخدمي "بدأ الحيض" من الشاشة الرئيسية.',
                ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/episode_correction_repository.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/evidence_provenance.dart';
import 'correction_sheet.dart';
import 'daily_checkin_sheet.dart' show showBackfillObservationSheet;
import 'episode_edit_sheet.dart';
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
///
/// [supersededElsewhere] holds the ids superseded by a correction dated on
/// another day (a moved period end corrects the old closing entry from the
/// new date), so such an entry is never offered as this day's current
/// value. [isLatestEpisode]/[hasOpenEpisode] decide whether "I'm still
/// bleeding" (undo an end) is offered in the period editor, and
/// [onEpisodeChanged] runs after every saved period edit, including an
/// Undo tapped after the sheets closed.
///
/// PT-055: the current entry of a day can be deleted (with Undo), except
/// the start entry of a period and the end entry of an ended one, which
/// are changed through "Edit this period" instead.
Future<bool> showObservationDetailSheet(
  BuildContext context, {
  required DateTime day,
  required BleedingEpisode? episodeForDay,
  required List<BleedingObservation> observationsForDay,
  required BleedingEpisodeRepositoryImpl repository,
  Set<String> supersededElsewhere = const {},
  bool isLatestEpisode = false,
  bool hasOpenEpisode = false,
  VoidCallback? onEpisodeChanged,
  @visibleForTesting EpisodeCorrectionRepository? correctionsOverride,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ObservationDetailSheet(
      messenger: messenger,
      corrections:
          correctionsOverride ??
          EpisodeCorrectionRepository(episodes: repository),
      day: day,
      episodeForDay: episodeForDay,
      observationsForDay: observationsForDay,
      supersededElsewhere: supersededElsewhere,
      isLatestEpisode: isLatestEpisode,
      hasOpenEpisode: hasOpenEpisode,
      onEpisodeChanged: onEpisodeChanged,
      repository: repository,
    ),
  );
  return result ?? false;
}

class _ObservationDetailSheet extends StatelessWidget {
  const _ObservationDetailSheet({
    required this.day,
    required this.episodeForDay,
    required this.observationsForDay,
    required this.supersededElsewhere,
    required this.isLatestEpisode,
    required this.hasOpenEpisode,
    required this.repository,
    required this.corrections,
    this.messenger,
    this.onEpisodeChanged,
  });

  final DateTime day;
  final BleedingEpisode? episodeForDay;
  final List<BleedingObservation> observationsForDay;
  final Set<String> supersededElsewhere;
  final bool isLatestEpisode;
  final bool hasOpenEpisode;
  final BleedingEpisodeRepositoryImpl repository;
  final EpisodeCorrectionRepository corrections;
  final ScaffoldMessengerState? messenger;
  final VoidCallback? onEpisodeChanged;

  bool get _arabic => AppLocaleController.instance.isArabic;

  BleedingObservation? get _effective {
    final supersededIds = {
      ...supersededElsewhere,
      ...observationsForDay.map((o) => o.supersedesId).whereType<String>(),
    };
    return observationsForDay
        .where((o) => !supersededIds.contains(o.id))
        .firstOrNull;
  }

  /// The entries a period cannot lose on their own: its start entry, and
  /// the closing "no bleeding" entry of an ended period.
  bool _isProtected(BleedingObservation entry) {
    final episode = episodeForDay;
    if (episode == null) return false;
    final sameDay = DateUtils.isSameDay;
    if (sameDay(entry.observedDate, episode.startDate) &&
        entry.flow != ObservationFlow.none) {
      return true;
    }
    return episode.lifecycleStatus == LifecycleStatus.ended &&
        entry.flow == ObservationFlow.none &&
        episode.endDate != null &&
        sameDay(entry.observedDate, episode.endDate!);
  }

  static String _failureMessage(EpisodeEditResult result) =>
      switch (result.status) {
        EpisodeEditStatus.offline => _t(
          "You're offline, so nothing was changed. Connect to the internet "
              'and try again.',
          'أنتِ غير متصلة بالإنترنت، لذلك لم يتغير شيء. اتصلي بالإنترنت '
              'وحاولي مرة أخرى.',
        ),
        EpisodeEditStatus.changedElsewhere => _t(
          'This period was changed on another device. Close this and open '
              'the day again.',
          'تم تعديل هذا الحيض من جهاز آخر. أغلقي هذه النافذة وافتحي اليوم '
              'مرة أخرى.',
        ),
        _ when (result.serverMessage ?? '').contains('newer entry') => _t(
          'A newer entry was added for that day, so the deleted one was not '
              'put back.',
          'أُضيف إدخال أحدث لذلك اليوم، لذلك لم يُستعد الإدخال المحذوف.',
        ),
        _ => _t(
          "This entry couldn't be deleted. Your records are unchanged.",
          'تعذّر حذف هذا الإدخال. سجلاتكِ لم تتغير.',
        ),
      };

  Future<void> _confirmAndRemove(
    BuildContext context,
    BleedingObservation entry,
  ) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(_t('Delete this entry?', 'حذف هذا الإدخال؟')),
          content: Text(
            _t(
              'This day will show as not recorded. The rest of the period '
                  'stays as it is. You can undo this right after.',
              'سيظهر هذا اليوم كغير مسجَّل، ويبقى باقي الحيض كما هو. '
                  'يمكنكِ التراجع مباشرة بعد الحذف.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t('Cancel', 'إلغاء')),
            ),
            TextButton(
              key: const Key('observation-detail-confirm-remove'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t('Delete', 'حذف')),
            ),
          ],
        ),
      ),
    );
    if (agreed != true || !context.mounted) return;

    final episodeId = episodeForDay!.id!;
    final result = await corrections.removeObservation(
      clientOperationId: const Uuid().v4(),
      episodeId: episodeId,
      observationId: entry.id!,
      revisionToken: episodeForDay!.revisionToken,
    );
    if (!result.saved) {
      messenger?.showSnackBar(
        SnackBar(
          key: const Key('observation-detail-remove-message'),
          content: Text(_failureMessage(result)),
        ),
      );
      return;
    }
    if (context.mounted) Navigator.of(context).pop(true);
    onEpisodeChanged?.call();
    final undoOperationId = const Uuid().v4();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('observation-detail-removed-snackbar'),
        content: Text(_t('Entry deleted.', 'تم حذف الإدخال.')),
        action: SnackBarAction(
          label: _t('Undo', 'تراجع'),
          onPressed: () async {
            final undone = await corrections.restoreObservation(
              clientOperationId: undoOperationId,
              episodeId: episodeId,
              removalRevisionId: result.revisionId!,
            );
            if (undone.saved) {
              onEpisodeChanged?.call();
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(_t('Entry restored.', 'تمت استعادة الإدخال.')),
                ),
              );
            } else {
              messenger?.showSnackBar(
                SnackBar(content: Text(_failureMessage(undone))),
              );
            }
          },
        ),
      ),
    );
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
                        episode: episodeForDay,
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
                // Logging/sync hardening (proposed): a NEW fact can only be
                // added to an OPEN episode — record_bleeding_observation
                // deterministically rejects an ended one, so offering
                // "Add missing entry" there could only ever fail.
                else if (episodeForDay?.lifecycleStatus == LifecycleStatus.open)
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
                if (effective?.id != null && episodeForDay?.id != null) ...[
                  const SizedBox(height: 8),
                  if (_isProtected(effective!))
                    Text(
                      key: const Key('observation-detail-protected-hint'),
                      effective.flow == ObservationFlow.none
                          ? _t(
                              "This is the period's end. To change it, use "
                                  '"Edit this period".',
                              'هذا هو نهاية الحيض. لتغييره استخدمي "تعديل '
                                  'هذا الحيض".',
                            )
                          : _t(
                              "This is the period's first day. To change it, "
                                  'use "Edit this period".',
                              'هذا هو أول يوم في الحيض. لتغييره استخدمي '
                                  '"تعديل هذا الحيض".',
                            ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    )
                  else
                    TextButton.icon(
                      key: const Key('observation-detail-remove-entry'),
                      onPressed: () => _confirmAndRemove(context, effective),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(_t('Delete this entry', 'حذف هذا الإدخال')),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                    ),
                ],
                if (episodeForDay?.id != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('observation-detail-edit-period'),
                    onPressed: () async {
                      final action = await showEpisodeEditSheet(
                        context,
                        episode: episodeForDay!,
                        isLatestEpisode: isLatestEpisode,
                        hasOpenEpisode: hasOpenEpisode,
                        onChanged: onEpisodeChanged,
                        episodes: repository,
                      );
                      if (context.mounted && action != null) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(_t('Edit this period', 'تعديل هذا الحيض')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
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

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/evidence_provenance.dart';
import '../../domain/entities/load_result.dart';
import '../widgets/cycle_calendar.dart' show hijriMonthLabel;
import '../widgets/observation_detail_sheet.dart';
import '../widgets/provenance_badge.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// F8 — the canonical month-grid calendar. Unlike [CycleCalendar] (which
/// still reads the legacy, one-row-per-day `cycle_entries`/[CycleLog]
/// projection), every marker here is derived directly from
/// `bleeding_episodes`/effective `bleeding_observations` — [source of
/// truth] required by the charter. `cycle_entries` is never read here.
///
/// [repositoryOverride]/[userIdOverride] mirror [DashboardScreen]'s own
/// established test-injection pattern, so widget tests can supply
/// genuine canonical evidence without a real Supabase backend.
class CanonicalCalendarScreen extends StatefulWidget {
  const CanonicalCalendarScreen({
    super.key,
    this.repositoryOverride,
    this.userIdOverride,
  });

  final BleedingEpisodeRepositoryImpl? repositoryOverride;
  final String? userIdOverride;

  @override
  State<CanonicalCalendarScreen> createState() =>
      _CanonicalCalendarScreenState();
}

class _CanonicalCalendarScreenState extends State<CanonicalCalendarScreen> {
  late final BleedingEpisodeRepositoryImpl _repository =
      widget.repositoryOverride ?? BleedingEpisodeRepositoryImpl();
  late final String? _userId =
      widget.userIdOverride ??
      NiswahSupabase.clientOrNull?.auth.currentUser?.id;

  late DateTime _month = DateTime(AppClock.now().year, AppClock.now().month);
  bool _loading = true;
  bool _episodesUnavailable = false;
  bool _observationsUnavailable = false;
  List<BleedingEpisode> _episodes = const [];
  List<BleedingObservation> _observations = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final episodesResult = await _repository.getEpisodesForUser(userId);
    final observationsResult = await _repository.getAllObservationsForUser(
      userId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _episodesUnavailable =
          episodesResult is LoadUnavailable<List<BleedingEpisode>>;
      _observationsUnavailable =
          observationsResult is LoadUnavailable<List<BleedingObservation>>;
      _episodes = episodesResult.dataOrNull ?? const [];
      _observations = observationsResult.dataOrNull ?? const [];
    });
  }

  void _changeMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Future<void> _pickMonth() async {
    final now = AppClock.now();
    final firstDate = DateTime(now.year - 100, now.month);
    final lastDate = DateTime(now.year, now.month);
    var initialDate = _month;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: _t('Select month', 'اختاري الشهر'),
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
  }

  Future<void> _onDayTap(DateTime day, _DayEvidence evidence) async {
    final refreshNeeded = await showObservationDetailSheet(
      context,
      day: day,
      episodeForDay: evidence.episode,
      observationsForDay: evidence.rawObservations,
      repository: _repository,
    );
    // A successful save must be visible in the calendar without relying
    // on the legacy projection — re-fetching canonical data directly is
    // exactly that guarantee.
    if (refreshNeeded && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(_t('Cycle calendar', 'تقويم الدورة')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: NiswahLoadingIndicator(size: NiswahLoadingSize.large),
                )
              : _episodesUnavailable
              ? _UnavailableCard(onRetry: _load)
              : RefreshIndicator(
                  color: AppColors.tahara,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      _MonthHeader(
                        month: _month,
                        onPrevious: () => _changeMonth(-1),
                        onNext: () => _changeMonth(1),
                        onTapLabel: _pickMonth,
                      ),
                      const SizedBox(height: 12),
                      if (_observationsUnavailable)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DegradedNotice(onRetry: _load),
                        ),
                      _CanonicalMonthGrid(
                        month: _month,
                        episodes: _episodes,
                        observations: _observations,
                        onDayTap: _onDayTap,
                      ),
                      const SizedBox(height: 20),
                      _Legend(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onTapLabel,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTapLabel;

  static const _monthNamesEn = [
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
  static const _monthNamesAr = [
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

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    final gregorianLabel =
        '${arabic ? _monthNamesAr[month.month - 1] : _monthNamesEn[month.month - 1]} ${month.year}';
    final hijriLabel = hijriMonthLabel(DateTime(month.year, month.month, 15));
    return Row(
      children: [
        Semantics(
          button: true,
          label: _t('Previous month', 'الشهر السابق'),
          child: IconButton(
            onPressed: onPrevious,
            icon: Icon(
              arabic ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: onTapLabel,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    gregorianLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldInk,
                    ),
                  ),
                  Text(
                    hijriLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: _t('Next month', 'الشهر التالي'),
          child: IconButton(
            onPressed: onNext,
            icon: Icon(
              arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

/// One calendar day's fully-resolved canonical evidence — computed once
/// per grid build, shared by the day cell's visual marker and the
/// detail sheet a tap opens.
class _DayEvidence {
  const _DayEvidence({
    required this.provenance,
    required this.hasBleeding,
    required this.isCorrected,
    required this.episode,
    required this.rawObservations,
  });

  final EvidenceProvenance? provenance;
  final bool hasBleeding;
  final bool isCorrected;
  final BleedingEpisode? episode;
  final List<BleedingObservation> rawObservations;
}

class _CanonicalMonthGrid extends StatelessWidget {
  const _CanonicalMonthGrid({
    required this.month,
    required this.episodes,
    required this.observations,
    required this.onDayTap,
  });

  final DateTime month;
  final List<BleedingEpisode> episodes;
  final List<BleedingObservation> observations;
  final void Function(DateTime day, _DayEvidence evidence) onDayTap;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(month.year, month.month);
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday % 7),
    );
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final dayCount = (((monthStart.weekday % 7) + daysInMonth) / 7).ceil() * 7;
    final arabic = AppLocaleController.instance.isArabic;
    final today = DateUtils.dateOnly(AppClock.now());

    final effectiveByDay = _effectiveByDay(observations);
    final prediction = _predictNextEpisode(episodes);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.shadowColor),
      ),
      child: Column(
        children: [
          GridView.builder(
            itemCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemBuilder: (context, index) => Center(
              child: Text(
                (arabic
                    ? const ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س']
                    : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])[index],
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            itemCount: dayCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 2,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final date = gridStart.add(Duration(days: index));
              final dayKey = DateTime(date.year, date.month, date.day);
              final rawForDay = observations
                  .where((o) => DateUtils.isSameDay(o.observedDate, dayKey))
                  .toList();
              final effective = effectiveByDay[dayKey];
              // Never treats a future day as "within" an open episode for
              // backfill-eligibility purposes — [showBackfillObservationSheet]'s
              // own date picker caps at "now," so offering its action on a
              // future day here would open a sheet whose initial date is
              // already out of that picker's own bounds (future-date
              // rejection must hold everywhere, not just inside the sheet).
              final episodeForDay = episodes
                  .where(
                    (e) =>
                        !dayKey.isBefore(DateUtils.dateOnly(e.startDate)) &&
                        !dayKey.isAfter(DateUtils.dateOnly(today)) &&
                        (e.endDate == null ||
                            !dayKey.isAfter(DateUtils.dateOnly(e.endDate!))),
                  )
                  .firstOrNull;

              final _DayEvidence evidence;
              if (effective != null) {
                evidence = _DayEvidence(
                  provenance: provenanceForObservation(effective),
                  hasBleeding:
                      effective.flow != ObservationFlow.none &&
                      effective.flow != ObservationFlow.uncertain,
                  isCorrected: rawForDay.length > 1,
                  episode: episodeForDay,
                  rawObservations: rawForDay,
                );
              } else if (prediction != null &&
                  !dayKey.isBefore(prediction.$1) &&
                  !dayKey.isAfter(prediction.$2)) {
                evidence = _DayEvidence(
                  provenance: EvidenceProvenance.predicted,
                  hasBleeding: true,
                  isCorrected: false,
                  episode: episodeForDay,
                  rawObservations: rawForDay,
                );
              } else {
                evidence = _DayEvidence(
                  provenance: null,
                  hasBleeding: false,
                  isCorrected: false,
                  episode: episodeForDay,
                  rawObservations: rawForDay,
                );
              }

              return _CanonicalDayCell(
                key: ValueKey('canonical-day-${dayKey.toIso8601String()}'),
                date: date,
                inMonth: date.month == month.month,
                isToday: DateUtils.isSameDay(date, AppClock.now()),
                evidence: evidence,
                onTap: () => onDayTap(dayKey, evidence),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Mirrors [CanonicalFiqhEvidenceAdapter]'s own effective-per-day
  /// policy (latest observed_time/reported_at wins) but keeps the full
  /// [BleedingObservation], not a collapsed [CycleLog] — this screen
  /// needs the real flow/provenance/notes, not the Fiqh engine's
  /// narrower shape.
  static Map<DateTime, BleedingObservation> _effectiveByDay(
    List<BleedingObservation> observations,
  ) {
    final supersededIds = observations
        .map((o) => o.supersedesId)
        .whereType<String>()
        .toSet();
    final effective = observations.where((o) => !supersededIds.contains(o.id));
    final byDay = <DateTime, BleedingObservation>{};
    for (final observation in effective) {
      final day = DateUtils.dateOnly(observation.observedDate);
      final existing = byDay[day];
      if (existing == null || _isLaterReport(observation, existing)) {
        byDay[day] = observation;
      }
    }
    return byDay;
  }

  static bool _isLaterReport(
    BleedingObservation candidate,
    BleedingObservation current,
  ) {
    final candidateTime = candidate.observedTime ?? candidate.reportedAt;
    final currentTime = current.observedTime ?? current.reportedAt;
    if (candidateTime == null || currentTime == null) return false;
    return candidateTime.isAfter(currentTime);
  }

  /// A bounded, disclosed projection only — never fabricates bleeding
  /// between two reported observations (it only ever projects forward
  /// from the last known episode, into days with no real data at all).
  /// Requires at least two ended episodes with a plausible gap (15-90
  /// days) before projecting anything, exactly like the legacy
  /// calendar's own [CycleCalendar] plausibility gate — a degenerate
  /// average must never repeat a fabricated "Expected Haid" block every
  /// few days.
  static (DateTime, DateTime)? _predictNextEpisode(
    List<BleedingEpisode> episodes,
  ) {
    final ended =
        episodes
            .where((e) => e.lifecycleStatus == LifecycleStatus.ended)
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (ended.length < 2) return null;

    final gaps = <int>[];
    for (var i = 1; i < ended.length; i++) {
      gaps.add(
        DateUtils.dateOnly(ended[i].startDate)
            .difference(DateUtils.dateOnly(ended[i - 1].startDate))
            .inDays,
      );
    }
    final averageGap = gaps.reduce((a, b) => a + b) / gaps.length;
    if (averageGap < 15 || averageGap > 90) return null;

    final durations = ended
        .map(
          (e) =>
              DateUtils.dateOnly(e.endDate!)
                  .difference(DateUtils.dateOnly(e.startDate))
                  .inDays +
              1,
        )
        .toList();
    final averageDuration =
        durations.reduce((a, b) => a + b) / durations.length;

    final last = ended.last;
    final predictedStart = DateUtils.dateOnly(last.startDate)
        .add(Duration(days: averageGap.round()));
    final predictedEnd = predictedStart.add(
      Duration(days: averageDuration.round() - 1),
    );
    // Never project over an already-open episode's own real data — that
    // would be exactly the "fabricate bleeding between two reported
    // observations" failure mode the charter prohibits.
    final hasOpen = episodes.any(
      (e) => e.lifecycleStatus == LifecycleStatus.open,
    );
    if (hasOpen) return null;
    return (predictedStart, predictedEnd);
  }
}

class _CanonicalDayCell extends StatelessWidget {
  const _CanonicalDayCell({
    super.key,
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.evidence,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final _DayEvidence evidence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    final provenance = evidence.provenance;
    final semanticsParts = <String>['${date.day}'];
    if (provenance != null && evidence.hasBleeding) {
      semanticsParts.add(provenance.longLabel(arabic));
    } else {
      semanticsParts.add(_t('No recorded bleeding', 'لا يوجد نزيف مسجَّل'));
    }
    if (evidence.isCorrected) {
      semanticsParts.add(_t('Has a correction', 'تحتوي على تصحيح'));
    }

    final fillColor = provenance == null
        ? Colors.transparent
        : provenance.isTentative
        ? AppColors.textSecondary.withValues(alpha: 0.08)
        : AppColors.haid.withValues(alpha: evidence.hasBleeding ? 1 : 0.12);
    final foreground =
        provenance != null && evidence.hasBleeding && !provenance.isTentative
        ? Colors.white
        : AppColors.textPrimary;

    return Opacity(
      opacity: inMonth ? 1 : 0.25,
      child: Semantics(
        button: true,
        label: semanticsParts.join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(
            foregroundPainter: provenance == EvidenceProvenance.predicted
                ? _DashedBorderPainter(color: AppColors.textSecondary)
                : null,
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(10),
                border: isToday
                    ? Border.all(color: AppColors.success, width: 2)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (evidence.isCorrected)
                    Icon(
                      Icons.edit_note_rounded,
                      size: 10,
                      color: foreground.withValues(alpha: 0.8),
                    )
                  else if (provenance == EvidenceProvenance.missingUncertain)
                    Icon(
                      Icons.question_mark_rounded,
                      size: 9,
                      color: foreground.withValues(alpha: 0.8),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(10),
        ).deflate(1),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      const ProvenanceBadge(provenance: EvidenceProvenance.userObserved),
      const ProvenanceBadge(
        provenance: EvidenceProvenance.userReportedHistorical,
      ),
      const ProvenanceBadge(provenance: EvidenceProvenance.predicted),
      const ProvenanceBadge(provenance: EvidenceProvenance.missingUncertain),
      const ProvenanceBadge(provenance: EvidenceProvenance.legacyUnverified),
    ],
  );
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 40,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            _t("Couldn't load your calendar", 'تعذر تحميل تقويمكِ'),
            style: const TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'Your data is safely saved — we just could not verify it '
                  'right now.',
              'بياناتكِ محفوظة بأمان — لم نتمكن فقط من التحقق منها الآن.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(onRetry()),
            child: Text(_t('Try again', 'إعادة المحاولة')),
          ),
        ],
      ),
    ),
  );
}

class _DegradedNotice extends StatelessWidget {
  const _DegradedNotice({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: AppColors.warning,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _t(
              'Some entries could not be verified right now — this month '
                  'may be incomplete.',
              'تعذر التحقق من بعض الإدخالات الآن — قد يكون هذا الشهر غير مكتمل.',
            ),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(onRetry()),
          child: Text(_t('Retry', 'إعادة')),
        ),
      ],
    ),
  );
}

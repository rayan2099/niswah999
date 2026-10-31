import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/calendar_system_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/presentation/widgets/cycle_calendar.dart'
    show hijriDateParts;
import '../../../wellbeing/presentation/wellbeing_trend_text.dart'
    show wellbeingMonthName;
import '../../domain/period_history.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// "27 أكتوبر 2026" / "15 جمادى الأولى 1448", in the calendar she chose,
/// always with English digits.
String historyDate(DateTime day, {bool withYear = true}) {
  final hijri = CalendarSystemController.instance.hijri;
  final arabic = AppLocaleController.instance.isArabic;
  final month = wellbeingMonthName(day, arabic: arabic, hijri: hijri);
  final (d, _, y) = hijri ? hijriDateParts(day) : (day.day, 0, day.year);
  return withYear ? '$d $month $y' : '$d $month';
}

/// "27 – 29 أكتوبر 2026", or both dates in full when the month differs.
String historyRange(DateTime from, DateTime to) {
  final hijri = CalendarSystemController.instance.hijri;
  final (_, fm, fy) = hijri ? hijriDateParts(from) : (0, from.month, from.year);
  final (_, tm, ty) = hijri ? hijriDateParts(to) : (0, to.month, to.year);
  if (fm == tm && fy == ty) {
    final (fd, _, _) = hijri ? hijriDateParts(from) : (from.day, 0, 0);
    return '$fd – ${historyDate(to)}';
  }
  if (fy == ty) {
    return '${historyDate(from, withYear: false)} – ${historyDate(to)}';
  }
  return '${historyDate(from)} – ${historyDate(to)}';
}

String _days(int n) => _t(
  n == 1 ? '1 day' : '$n days',
  n == 1
      ? 'يوم واحد'
      : n == 2
      ? 'يومان'
      : n <= 10
      ? '$n أيام'
      : '$n يومًا',
);

String _flowName(FlowLevel flow) => switch (flow) {
  FlowLevel.spotting => _t('spotting', 'تنقيط'),
  FlowLevel.light => _t('light bleeding', 'نزول خفيف'),
  FlowLevel.medium => _t('medium bleeding', 'نزول متوسط'),
  FlowLevel.heavy => _t('heavy bleeding', 'نزول غزير'),
  FlowLevel.none => _t('no bleeding', 'لا نزول'),
};

/// What one daily record says, in her words.
String observationDescription(HistoryObservation o) {
  if (o.isFirstCleanDay) {
    return _t(
      'bleeding stopped (first clean day)',
      'توقف النزول (أول يوم طهر)',
    );
  }
  return switch (o.kind) {
    ObservationKind.bleeding => _flowName(o.log.flow),
    ObservationKind.noBleeding => _t('No bleeding recorded', 'تسجيل بلا نزول'),
    ObservationKind.symptomsOnly => _t(
      'Symptoms or notes only',
      'أعراض أو ملاحظات فقط',
    ),
  };
}

String periodStatusLabel(PeriodItem p) => switch (p.status) {
  PeriodStatus.completed => _t('Completed', 'مكتملة'),
  PeriodStatus.ongoing => _t('Ongoing', 'مستمرة'),
  PeriodStatus.endUnknown => _t(
    'End date not recorded',
    'تاريخ النهاية غير مسجّل',
  ),
};

/// The period's dates: first to last bleeding day.
String periodDates(PeriodItem p) => switch (p.status) {
  PeriodStatus.completed =>
    p.lastBleedingDay == null
        ? historyDate(p.start)
        : historyRange(p.start, p.lastBleedingDay!),
  PeriodStatus.ongoing => _t(
    'Since ${historyDate(p.start)}',
    'منذ ${historyDate(p.start)}',
  ),
  PeriodStatus.endUnknown => _t(
    'Started ${historyDate(p.start)}',
    'بدأت ${historyDate(p.start)}',
  ),
};

/// "3 أيام نزول · طهرت في 30 أكتوبر".
String periodSummary(PeriodItem p) => switch (p.status) {
  PeriodStatus.completed =>
    p.lengthDays == null
        ? _t(
            'Clean from ${historyDate(p.firstCleanDay!, withYear: false)}',
            'طهرت في ${historyDate(p.firstCleanDay!, withYear: false)}',
          )
        : _t(
            '${_days(p.lengthDays!)} of bleeding · clean from ${historyDate(p.firstCleanDay!, withYear: false)}',
            '${_days(p.lengthDays!)} نزول · طهرت في ${historyDate(p.firstCleanDay!, withYear: false)}',
          ),
  PeriodStatus.ongoing =>
    p.currentDay == null
        ? _t('Not ended yet', 'لم تنتهِ بعد')
        : _t('Day ${p.currentDay} today', 'اليوم ${p.currentDay} من الدورة'),
  PeriodStatus.endUnknown => _t(
    'Ended; add the end date to see its length',
    'انتهت؛ أضيفي تاريخ النهاية لمعرفة مدتها',
  ),
};

String _linkedSummary(PeriodItem p) {
  final n = p.observations.length;
  if (n == 1) {
    final o = p.observations.single;
    return _t(
      'Daily record on ${historyDate(o.date, withYear: false)}: ${observationDescription(o)}',
      'تسجيل يومي في ${historyDate(o.date, withYear: false)}: ${observationDescription(o)}',
    );
  }
  return _t(
    '$n daily records within this period',
    n == 2
        ? 'تسجيلان يوميان ضمن هذه الدورة'
        : '$n تسجيلات يومية ضمن هذه الدورة',
  );
}

/// One entry of the history list. Tapping it opens its details.
class PeriodHistoryTile extends StatelessWidget {
  const PeriodHistoryTile({super.key, required this.item, required this.onTap});
  final PeriodHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => switch (item) {
    final PeriodItem p => _tile(
      context,
      icon: p.status == PeriodStatus.ongoing
          ? Icons.water_drop_rounded
          : Icons.water_drop_outlined,
      iconColor: AppColors.brandSecondary,
      title: periodDates(p),
      chip: periodStatusLabel(p),
      chipColor: p.status == PeriodStatus.ongoing
          ? const Color(0xFFE91E4D)
          : p.status == PeriodStatus.completed
          ? const Color(0xFF0F7B5F)
          : const Color(0xFF9A6700),
      lines: [
        periodSummary(p),
        if (p.observations.isNotEmpty) _linkedSummary(p),
      ],
      linked: p.observations.isNotEmpty,
    ),
    final StandaloneObservationItem s => _tile(
      context,
      icon: Icons.edit_calendar_outlined,
      iconColor: AppColors.textTertiary,
      title: historyDate(s.observation.date),
      chip: _t('Separate record', 'تسجيل منفصل'),
      chipColor: const Color(0xFF6B7280),
      lines: [
        observationDescription(s.observation),
        _t('Not part of a recorded period', 'ليس ضمن دورة مسجّلة'),
      ],
      linked: false,
    ),
  };

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String chip,
    required Color chipColor,
    required List<String> lines,
    required bool linked,
  }) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: [title, chip, ...lines].join('. '),
      hint: _t('Double-tap for details', 'انقري مرتين للتفاصيل'),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _Chip(label: chip, color: chipColor),
                        ],
                      ),
                      for (final (i, line) in lines.indexed) ...[
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (linked && i == lines.length - 1) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  rtl
                                      ? Icons.subdirectory_arrow_left_rounded
                                      : Icons.subdirectory_arrow_right_rounded,
                                  size: 14,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

/// The state of the history: loading, failed, empty or a list.
class PeriodHistoryBody extends StatelessWidget {
  const PeriodHistoryBody({
    super.key,
    required this.items,
    required this.isLoading,
    required this.error,
    required this.incomplete,
    required this.onRetry,
    required this.onOpen,
    this.limit,
  });

  final List<PeriodHistoryItem> items;
  final bool isLoading;
  final String? error;

  /// The canonical periods could not all be read (offline); what is shown
  /// may be missing some.
  final bool incomplete;
  final VoidCallback onRetry;
  final ValueChanged<PeriodHistoryItem> onOpen;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return Padding(
        key: const Key('period-history-loading'),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Semantics(
          label: _t('Loading period history', 'جارٍ تحميل سجل الدورة'),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (error != null && items.isEmpty) {
      return Column(
        key: const Key('period-history-error'),
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          Text(
            _t(
              'Your period history could not be loaded.',
              'تعذّر تحميل سجل الدورة.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(_t('Try again', 'إعادة المحاولة')),
          ),
        ],
      );
    }
    if (items.isEmpty) {
      return Padding(
        key: const Key('period-history-empty'),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 40,
              color: Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 10),
            Text(
              _t('No cycle history yet', 'لا يوجد سجل للدورة بعد'),
              style: const TextStyle(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(
              _t(
                'Periods you record will appear here.',
                'ستظهر هنا الدورات التي تسجّلينها.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    final shown = limit == null ? items : items.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (incomplete)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _t(
                'Some periods could not be loaded right now, so this list may be incomplete.',
                'تعذّر تحميل بعض الدورات الآن، لذا قد تكون القائمة ناقصة.',
              ),
              style: const TextStyle(color: Color(0xFF9A6700), fontSize: 12),
            ),
          ),
        for (final (i, item) in shown.indexed) ...[
          if (i > 0) const Divider(height: 1, color: Color(0xFFF3E8E6)),
          PeriodHistoryTile(item: item, onTap: () => onOpen(item)),
        ],
      ],
    );
  }
}

/// Every detail of one entry, and the way to correct it.
Future<void> showPeriodHistoryDetails(
  BuildContext context,
  PeriodHistoryItem item, {
  required VoidCallback onOpenCalendar,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        key: const Key('period-history-details'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...switch (item) {
            final PeriodItem p => _periodDetails(p),
            final StandaloneObservationItem s => _observationDetails(s),
          },
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(
                _t('Correct it in the calendar', 'التعديل من التقويم'),
              ),
              onPressed: () {
                Navigator.of(sheetContext).pop();
                onOpenCalendar();
              },
            ),
          ),
        ],
      ),
    ),
  ),
);

Widget _heading(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Text(
    text,
    style: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
  ),
);

Widget _fact(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        ),
      ),
      Expanded(
        flex: 3,
        child: Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);

List<Widget> _periodDetails(PeriodItem p) => [
  _heading(_t('Period', 'الدورة')),
  _fact(_t('Status', 'الحالة'), periodStatusLabel(p)),
  _fact(_t('Started', 'البداية'), historyDate(p.start)),
  if (p.lastBleedingDay != null)
    _fact(
      _t('Last bleeding day', 'آخر يوم نزول'),
      historyDate(p.lastBleedingDay!),
    ),
  if (p.firstCleanDay != null)
    _fact(_t('First clean day', 'أول يوم طهر'), historyDate(p.firstCleanDay!)),
  if (p.lengthDays != null) _fact(_t('Length', 'المدة'), _days(p.lengthDays!)),
  if (p.currentDay != null)
    _fact(
      _t('Today', 'اليوم'),
      _t('Day ${p.currentDay}', 'اليوم ${p.currentDay}'),
    ),
  const SizedBox(height: 12),
  Text(
    _t('Daily records in this period', 'التسجيلات اليومية ضمن هذه الدورة'),
    style: const TextStyle(fontWeight: FontWeight.w700),
  ),
  const SizedBox(height: 6),
  if (p.observations.isEmpty)
    Text(
      _t(
        'None. The dates above are what you recorded for the period.',
        'لا يوجد. التواريخ أعلاه هي ما سجّلتِه للدورة.',
      ),
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  for (final o in p.observations)
    _fact(
      historyDate(o.date),
      o.dayOfPeriod == null
          ? observationDescription(o)
          : '${_t('Day ${o.dayOfPeriod}', 'اليوم ${o.dayOfPeriod}')} · ${observationDescription(o)}',
    ),
  if (p.firstCleanDay != null) ...[
    const SizedBox(height: 10),
    Text(
      _t(
        'The first clean day is when bleeding was recorded as stopped. It is not a bleeding day and not a new period.',
        'أول يوم طهر هو اليوم الذي سُجّل فيه توقف النزول، وليس يوم نزول ولا بداية دورة جديدة.',
      ),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        height: 1.5,
      ),
    ),
  ],
];

List<Widget> _observationDetails(StandaloneObservationItem s) => [
  _heading(_t('Daily record', 'تسجيل يومي')),
  _fact(_t('Date', 'التاريخ'), historyDate(s.observation.date)),
  _fact(_t('Recorded', 'المسجّل'), observationDescription(s.observation)),
  if ((s.observation.log.notes ?? '').trim().isNotEmpty)
    _fact(_t('Note', 'ملاحظة'), s.observation.log.notes!.trim()),
  const SizedBox(height: 10),
  Text(
    _t(
      'This record is not within any period you recorded, so it is shown on its own. Nothing was changed or merged.',
      'هذا التسجيل لا يقع ضمن أي دورة مسجّلة، لذلك يظهر وحده. لم يُحذف أو يُدمج شيء.',
    ),
    style: const TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12,
      height: 1.5,
    ),
  ),
];

/// The full list, opened from "عرض الكل".
class PeriodHistoryScreen extends StatelessWidget {
  const PeriodHistoryScreen({
    super.key,
    required this.listenable,
    required this.items,
    required this.isLoading,
    required this.error,
    required this.incomplete,
    required this.onRetry,
    required this.onOpenCalendar,
  });

  /// Rebuilds the list when the underlying data changes.
  final Listenable listenable;
  final List<PeriodHistoryItem> Function() items;
  final bool Function() isLoading;
  final String? Function() error;
  final bool Function() incomplete;
  final VoidCallback onRetry;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('Cycle history', 'سجل الدورة'))),
    body: ListenableBuilder(
      listenable: Listenable.merge([
        listenable,
        CalendarSystemController.instance,
      ]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          PeriodHistoryBody(
            items: items(),
            isLoading: isLoading(),
            error: error(),
            incomplete: incomplete(),
            onRetry: onRetry,
            onOpen: (item) => showPeriodHistoryDetails(
              context,
              item,
              onOpenCalendar: onOpenCalendar,
            ),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/period_prediction.dart';
import '../../domain/entities/prediction_history_review.dart';
import '../../../../core/utils/app_clock.dart';

/// Shared explanation across prediction surfaces. No percentage confidence
/// is inferred from history count or the width of the historical range.
class PeriodPredictionDetails extends StatelessWidget {
  const PeriodPredictionDetails({
    super.key,
    required this.prediction,
    this.onSaveReview,
    this.onReloadHistory,
  });
  final PeriodPrediction prediction;
  final Future<void> Function(PredictionHistoryReview review)? onSaveReview;
  final Future<void> Function()? onReloadHistory;

  String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);
  String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final String explanation;
    switch (prediction.status) {
      case PeriodPredictionStatus.insufficientHistory:
        explanation = _t(
          'Record actual period starts to build your personal history.',
          'سجّلي بدايات الدورة الفعلية لبناء سجلك الشخصي.',
        );
      case PeriodPredictionStatus.historyNeedsReview:
        explanation = switch (prediction.reviewReason) {
          PredictionReviewReason.unverifiedHistory => _t(
            'We could not verify your saved history-review answers. Reload your history before using an estimate.',
            'تعذر التحقق من إجابات مراجعة السجل المحفوظة. أعيدي تحميل السجل قبل استخدام أي تقدير.',
          ),
          PredictionReviewReason.unexplainedGap => _t(
            'There is an unusual gap between recorded starts. Review whether any periods were not recorded before we estimate another date.',
            'يوجد فاصل غير معتاد بين بدايات الدورة المسجلة. راجعي ما إذا كانت هناك دورات لم تُسجّل قبل تقدير موعد جديد.',
          ),
          PredictionReviewReason.insufficientRecentHistory => _t(
            'This gap is excluded from estimates. Record at least three actual starts after it to rebuild recent history; no missing periods have been invented.',
            'استُبعد هذا الفاصل من التقديرات. سجّلي ثلاث بدايات فعلية على الأقل بعده لبناء سجل حديث؛ لم نفترض حدوث دورات مفقودة.',
          ),
          PredictionReviewReason.excessiveVariation => _t(
            'Recent recorded intervals vary too widely for a useful estimate. Your records are kept; no date is shown.',
            'تتفاوت الفواصل المسجلة حديثًا بدرجة لا تسمح بتقدير مفيد. سجلك محفوظ، ولا نعرض موعدًا تقديريًا.',
          ),
          PredictionReviewReason.unsupportedLongInterval => _t(
            'Your answer is saved. This longer interval is outside the range supported by our estimator, so no date is shown. This is not a diagnosis.',
            'حُفظت إجابتك. هذا الفاصل الطويل يتجاوز نطاق التقدير الذي ندعمه، لذلك لا نعرض موعدًا. هذا ليس تشخيصًا.',
          ),
          PredictionReviewReason.staleHistory => _t(
            'The last recorded start is too old for a new estimate. Check your history and add any actual starts you have not recorded.',
            'مرّ وقت طويل على آخر بداية مسجلة فلا يتوفر تقدير جديد. راجعي سجلك وأضيفي البدايات الفعلية التي لم تسجّليها.',
          ),
          _ => _t(
            'Your records need checking before a new estimate can be shown.',
            'تحتاج بيانات السجل إلى مراجعة قبل عرض تقدير جديد.',
          ),
        };
      case PeriodPredictionStatus.overdue:
        explanation = _t(
          'The previous estimate has passed. Check your records; no new period has been assumed.',
          'مضى موعد التقدير السابق. راجعي سجلك؛ لم نفترض حدوث دورة جديدة.',
        );
      case PeriodPredictionStatus.estimated:
        explanation = prediction.hasHistoricalRange
            ? _t(
                'Based on ${prediction.intervalCount} recorded cycles. This range reflects past variation; it does not guarantee the next date.',
                'بناءً على ${prediction.intervalCount} دورة مسجلة. يعكس النطاق اختلاف المواعيد السابقة، ولا يضمن موعد الدورة القادمة.',
              )
            : _t(
                'Based on one recorded cycle interval. More history is needed to describe variation.',
                'بناءً على فاصل واحد مسجل بين بدايتَي دورة. نحتاج سجلًا أطول لوصف اختلاف المواعيد.',
              );
    }
    return Column(
      key: const Key('period-prediction-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prediction.hasFutureEstimate && prediction.hasHistoricalRange) ...[
          Text(
            _t('Range from your past cycles', 'نطاق مستند إلى دوراتك السابقة'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${_date(prediction.historicalRangeStart!)} – ${_date(prediction.historicalRangeEnd!)}',
            textDirection: TextDirection.ltr,
            key: const Key('period-historical-range'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          explanation,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        if (prediction.excludedIntervalCount > 0)
          Text(
            _t(
              'Estimates use up to six recent usable intervals; ${prediction.excludedIntervalCount} older or interrupted intervals are excluded. Recorded history is unchanged.',
              'تستخدم التقديرات حتى ستة فواصل حديثة قابلة للاستخدام؛ استُبعد ${prediction.excludedIntervalCount} من الفواصل الأقدم أو المنقطعة. لم يتغير السجل الفعلي.',
            ),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        if (prediction.reviewGaps.isNotEmpty && onSaveReview != null)
          TextButton.icon(
            key: const Key('review-prediction-history'),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              _t('Review gaps in your history', 'مراجعة الفواصل في سجلك'),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => Directionality(
                textDirection: AppLocaleController.instance.isArabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: _HistoryReviewSheet(
                  prediction: prediction,
                  onSave: onSaveReview!,
                ),
              ),
            ),
          ),
        if (prediction.reviewReason ==
                PredictionReviewReason.unverifiedHistory &&
            onReloadHistory != null)
          TextButton(
            onPressed: onReloadHistory,
            child: Text(_t('Reload history', 'إعادة تحميل السجل')),
          ),
      ],
    );
  }
}

class _HistoryReviewSheet extends StatefulWidget {
  const _HistoryReviewSheet({required this.prediction, required this.onSave});
  final PeriodPrediction prediction;
  final Future<void> Function(PredictionHistoryReview) onSave;
  @override
  State<_HistoryReviewSheet> createState() => _HistoryReviewSheetState();
}

class _HistoryReviewSheetState extends State<_HistoryReviewSheet> {
  bool _saving = false;
  bool _failed = false;
  String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);
  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _label(PredictionGapResolution resolution) => switch (resolution) {
    PredictionGapResolution.missedRecords => _t(
      'I missed recording one or more periods',
      'لم أسجّل دورة واحدة أو أكثر',
    ),
    PredictionGapResolution.longerCycle => _t(
      'This was a longer cycle; I did not miss a period',
      'كانت هذه دورة أطول، ولم أُغفل تسجيل دورة',
    ),
    PredictionGapResolution.unsure => _t('I am unsure', 'لست متأكدة'),
  };

  Future<void> _save(
    PredictionHistoryGap gap,
    PredictionGapResolution resolution,
  ) async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(
        PredictionHistoryReview(
          start: gap.start,
          end: gap.end,
          resolution: resolution,
          reportedAt: AppClock.now().toUtc(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _failed = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Review recorded gaps', 'مراجعة الفواصل المسجلة'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                'Choose an answer to save. It affects estimates only, never your bleeding records or religious rulings. Answers are saved securely on this device; another device may ask again.',
                'اختاري إجابة لحفظها. تؤثر في التقديرات فقط، ولا تغيّر سجل النزيف أو الأحكام الشرعية. تُحفظ الإجابات بأمان على هذا الجهاز، وقد تحتاجين للإجابة مجددًا على جهاز آخر.',
              ),
            ),
            if (_failed)
              Text(
                _t(
                  'Could not verify the saved answer. Retry or close and reload your history.',
                  'تعذر التحقق من حفظ الإجابة. أعيدي المحاولة أو أغلقي النافذة وأعيدي تحميل سجلك.',
                ),
              ),
            for (final gap in widget.prediction.reviewGaps) ...[
              const Divider(height: 32),
              Text(
                '${_date(gap.start)} – ${_date(gap.end)}',
                textDirection: TextDirection.ltr,
              ),
              Text(
                _t(
                  '${gap.days} days between recorded starts',
                  '${gap.days} يومًا بين البدايتين المسجلتين',
                ),
              ),
              if (gap.resolution != null)
                Text(
                  _t('Saved: ', 'الإجابة المحفوظة: ') + _label(gap.resolution!),
                ),
              for (final resolution in PredictionGapResolution.values)
                TextButton(
                  onPressed: _saving ? null : () => _save(gap, resolution),
                  child: Text(_label(resolution)),
                ),
            ],
            if (_saving) const LinearProgressIndicator(),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(_t('Close', 'إغلاق')),
            ),
          ],
        ),
      ),
    ),
  );
}

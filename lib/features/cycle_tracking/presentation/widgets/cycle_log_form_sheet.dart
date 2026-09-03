import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rating_scale_row.dart';
import '../../domain/entities/cycle_log.dart';
import '../../domain/services/cycle_calculation_service.dart';
import '../../domain/services/cycle_symptom_decoder.dart';
import '../models/cycle_log_form_data.dart';
import '../viewmodels/cycle_tracking_view_model.dart';

String _cl(String en, String ar) => AppLocaleController.instance.text(en, ar);

enum CycleLogSheetMode { period, symptomsOnly }

Future<void> showCycleLogSheet(
  BuildContext context, {
  required CycleTrackingViewModel viewModel,
  CycleLog? existingLog,
  CycleLogSheetMode mode = CycleLogSheetMode.period,
  DateTime? date,
  FlowLevel? initialFlow,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .34),
  builder: (_) => _CycleLogSheet(
    viewModel: viewModel,
    existingLog: existingLog,
    mode: mode,
    date: date ?? DateTime.now(),
    initialFlow: initialFlow,
  ),
);

class _CycleLogSheet extends StatefulWidget {
  const _CycleLogSheet({
    required this.viewModel,
    required this.date,
    this.existingLog,
    this.mode = CycleLogSheetMode.period,
    this.initialFlow,
  });
  final CycleTrackingViewModel viewModel;
  final CycleLog? existingLog;
  final CycleLogSheetMode mode;

  /// The date this log applies to when creating a *new* entry (an edit
  /// always keeps the existing log's own date). Defaults to today at the
  /// [showCycleLogSheet] call site; the calendar's day-tap passes the
  /// tapped date so backfilling a past day doesn't silently save as today.
  final DateTime date;

  /// Overrides the flow the sheet opens with, taking priority over
  /// [existingLog]'s own flow. Callers whose action explicitly means "log
  /// bleeding now" (period-start button, ring tap, blood-log prompt) pass
  /// this so today's *already-logged* flow (e.g. `none` from an earlier
  /// "period ended" entry) can't silently pre-select itself and turn the
  /// save into a no-op. Left null for edit flows (the calendar's day-tap)
  /// where showing what's actually logged for that day is the point.
  final FlowLevel? initialFlow;

  @override
  State<_CycleLogSheet> createState() => _CycleLogSheetState();
}

class _CycleLogSheetState extends State<_CycleLogSheet> {
  static const _presetBloodColors = {'red', 'dark', 'brown', 'pink', 'other'};

  late FlowLevel _flow;
  // Defaults to "Red" (the most common case) rather than "Other" — "Other"
  // now reveals a text field, which shouldn't appear unprompted on a
  // brand-new log before the user has actually picked it.
  String _bloodColor = 'red';
  int _energy = 3;
  int _sleep = 3;
  int _mood = 3;
  final Map<String, int> _symptoms = <String, int>{};
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customColorController = TextEditingController();
  bool _saving = false;

  bool get _isPeriodMode => widget.mode == CycleLogSheetMode.period;

  /// What actually gets saved for blood color: the free-text description
  /// when "Other" is selected and something was typed, otherwise whichever
  /// chip id is selected (including the literal "other" if left blank).
  String get _resolvedBloodColor {
    if (_bloodColor == 'other') {
      final custom = _customColorController.text.trim();
      if (custom.isNotEmpty) return custom;
    }
    return _bloodColor;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existingLog;
    _flow =
        widget.initialFlow ??
        existing?.flow ??
        (_isPeriodMode ? FlowLevel.medium : FlowLevel.none);
    if (existing != null) {
      final decoded = CycleSymptomDecoder.decode(existing);
      final decodedColor = decoded.bloodColor;
      if (decodedColor != null && !_presetBloodColors.contains(decodedColor)) {
        // A previously-saved custom description — reselect "Other" and
        // repopulate the free-text field with it.
        _bloodColor = 'other';
        _customColorController.text = decodedColor;
      } else {
        _bloodColor = decodedColor ?? _bloodColor;
      }
      _energy = decoded.energy ?? _energy;
      _sleep = decoded.sleep ?? _sleep;
      _mood = decoded.mood ?? _mood;
      _symptoms.addAll(decoded.symptomSeverities);
      _notesController.text = decoded.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _customColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: FractionallySizedBox(
        heightFactor: .91,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFFFFEFD),
            borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    _header(),
                    const SizedBox(height: 26),
                    if (_isPeriodMode) ...[
                      _sectionCard(
                        icon: Icons.water_drop_outlined,
                        title: _cl('Flow intensity', 'شدة التدفق'),
                        subtitle: _cl(
                          'Choose the closest description for today.',
                          'اختاري أقرب وصف لهذا اليوم.',
                        ),
                        child: Row(
                          children: FlowLevel.values
                              .map(
                                (flow) => Expanded(
                                  child: _FlowChoice(
                                    flow: flow,
                                    selected: _flow == flow,
                                    onTap: () => setState(() => _flow = flow),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: _cl('Blood color', 'لون الدم'),
                        leadingLabel:
                            _bloodColor == 'other' &&
                                _customColorController.text.trim().isNotEmpty
                            ? _customColorController.text.trim()
                            : switch (_bloodColor) {
                                'red' => _cl('Red', 'أحمر'),
                                'dark' => _cl('Dark', 'داكن'),
                                'brown' => _cl('Brown', 'بني'),
                                'pink' => _cl('Pink', 'وردي'),
                                _ => _cl('Other', 'غير ذلك'),
                              },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _color(
                                  'red',
                                  _cl('Red', 'أحمر'),
                                  const Color(0xFFEC4961),
                                ),
                                _color(
                                  'dark',
                                  _cl('Dark', 'داكن'),
                                  const Color(0xFF9B1C3B),
                                ),
                                _color(
                                  'brown',
                                  _cl('Brown', 'بني'),
                                  const Color(0xFF873F14),
                                ),
                                _color(
                                  'pink',
                                  _cl('Pink', 'وردي'),
                                  const Color(0xFFED7381),
                                ),
                                _color(
                                  'other',
                                  _cl('Other', 'غير ذلك'),
                                  const Color(0xFFD1D5DB),
                                ),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              alignment: Alignment.topCenter,
                              child: _bloodColor != 'other'
                                  ? const SizedBox(width: double.infinity)
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: TextField(
                                        controller: _customColorController,
                                        autofocus: true,
                                        maxLength: 60,
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          counterText: '',
                                          hintText: _cl(
                                            'Describe the color here...',
                                            'اكتبي وصف اللون هنا...',
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFF9FAFB),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    RatingScaleRow(
                      label: _cl('Mood', 'المزاج'),
                      icon: Icons.sentiment_satisfied_alt_rounded,
                      iconBuilder: moodRatingIcon,
                      activeColor: const Color(0xFFFB7185),
                      value: _mood,
                      descriptionBuilder: moodRatingDescription,
                      onChanged: (value) => setState(() => _mood = value),
                    ),
                    const SizedBox(height: 20),
                    RatingScaleRow(
                      label: _cl('Energy', 'الطاقة'),
                      icon: Icons.bolt_rounded,
                      activeColor: const Color(0xFFF59E0B),
                      value: _energy,
                      descriptionBuilder: energyRatingDescription,
                      onChanged: (value) => setState(() => _energy = value),
                    ),
                    const SizedBox(height: 20),
                    RatingScaleRow(
                      label: _cl('Sleep', 'النوم'),
                      icon: Icons.nightlight_round,
                      activeColor: const Color(0xFF0D9488),
                      value: _sleep,
                      descriptionBuilder: sleepRatingDescription,
                      onChanged: (value) => setState(() => _sleep = value),
                    ),
                    const SizedBox(height: 16),
                    _symptomsCard(),
                    const SizedBox(height: 16),
                    _notesCard(),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.paddingOf(context).bottom + 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFEFD),
                  border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
                ),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_cl('Save log', 'حفظ السجل')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    backgroundColor: const Color(0xFFF43F5E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppTypography.arabicFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final isArabic = AppLocaleController.instance.isArabic;
    final alignment = isArabic
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 76, top: 4),
          child: Column(
            crossAxisAlignment: alignment,
            children: [
              Align(
                alignment: isArabic
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFFFD5DB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isPeriodMode
                            ? Icons.water_drop_outlined
                            : Icons.favorite_outline,
                        color: const Color(0xFFF43F5E),
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isPeriodMode
                            ? _cl('TODAY\'S LOG', 'تسجيل اليوم')
                            : _cl('SYMPTOMS', 'تسجيل الأعراض'),
                        style: const TextStyle(
                          color: Color(0xFFF43F5E),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isPeriodMode
                    ? _cl('Log today', 'تسجيل اليوم')
                    : _cl('Log symptoms', 'تسجيل الأعراض'),
                style: TextStyle(
                  fontFamily: AppTypography.serifFamily,
                  color: const Color(0xFF111827),
                  fontSize: 32,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _isPeriodMode
                    ? _cl(
                        'Record blood details and symptoms for today.',
                        'سجلي تفاصيل الدم والأعراض لهذا اليوم.',
                      )
                    : _cl(
                        'Record how you\'re feeling today.',
                        'سجلي حالتك وأعراضك لهذا اليوم.',
                      ),
                style: const TextStyle(
                  color: Color(0xFF7C8494),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Positioned.directional(
          textDirection: textDirection,
          start: 0,
          top: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9CA3AF),
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    IconData? icon,
    Color iconColor = const Color(0xFFFB7185),
    required String title,
    String? subtitle,
    String? leadingLabel,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: icon == null ? const Color(0xFFF3F4F6) : const Color(0xFFFFD5DB),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  icon,
                  key: ValueKey(icon),
                  color: iconColor,
                  size: 25,
                ),
              ),
            ] else if (leadingLabel != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  leadingLabel,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _color(String id, String label, Color color) => Expanded(
    child: _ColorChoice(
      label: label,
      color: color,
      selected: _bloodColor == id,
      onTap: () => setState(() => _bloodColor = id),
    ),
  );

  Widget _symptomsCard() {
    final symptoms = <String>[
      _cl('Cramps', 'تشنجات'),
      _cl('Mood', 'المزاج'),
      _cl('Headache', 'صداع'),
      _cl('Bloating', 'انتفاخ'),
      _cl('Back pain', 'ألم ظهر'),
      _cl('Nausea', 'غثيان'),
      _cl('Fatigue', 'تعب'),
      _cl('Acne', 'حبوب'),
      _cl('Breast pain', 'آلام الثدي'),
    ];
    return _sectionCard(
      title: _cl('Symptoms', 'الأعراض'),
      subtitle: _cl(
        'Tap repeatedly to move from mild to severe.',
        'اضغطي مرة للتدرج من خفيف إلى شديد.',
      ),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: symptoms.map((symptom) {
          final severity = _symptoms[symptom] ?? 0;
          return InkWell(
            onTap: () => setState(() {
              final next = (severity + 1) % 4;
              if (next == 0) {
                _symptoms.remove(symptom);
              } else {
                _symptoms[symptom] = next;
              }
            }),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: (MediaQuery.sizeOf(context).width - 94) / 3,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: severity == 0
                    ? const Color(0xFFF9FAFB)
                    : const Color(0xFFF43F5E)
                          .withValues(alpha: .25 + severity * .22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: severity == 0
                      ? const Color(0xFFF1F2F4)
                      : const Color(0xFFFF8FA3),
                ),
              ),
              child: Text(
                symptom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: severity == 0
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF9F1239),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _notesCard() => _sectionCard(
    title: _cl('Notes', 'ملاحظات'),
    subtitle: _cl(
      'Write anything you want to remember later.',
      'اكتبي أي شيء تريدين تذكره لاحقاً.',
    ),
    child: TextField(
      controller: _notesController,
      minLines: 4,
      maxLines: 6,
      decoration: InputDecoration(
        hintText: _cl(
          'For example: I slept late, felt more anxious than usual, or felt better after walking...',
          'مثلاً: نمت متأخرة، قلقي كان أعلى من المعتاد، أو شعرت براحة بعد المشي...',
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF1F2F4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF1F2F4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF8FA3)),
        ),
      ),
      style: const TextStyle(fontSize: 12),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final existing = widget.existingLog;
      final date = existing?.date ?? widget.date;
      final notes = _notesController.text.trim();
      await widget.viewModel.saveLog(
        CycleLogFormData(
          date: date,
          flow: _flow,
          cycleDay:
              existing?.cycleDay ??
              const CycleCalculationService().computeCycleDayForNewEntry(
                existingLogs: widget.viewModel.logs,
                date: date,
                flow: _flow,
              ),
          notes: notes.isEmpty ? null : notes,
          symptoms: [
            'energy:$_energy',
            'sleep:$_sleep',
            if (_isPeriodMode) 'color:$_resolvedBloodColor',
            'mood:$_mood',
            ..._symptoms.entries.map((entry) => '${entry.key}:${entry.value}'),
          ],
        ),
        existingLog: existing,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(content: Text(_cl('Log saved.', 'تم حفظ السجل.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is FormatException
            ? e.message
            : _cl('Unable to save your cycle log.', 'تعذر حفظ سجل الدورة.');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _FlowChoice extends StatelessWidget {
  const _FlowChoice({
    required this.flow,
    required this.selected,
    required this.onTap,
  });
  final FlowLevel flow;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = switch (flow) {
      FlowLevel.none => const Color(0xFFE5E7EB),
      FlowLevel.spotting => const Color(0xFFF9A8B4),
      FlowLevel.light => const Color(0xFFED7E8E),
      FlowLevel.medium => const Color(0xFFC70D3D),
      FlowLevel.heavy => const Color(0xFF881337),
    };
    final label = switch (flow) {
      FlowLevel.none => _cl('Period ended', 'انتهى الحيض'),
      FlowLevel.spotting => _cl('Spotting', 'تنقيط'),
      FlowLevel.light => _cl('Light', 'خفيف'),
      FlowLevel.medium => _cl('Medium', 'متوسط'),
      FlowLevel.heavy => _cl('Heavy', 'شديد'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF1F2) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFF8FA3)
                  : const Color(0xFFF1F2F4),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: flow == FlowLevel.none ? Colors.transparent : color,
                  shape: BoxShape.circle,
                  border: flow == FlowLevel.none
                      ? Border.all(color: const Color(0xFFD1D5DB), width: 2)
                      : null,
                ),
              ),
              const SizedBox(height: 7),
              FittedBox(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF9F1239)
                        : const Color(0xFF9CA3AF),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
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

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFF8FA3) : const Color(0xFFF1F2F4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

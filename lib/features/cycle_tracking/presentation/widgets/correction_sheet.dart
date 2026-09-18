import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/device_timezone.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../data/local/pending_bleeding_operation_store.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../domain/entities/bleeding_episode.dart';

String _t(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

String _flowLabel(ObservationFlow flow) => switch (flow) {
  ObservationFlow.uncertain => _t("I'm not sure", 'لست متأكدة'),
  ObservationFlow.none => _t('None', 'لا يوجد'),
  ObservationFlow.spotting => _t('Spotting', 'تبقيع'),
  ObservationFlow.light => _t('Light', 'خفيف'),
  ObservationFlow.medium => _t('Medium', 'متوسط'),
  ObservationFlow.heavy => _t('Heavy', 'غزير'),
};

/// Menstrual Data Integrity charter, Commits D5/D6/D7 — corrects one
/// existing observation. [target] must be the CURRENT tip of its
/// revision chain (resolve via
/// [BleedingEpisodeRepositoryImpl.effectiveObservationId] before opening
/// this — Commit D6's correction-of-correction works by always
/// correcting the tip, never the original root, so a third correction on
/// top of a second one is simply another call with the second one as
/// [target]). Returns true if a correction was actually saved.
///
/// D7 — if another correction reached the target first (a different
/// device, an earlier reconciliation), this surfaces a real conflict
/// screen — "Current saved value: X / Your offline change: Y" — rather
/// than silently forking or losing her intended change. Choosing "Use my
/// change" retries against the NEW current tip, never the stale original
/// (Section: "create a new revision from the CURRENT tip, not a fork
/// from v1").
Future<bool> showCorrectObservationSheet(
  BuildContext context, {
  required BleedingObservation target,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CorrectObservationSheet(target: target),
  );
  return result ?? false;
}

class _CorrectObservationSheet extends StatefulWidget {
  const _CorrectObservationSheet({required this.target});
  final BleedingObservation target;

  @override
  State<_CorrectObservationSheet> createState() =>
      _CorrectObservationSheetState();
}

class _CorrectObservationSheetState extends State<_CorrectObservationSheet> {
  late ObservationFlow? _flow = widget.target.flow;
  bool _saving = false;
  String? _errorMessage;

  // D7 — set only when a conflict is detected; carries the value already
  // saved (fetched fresh via effectiveObservationId + a lookup, never
  // parsed out of the exception message) so the resolution UI can show
  // an honest "Current saved value."
  BleedingObservation? _conflictWith;
  String _clientOperationId = const Uuid().v4();
  String _supersedesId = '';

  bool get _arabic => AppLocaleController.instance.isArabic;

  @override
  void initState() {
    super.initState();
    _supersedesId = widget.target.id!;
  }

  Future<void> _submit() async {
    final flow = _flow;
    if (flow == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
      _conflictWith = null;
    });

    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;
    final repository = BleedingEpisodeRepositoryImpl();

    // Commit D9: persisted before the RPC is sent — the same durable
    // pattern every other write in this model uses. A conflict (D7)
    // deliberately leaves this pending rather than clearing it, so her
    // offline-intended change is never silently dropped.
    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: _clientOperationId,
        type: PendingBleedingOperationType.correction,
        params: {
          'supersedesId': _supersedesId,
          'observedDate': widget.target.observedDate.toIso8601String(),
          'precision': widget.target.precision.value,
          'flow': flow.value,
          'source': widget.target.source.value,
          'utcOffsetMinutes': utcOffsetMinutes,
          'timezone': timezone,
        },
        createdAt: now,
      ),
    );

    try {
      final observationId = await repository.correctObservation(
        clientOperationId: _clientOperationId,
        supersedesId: _supersedesId,
        observedDate: widget.target.observedDate,
        precision: widget.target.precision,
        flow: flow,
        source: widget.target.source,
        utcOffsetMinutes: utcOffsetMinutes,
        timezone: timezone,
      );

      if (observationId == null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _errorMessage = _t(
            'Could not save. Please try again.',
            'تعذر الحفظ. يرجى المحاولة مجدداً.',
          );
        });
        return;
      }

      await PendingBleedingOperationStore.clearPending(_clientOperationId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CorrectionConflictException catch (conflict) {
      // The value that's actually saved now — a fresh read, never
      // reconstructed from the exception itself.
      final currentTipId = await repository.effectiveObservationId(
        conflict.supersedesId,
      );
      final observations = await repository.getObservationsForEpisode(
        widget.target.episodeId,
      );
      final currentValue = observations
          .where((o) => o.id == currentTipId)
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _conflictWith = currentValue;
      });
    }
  }

  void _useMyChangeAnyway() {
    final conflictWith = _conflictWith;
    if (conflictWith?.id == null) return;
    // Rebased onto the CURRENT tip, never the stale original target —
    // exactly the "new revision from the current tip, not a fork from
    // v1" the charter requires. A fresh operation id: this is now
    // logically a *new* correction attempt, not a retry of the one that
    // just conflicted.
    setState(() {
      _supersedesId = conflictWith!.id!;
      _clientOperationId = const Uuid().v4();
      _conflictWith = null;
    });
    unawaited(_submit());
  }

  void _keepSaved() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final conflictWith = _conflictWith;
    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 20,
          end: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: conflictWith != null
              ? _buildConflict(conflictWith)
              : _buildForm(),
        ),
      ),
    );
  }

  List<Widget> _buildForm() => [
    Text(
      _t('Correct this entry', 'تصحيح هذا الإدخال'),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontFamily: AppTypography.serifFamily,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    Text(
      _t('What was the flow that day?', 'ما حال النزيف في ذلك اليوم؟'),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in ObservationFlow.values)
          ChoiceChip(
            label: Text(_flowLabel(option)),
            selected: _flow == option,
            onSelected: (_) => setState(() => _flow = option),
          ),
      ],
    ),
    if (_errorMessage != null) ...[
      const SizedBox(height: 16),
      Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.red),
        textAlign: TextAlign.center,
      ),
    ],
    const SizedBox(height: 24),
    FilledButton(
      onPressed: (_flow == null || _saving) ? null : _submit,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.haid,
      ),
      child: _saving
          ? const NiswahLoadingIndicator(
              size: NiswahLoadingSize.small,
              contrast: NiswahLoadingContrast.light,
            )
          : Text(_t('Save correction', 'حفظ التصحيح')),
    ),
  ];

  List<Widget> _buildConflict(BleedingObservation conflictWith) => [
    Text(
      _t('This entry changed elsewhere', 'تغيّر هذا الإدخال في مكان آخر'),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontFamily: AppTypography.serifFamily,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 12),
    Text(
      _t(
        'Another device already saved a different correction for this '
            'day while you were offline.',
        'قام جهاز آخر بحفظ تصحيح مختلف لهذا اليوم أثناء عدم اتصالكِ.',
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBF8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _t(
          'Current saved value: ${_flowLabel(conflictWith.flow)}',
          'القيمة المحفوظة حالياً: ${_flowLabel(conflictWith.flow)}',
        ),
      ),
    ),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _t(
          'Your offline change: ${_flow != null ? _flowLabel(_flow!) : ''}',
          'تغييركِ غير المتصل: ${_flow != null ? _flowLabel(_flow!) : ''}',
        ),
      ),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _keepSaved,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(_t('Keep saved value', 'الاحتفاظ بالقيمة المحفوظة')),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: _useMyChangeAnyway,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(_t('Use my change', 'استخدام تغييري')),
    ),
  ];
}

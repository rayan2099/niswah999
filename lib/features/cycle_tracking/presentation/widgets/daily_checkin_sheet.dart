import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/device_timezone.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../../notifications/domain/services/notification_scheduler.dart';
import '../../data/local/pending_bleeding_operation_store.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/cycle_entries_projection.dart';
import '../../domain/entities/bleeding_episode.dart';

String _t(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

/// Commit D1's three possible outcomes of one daily check-in — the
/// dashboard uses this to decide what to refresh, never assumes success
/// from a mere "the sheet closed."
enum DailyCheckinOutcome {
  /// Dismissed without answering — nothing was recorded (Section
  /// 15/D3: a missed/skipped check-in is zero observations, not a
  /// guess).
  cancelled,

  /// YES — a new flow observation was recorded for today.
  recordedToday,

  /// NO — the episode was ended via the atomic `end_bleeding_episode`
  /// RPC (a real closing observation now exists too).
  ended,

  /// I'M NOT SURE — `continuation_certainty` set to uncertain; the
  /// episode stays open, no observation was fabricated either way.
  markedUncertain,
}

/// Menstrual Data Integrity charter, Commit D1 — the daily check-in for
/// an OPEN episode (Sections 8-11/14/15): "Are you still bleeding
/// today?" with three real answers, never a forced YES/NO. Distinct from
/// [showStartBleedingSheet]/[showEndBleedingSheet] (Section 6's one-time
/// start/end questions) — this is the *recurring* question asked once
/// bleeding is already being tracked. [episodeId]/[episodeStartDate] bound
/// what this sheet can do (mirrors [showEndBleedingSheet]'s own end-date
/// picker bounding, Blocker 11).
Future<DailyCheckinOutcome> showDailyCheckinSheet(
  BuildContext context, {
  required String episodeId,
  required DateTime episodeStartDate,
}) async {
  final result = await showModalBottomSheet<DailyCheckinOutcome>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DailyCheckinSheet(
      episodeId: episodeId,
      episodeStartDate: episodeStartDate,
    ),
  );
  return result ?? DailyCheckinOutcome.cancelled;
}

enum _CheckinStep { question, yesFlow, noEndDate }

class _DailyCheckinSheet extends StatefulWidget {
  const _DailyCheckinSheet({
    required this.episodeId,
    required this.episodeStartDate,
  });
  final String episodeId;
  final DateTime episodeStartDate;

  @override
  State<_DailyCheckinSheet> createState() => _DailyCheckinSheetState();
}

class _DailyCheckinSheetState extends State<_DailyCheckinSheet> {
  _CheckinStep _step = _CheckinStep.question;
  ObservationFlow? _flow;
  DateTime? _endDate;
  bool _saving = false;
  String? _errorMessage;

  final String _clientOperationId = const Uuid().v4();

  bool get _arabic => AppLocaleController.instance.isArabic;

  Future<void> _submitYes() async {
    final flow = _flow;
    if (flow == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;
    final today = DateTime(now.year, now.month, now.day);

    // Commit D9: persisted before the RPC is sent — the same pattern the
    // Start/End sheets already establish. If the process dies between the
    // server committing and this sheet ever seeing the response, the next
    // app start's reconciliation replays this exact operation id rather
    // than risking a fresh one on retry.
    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: _clientOperationId,
        type: PendingBleedingOperationType.dailyOrBackfillObservation,
        params: {
          'episodeId': widget.episodeId,
          'observedDate': today.toIso8601String(),
          'precision': ObservationPrecision.dateOnly.value,
          'flow': flow.value,
          'utcOffsetMinutes': utcOffsetMinutes,
          'timezone': timezone,
        },
        createdAt: now,
      ),
    );

    final repository = BleedingEpisodeRepositoryImpl();
    final observationId = await repository.recordObservation(
      clientOperationId: _clientOperationId,
      episodeId: widget.episodeId,
      observedDate: today,
      precision: ObservationPrecision.dateOnly,
      flow: flow,
      utcOffsetMinutes: utcOffsetMinutes,
      timezone: timezone,
    );

    if (observationId == null) {
      // Closure Blocker 12 — the observation is already safely encrypted
      // on-device (savePending above already committed before this RPC
      // was ever sent) and queued for the next reconciliation attempt —
      // "Could not save" would be a lie here; nothing was lost.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'Saved on device — syncing.',
          'تم الحفظ على الجهاز — جارٍ المزامنة.',
        );
      });
      return;
    }

    await PendingBleedingOperationStore.clearPending(_clientOperationId);

    // Best-effort mirror into the legacy read model — see the Start/End
    // sheets' own identical note (Blocker 12, Commit F closes this gap).
    try {
      final observations =
          (await repository.getObservationsForEpisode(widget.episodeId))
              .dataOrNull ??
          const [];
      final recorded = observations
          .where((o) => o.id == observationId)
          .firstOrNull;
      if (recorded != null) {
        await CycleEntriesProjection().project(recorded);
      }
    } catch (_) {
      // Reported internally by the projection's own repository calls.
    }

    if (!mounted) return;
    Navigator.of(context).pop(DailyCheckinOutcome.recordedToday);
  }

  Future<void> _submitNo() async {
    final endDate = _endDate;
    if (endDate == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;

    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: _clientOperationId,
        type: PendingBleedingOperationType.endEpisode,
        params: {
          'episodeId': widget.episodeId,
          'endDate': endDate.toIso8601String(),
          'endPrecision': ObservationPrecision.dateOnly.value,
          'observationPrecision': ObservationPrecision.dateOnly.value,
          'timezone': timezone,
          'utcOffsetMinutes': utcOffsetMinutes,
        },
        createdAt: now,
      ),
    );

    final repository = BleedingEpisodeRepositoryImpl();
    final result = await repository.endEpisode(
      clientOperationId: _clientOperationId,
      episodeId: widget.episodeId,
      endDate: endDate,
      endPrecision: ObservationPrecision.dateOnly,
      observationPrecision: ObservationPrecision.dateOnly,
      timezone: timezone,
      utcOffsetMinutes: utcOffsetMinutes,
    );

    if (result == null) {
      // Closure Blocker 12 — already safely queued (savePending ran
      // before this RPC), so this is never "Could not save."
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'Saved on device — syncing.',
          'تم الحفظ على الجهاز — جارٍ المزامنة.',
        );
      });
      return;
    }

    await PendingBleedingOperationStore.clearPending(_clientOperationId);
    try {
      final observations =
          (await repository.getObservationsForEpisode(widget.episodeId))
              .dataOrNull ??
          const [];
      final closingObservation = observations
          .where((o) => o.id == result.closingObservationId)
          .firstOrNull;
      if (closingObservation != null) {
        await CycleEntriesProjection().project(closingObservation);
      }
    } catch (_) {
      // Reported internally by the projection's own repository calls.
    }

    // Commit E9 — ending the episode cancels today's own active-bleeding
    // reminder id (the same stable id the coordinator would have
    // scheduled it under); no reminder should keep asking about an
    // episode that no longer exists as open.
    final signedInUserId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (signedInUserId != null) {
      await NotificationService.instance.cancel(
        ActiveBleedingReminderScheduler.reminderId(
          userId: signedInUserId,
          episodeId: widget.episodeId,
          localDay: BleedingEpisodeRepositoryImpl.localToday(utcOffsetMinutes),
        ),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(DailyCheckinOutcome.ended);
  }

  Future<void> _submitUnsure() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final repository = BleedingEpisodeRepositoryImpl();
    final result = await repository.markEpisodeUncertain(widget.episodeId);

    if (result == null) {
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

    if (!mounted) return;
    Navigator.of(context).pop(DailyCheckinOutcome.markedUncertain);
  }

  Future<void> _pickOtherEndDate() async {
    final now = AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now,
      firstDate: widget.episodeStartDate,
      lastDate: now,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) => Directionality(
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
        children: [
          Text(
            _t('Daily check-in', 'المتابعة اليومية'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontFamily: AppTypography.serifFamily,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_step == _CheckinStep.question) ..._buildQuestion(),
          if (_step == _CheckinStep.yesFlow) ..._buildYesFlow(),
          if (_step == _CheckinStep.noEndDate) ..._buildNoEndDate(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );

  List<Widget> _buildQuestion() => [
    Text(
      _t('Are you still bleeding today?', 'هل ما زال النزيف مستمراً اليوم؟'),
      style: const TextStyle(fontWeight: FontWeight.w600),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: () => setState(() => _step = _CheckinStep.yesFlow),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.haid,
      ),
      child: Text(_t('Yes', 'نعم')),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: () => setState(() => _step = _CheckinStep.noEndDate),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(_t('No', 'لا')),
    ),
    const SizedBox(height: 10),
    TextButton(
      onPressed: _saving ? null : _submitUnsure,
      child: _saving
          ? const NiswahLoadingIndicator(size: NiswahLoadingSize.small)
          : Text(_t("I'm not sure", 'لست متأكدة')),
    ),
  ];

  List<Widget> _buildYesFlow() => [
    Text(
      _t('How is it right now?', 'كيف حاله الآن؟'),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in const [
          (ObservationFlow.spotting, 'Spotting', 'تبقيع'),
          (ObservationFlow.light, 'Light', 'خفيف'),
          (ObservationFlow.medium, 'Medium', 'متوسط'),
          (ObservationFlow.heavy, 'Heavy', 'غزير'),
          (ObservationFlow.uncertain, "I'm not sure", 'لست متأكدة'),
        ])
          ChoiceChip(
            label: Text(_t(option.$2, option.$3)),
            selected: _flow == option.$1,
            onSelected: (_) => setState(() => _flow = option.$1),
          ),
      ],
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: (_flow == null || _saving) ? null : _submitYes,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.haid,
      ),
      child: _saving
          ? const NiswahLoadingIndicator(
              size: NiswahLoadingSize.small,
              contrast: NiswahLoadingContrast.light,
            )
          : Text(_t('Save', 'حفظ')),
    ),
  ];

  List<Widget> _buildNoEndDate() {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayReachable = !yesterday.isBefore(widget.episodeStartDate);

    return [
      Text(
        _t('When did it stop?', 'متى توقف؟'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text(_t('Today', 'اليوم')),
            selected: _endDate != null && DateUtils.isSameDay(_endDate, today),
            onSelected: (_) => setState(() => _endDate = today),
          ),
          ChoiceChip(
            label: Text(_t('Yesterday', 'أمس')),
            selected:
                _endDate != null && DateUtils.isSameDay(_endDate, yesterday),
            onSelected: yesterdayReachable
                ? (_) => setState(() => _endDate = yesterday)
                : null,
          ),
          ActionChip(
            label: Text(
              _endDate != null &&
                      !DateUtils.isSameDay(_endDate, today) &&
                      !DateUtils.isSameDay(_endDate, yesterday)
                  ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                  : _t('Choose a date', 'اختيار تاريخ'),
            ),
            onPressed: _pickOtherEndDate,
          ),
        ],
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: (_endDate == null || _saving) ? null : _submitNo,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.haid,
        ),
        child: _saving
            ? const NiswahLoadingIndicator(
                size: NiswahLoadingSize.small,
                contrast: NiswahLoadingContrast.light,
              )
            : Text(_t('Save', 'حفظ')),
      ),
    ];
  }
}

/// Menstrual Data Integrity charter, Commit D4 — backfill: a report made
/// after the fact (Section 16). Unlike the daily check-in (always today),
/// this lets her pick ANY date within the episode's own range —
/// `observed_date` is genuinely that past date, `reported_at` defaults to
/// right now via the column's own DEFAULT, so the gap between them is
/// never fabricated. [initialDate] pre-fills the picker (Commit D3's
/// missed-day prompt passes the specific missing date it detected).
Future<bool> showBackfillObservationSheet(
  BuildContext context, {
  required String episodeId,
  required DateTime episodeStartDate,
  DateTime? initialDate,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BackfillObservationSheet(
      episodeId: episodeId,
      episodeStartDate: episodeStartDate,
      initialDate: initialDate,
    ),
  );
  return result ?? false;
}

class _BackfillObservationSheet extends StatefulWidget {
  const _BackfillObservationSheet({
    required this.episodeId,
    required this.episodeStartDate,
    this.initialDate,
  });
  final String episodeId;
  final DateTime episodeStartDate;
  final DateTime? initialDate;

  @override
  State<_BackfillObservationSheet> createState() =>
      _BackfillObservationSheetState();
}

class _BackfillObservationSheetState extends State<_BackfillObservationSheet> {
  late DateTime? _observedDate = widget.initialDate;
  ObservationFlow? _flow;
  bool _saving = false;
  String? _errorMessage;

  final String _clientOperationId = const Uuid().v4();

  bool get _arabic => AppLocaleController.instance.isArabic;

  Future<void> _pickDate() async {
    final now = AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _observedDate ?? now,
      firstDate: widget.episodeStartDate,
      lastDate: now,
    );
    if (picked != null) setState(() => _observedDate = picked);
  }

  Future<void> _submit() async {
    final observedDate = _observedDate;
    final flow = _flow;
    if (observedDate == null || flow == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;

    await PendingBleedingOperationStore.savePending(
      PendingBleedingOperation(
        operationId: _clientOperationId,
        type: PendingBleedingOperationType.dailyOrBackfillObservation,
        params: {
          'episodeId': widget.episodeId,
          'observedDate': observedDate.toIso8601String(),
          'precision': ObservationPrecision.dateOnly.value,
          'flow': flow.value,
          'utcOffsetMinutes': utcOffsetMinutes,
          'timezone': timezone,
        },
        createdAt: now,
      ),
    );

    final repository = BleedingEpisodeRepositoryImpl();
    final observationId = await repository.recordObservation(
      clientOperationId: _clientOperationId,
      episodeId: widget.episodeId,
      observedDate: observedDate,
      precision: ObservationPrecision.dateOnly,
      flow: flow,
      utcOffsetMinutes: utcOffsetMinutes,
      timezone: timezone,
    );

    if (observationId == null) {
      // Closure Blocker 12 — already safely queued (savePending ran
      // before this RPC), so this is never "Could not save."
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'Saved on device — syncing.',
          'تم الحفظ على الجهاز — جارٍ المزامنة.',
        );
      });
      return;
    }

    await PendingBleedingOperationStore.clearPending(_clientOperationId);
    try {
      final observations =
          (await repository.getObservationsForEpisode(widget.episodeId))
              .dataOrNull ??
          const [];
      final recorded = observations
          .where((o) => o.id == observationId)
          .firstOrNull;
      if (recorded != null) {
        await CycleEntriesProjection().project(recorded);
      }
    } catch (_) {
      // Reported internally by the projection's own repository calls.
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Directionality(
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
        children: [
          Text(
            _t('Add a missing day', 'إضافة يوم فائت'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontFamily: AppTypography.serifFamily,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            _t('Which day?', 'أي يوم؟'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ActionChip(
            label: Text(
              _observedDate != null
                  ? '${_observedDate!.year}-${_observedDate!.month.toString().padLeft(2, '0')}-${_observedDate!.day.toString().padLeft(2, '0')}'
                  : _t('Choose a date', 'اختيار تاريخ'),
            ),
            onPressed: _pickDate,
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
              for (final option in const [
                (ObservationFlow.spotting, 'Spotting', 'تبقيع'),
                (ObservationFlow.light, 'Light', 'خفيف'),
                (ObservationFlow.medium, 'Medium', 'متوسط'),
                (ObservationFlow.heavy, 'Heavy', 'غزير'),
                (ObservationFlow.uncertain, "I'm not sure", 'لست متأكدة'),
              ])
                ChoiceChip(
                  label: Text(_t(option.$2, option.$3)),
                  selected: _flow == option.$1,
                  onSelected: (_) => setState(() => _flow = option.$1),
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
            onPressed: (_observedDate == null || _flow == null || _saving)
                ? null
                : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.haid,
            ),
            child: _saving
                ? const NiswahLoadingIndicator(
                    size: NiswahLoadingSize.small,
                    contrast: NiswahLoadingContrast.light,
                  )
                : Text(_t('Save', 'حفظ')),
          ),
        ],
      ),
    ),
  );
}

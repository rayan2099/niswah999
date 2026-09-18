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

/// PR #4 hardening, Blocker 6: no medically-motivated bound on how long
/// ago a real bleeding start/end can be reported — a technical bound is
/// still required by `showDatePicker`'s own API, so this is deliberately
/// generous (effectively "no meaningful restriction" for any real human
/// history) rather than the previous 2-year window, which contradicted
/// this very screen's own "however long ago that was" copy.
DateTime _earliestReportableDate(DateTime now) =>
    DateTime(now.year - 100, now.month, now.day);

/// Menstrual Data Integrity charter — Section 6's "Start Bleeding" UX:
/// only factual questions (when it started, how it is right now), never a
/// Fiqh conclusion ("Bleeding started," never "Haid started" — the Fiqh
/// classification is a separate, later layer that may not even be
/// resolvable yet if the Madhhab is unset). Returns true if a new episode
/// was actually started, so the caller (the dashboard) knows to refresh.
Future<bool> showStartBleedingSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _StartBleedingSheet(),
  );
  return result ?? false;
}

class _StartBleedingSheet extends StatefulWidget {
  const _StartBleedingSheet();
  @override
  State<_StartBleedingSheet> createState() => _StartBleedingSheetState();
}

class _StartBleedingSheetState extends State<_StartBleedingSheet> {
  DateTime? _startDate;
  ObservationFlow? _flow;
  bool _saving = false;
  String? _errorMessage;

  // PR #4 hardening, Blocker 1: generated once for this sheet instance and
  // reused on every retry (a failed attempt, a double-tap before the
  // first result is seen) — this is exactly what lets the RPC recognize a
  // retry as the *same* logical action instead of a new one.
  final String _clientOperationId = const Uuid().v4();

  bool get _arabic => AppLocaleController.instance.isArabic;

  Future<void> _pickOtherDate() async {
    final now = AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: _earliestReportableDate(now),
      lastDate: now,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    final startDate = _startDate;
    final flow = _flow;
    if (startDate == null || flow == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
      if (userId == null) {
        throw StateError('Not signed in.');
      }

      final now = AppClock.now();
      // PR #4 completion wave, Fix B: a real IANA identifier
      // ("Asia/Riyadh") when the platform can provide one — never a bare
      // abbreviation ("AST"), which is ambiguous and was never usable for
      // future local-time interpretation (only for the historical-offset
      // math below, which utcOffsetMinutes already covers exactly).
      // Best-effort: null if genuinely unavailable, matching the schema's
      // own nullable `timezone` column.
      final timezone = await DeviceTimezone.currentId();
      final utcOffsetMinutes = now.timeZoneOffset.inMinutes;

      // PR #4 completion wave, Fix D: persisted *before* the RPC is sent
      // — if the process dies between the server committing this and the
      // response reaching this sheet, the next app start's reconciliation
      // replays this exact operation id rather than a fresh one, which
      // would otherwise look like a genuinely new request.
      await PendingBleedingOperationStore.savePending(
        PendingBleedingOperation(
          operationId: _clientOperationId,
          type: PendingBleedingOperationType.startEpisode,
          params: {
            'startDate': startDate.toIso8601String(),
            'startPrecision': ObservationPrecision.dateOnly.value,
            'flow': flow.value,
            'observationPrecision': ObservationPrecision.dateOnly.value,
            'timezone': timezone,
            'utcOffsetMinutes': utcOffsetMinutes,
          },
          createdAt: now,
        ),
      );

      final result = await BleedingEpisodeRepositoryImpl().startEpisode(
        clientOperationId: _clientOperationId,
        startDate: startDate,
        startPrecision: ObservationPrecision.dateOnly,
        flow: flow,
        observationPrecision: ObservationPrecision.dateOnly,
        timezone: timezone,
        utcOffsetMinutes: utcOffsetMinutes,
      );
      await PendingBleedingOperationStore.clearPending(_clientOperationId);

      // Best-effort: the canonical episode/observation are already saved
      // at this point (Section 7's "prove what succeeded") — a projection
      // failure must not make the dashboard claim the whole action
      // failed when the real save already succeeded. Full durability
      // here is Commit F's job once the dashboard reads canonical data
      // directly; until then this is a best-effort mirror, not the
      // source of truth (Blocker 12).
      try {
        await CycleEntriesProjection().project(result.observation);
      } catch (_) {
        // Reported internally by the projection's own repository calls.
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ActiveEpisodeAlreadyExistsException {
      // This specific operation can never succeed under these params —
      // a *different* operation genuinely holds the one-open-episode
      // slot — so leaving it pending would only make reconciliation
      // retry a call doomed to repeat this same conflict.
      await PendingBleedingOperationStore.clearPending(_clientOperationId);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'You already have an active period being tracked.',
          'لديكِ بالفعل دورة نشطة قيد التتبع.',
        );
      });
    } catch (_) {
      // Left pending on any other failure (network, etc.) — either she
      // retries here (same operation id, same sheet), or, if the app
      // dies before that, the next start-up's reconciliation replays it.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'Could not save. Please try again.',
          'تعذر الحفظ. يرجى المحاولة مجدداً.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

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
          children: [
            Text(
              _t('Bleeding started', 'بدأ النزيف'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: AppTypography.serifFamily,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              _t('When did it start?', 'متى بدأ؟'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(_t('Today', 'اليوم')),
                  selected:
                      _startDate != null &&
                      DateUtils.isSameDay(_startDate, today),
                  onSelected: (_) => setState(() => _startDate = today),
                ),
                ChoiceChip(
                  label: Text(_t('Yesterday', 'أمس')),
                  selected:
                      _startDate != null &&
                      DateUtils.isSameDay(_startDate, yesterday),
                  onSelected: (_) => setState(() => _startDate = yesterday),
                ),
                ActionChip(
                  label: Text(
                    _startDate != null &&
                            !DateUtils.isSameDay(_startDate, today) &&
                            !DateUtils.isSameDay(_startDate, yesterday)
                        ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                        : _t('Choose a date', 'اختيار تاريخ'),
                  ),
                  onPressed: _pickOtherDate,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _t('How is the bleeding right now?', 'كيف حال النزيف الآن؟'),
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
              onPressed: (_startDate == null || _flow == null || _saving)
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
}

/// Section 6's end-of-episode counterpart: only "when did it stop?" — no
/// Fiqh conclusion here either. [episodeStartDate] bounds the date picker
/// so the user cannot even attempt an impossible date (Blocker 11) — the
/// canonical `end_bleeding_episode` RPC still re-validates this itself as
/// defense in depth.
Future<bool> showEndBleedingSheet(
  BuildContext context, {
  required String episodeId,
  required DateTime episodeStartDate,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EndBleedingSheet(
      episodeId: episodeId,
      episodeStartDate: episodeStartDate,
    ),
  );
  return result ?? false;
}

class _EndBleedingSheet extends StatefulWidget {
  const _EndBleedingSheet({
    required this.episodeId,
    required this.episodeStartDate,
  });
  final String episodeId;
  final DateTime episodeStartDate;
  @override
  State<_EndBleedingSheet> createState() => _EndBleedingSheetState();
}

class _EndBleedingSheetState extends State<_EndBleedingSheet> {
  DateTime? _endDate;
  bool _saving = false;
  String? _errorMessage;

  final String _clientOperationId = const Uuid().v4();

  bool get _arabic => AppLocaleController.instance.isArabic;

  Future<void> _pickOtherDate() async {
    final now = AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now,
      firstDate: widget.episodeStartDate,
      lastDate: now,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    final endDate = _endDate;
    if (endDate == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final utcOffsetMinutes = now.timeZoneOffset.inMinutes;

    // PR #4 completion wave, Fix D: persisted before the RPC is sent —
    // see the Start sheet's own note on why (app-kill recovery via the
    // next start-up's reconciliation).
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

    // Atomic: the episode's state transition and its closing (flow: none)
    // observation are created together by the RPC — never a separate
    // client-issued INSERT that could leave the episode ended with no
    // factual record of its own closure.
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

    if (result != null) {
      await PendingBleedingOperationStore.clearPending(_clientOperationId);
      // Gives the still-in-use legacy CycleCalculationService/dashboard
      // engine (which reads cycle_entries, not this table) the "ended"
      // signal it needs via the same projection every other observation
      // goes through — never a second, separately-authored write. The
      // closing observation already exists (created atomically above);
      // this only mirrors it, and a failure here does not mean the real
      // save failed.
      final observations = await repository.getObservationsForEpisode(
        widget.episodeId,
      );
      final closingObservation = observations
          .where((o) => o.id == result.closingObservationId)
          .firstOrNull;
      if (closingObservation != null) {
        try {
          await CycleEntriesProjection().project(closingObservation);
        } catch (_) {
          // Reported internally by the projection's own repository calls.
        }
      }

      // Commit E9 — see daily_checkin_sheet.dart's identical note: ending
      // an episode from this sheet must cancel its reminder exactly the
      // same way ending it from the daily check-in flow does.
      final signedInUserId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
      if (signedInUserId != null) {
        await NotificationService.instance.cancel(
          ActiveBleedingReminderScheduler.reminderId(
            userId: signedInUserId,
            episodeId: widget.episodeId,
            localDay: BleedingEpisodeRepositoryImpl.localToday(
              utcOffsetMinutes,
            ),
          ),
        );
      }
    }

    if (!mounted) return;
    if (result == null) {
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'Could not save. Please try again.',
          'تعذر الحفظ. يرجى المحاولة مجدداً.',
        );
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayReachable = !yesterday.isBefore(widget.episodeStartDate);

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
          children: [
            Text(
              _t('Bleeding stopped', 'توقف النزيف'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: AppTypography.serifFamily,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
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
                  selected:
                      _endDate != null && DateUtils.isSameDay(_endDate, today),
                  onSelected: (_) => setState(() => _endDate = today),
                ),
                // Blocker 11: never offer a choice the canonical episode
                // start itself makes impossible — disabled, not hidden,
                // so the constraint is visible rather than merely absent.
                ChoiceChip(
                  label: Text(_t('Yesterday', 'أمس')),
                  selected:
                      _endDate != null &&
                      DateUtils.isSameDay(_endDate, yesterday),
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
                  onPressed: _pickOtherDate,
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
              onPressed: (_endDate == null || _saving) ? null : _submit,
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
}

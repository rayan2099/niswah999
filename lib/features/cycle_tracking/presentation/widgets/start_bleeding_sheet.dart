import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/cycle_entries_projection.dart';
import '../../domain/entities/bleeding_episode.dart';

String _t(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

/// Menstrual Data Integrity charter, Commit D — Section 6's "Start
/// Bleeding" UX: only factual questions (when it started, how it is right
/// now), never a Fiqh conclusion ("Bleeding started," never "Haid
/// started" — the Fiqh classification is a separate, later layer that may
/// not even be resolvable yet if the Madhhab is unset). Returns true if a
/// new episode was actually started, so the caller (the dashboard) knows
/// to refresh.
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

  bool get _arabic => AppLocaleController.instance.isArabic;

  Future<void> _pickOtherDate() async {
    final now = AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2, now.month, now.day),
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
      // Dart's core DateTime has no true IANA timezone identifier — only
      // a platform-dependent abbreviation. Honest limitation, not a
      // fabrication: this is what the platform actually gives us, stored
      // as-is rather than invented.
      final timezone = now.timeZoneName;

      final result = await BleedingEpisodeRepositoryImpl().startEpisode(
        startDate: startDate,
        startPrecision: ObservationPrecision.dateOnly,
        flow: flow,
        observationPrecision: ObservationPrecision.dateOnly,
        timezone: timezone,
      );

      // Best-effort: the canonical episode/observation are already saved
      // at this point (Section 7's "prove what succeeded") — a projection
      // failure must not make the dashboard claim the whole action
      // failed when the real save already succeeded.
      try {
        await CycleEntriesProjection().project(result.observation);
      } catch (_) {
        // Reported internally by the projection's own repository calls.
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ActiveEpisodeAlreadyExistsException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = _t(
          'You already have an active period being tracked.',
          'لديكِ بالفعل دورة نشطة قيد التتبع.',
        );
      });
    } catch (_) {
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
/// Fiqh conclusion here either.
Future<bool> showEndBleedingSheet(
  BuildContext context, {
  required String episodeId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EndBleedingSheet(episodeId: episodeId),
  );
  return result ?? false;
}

class _EndBleedingSheet extends StatefulWidget {
  const _EndBleedingSheet({required this.episodeId});
  final String episodeId;
  @override
  State<_EndBleedingSheet> createState() => _EndBleedingSheetState();
}

class _EndBleedingSheetState extends State<_EndBleedingSheet> {
  DateTime? _endDate;
  bool _saving = false;
  String? _errorMessage;

  bool get _arabic => AppLocaleController.instance.isArabic;

  Future<void> _pickOtherDate() async {
    final now = AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2, now.month, now.day),
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

    final repository = BleedingEpisodeRepositoryImpl();
    final result = await repository.endEpisode(
      episodeId: widget.episodeId,
      endDate: endDate,
      endPrecision: ObservationPrecision.dateOnly,
      endSource: ObservationSource.userObserved,
    );

    if (result != null) {
      // "Bleeding stopped on X" is itself a real, factual observation
      // (flow: none — an explicit "not bleeding," distinct from an
      // unanswered check-in), not merely metadata on the episode. Also
      // gives the still-in-use legacy CycleCalculationService/dashboard
      // engine (which reads cycle_entries, not this table) the "ended"
      // signal it needs via the same projection every other observation
      // goes through — never a second, separately-authored write.
      final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
      if (userId != null) {
        final observation = await repository.addObservation(
          BleedingObservation(
            userId: userId,
            episodeId: widget.episodeId,
            observedDate: endDate,
            precision: ObservationPrecision.dateOnly,
            flow: ObservationFlow.none,
            source: ObservationSource.userObserved,
            timezone: AppClock.now().timeZoneName,
          ),
        );
        if (observation != null) {
          try {
            await CycleEntriesProjection().project(observation);
          } catch (_) {
            // Reported internally by the projection's own repository calls.
          }
        }
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
                ChoiceChip(
                  label: Text(_t('Yesterday', 'أمس')),
                  selected:
                      _endDate != null &&
                      DateUtils.isSameDay(_endDate, yesterday),
                  onSelected: (_) => setState(() => _endDate = yesterday),
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

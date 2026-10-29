import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../../../../core/utils/device_timezone.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../data/repositories/episode_correction_repository.dart';
import '../../domain/entities/bleeding_episode.dart';
import 'discard_edit_guard.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

const _months = [
  ['January', 'يناير'],
  ['February', 'فبراير'],
  ['March', 'مارس'],
  ['April', 'أبريل'],
  ['May', 'مايو'],
  ['June', 'يونيو'],
  ['July', 'يوليو'],
  ['August', 'أغسطس'],
  ['September', 'سبتمبر'],
  ['October', 'أكتوبر'],
  ['November', 'نوفمبر'],
  ['December', 'ديسمبر'],
];

/// "3 October 2026" / "3 أكتوبر 2026" — always Western digits.
String episodeDateLabel(DateTime date) {
  final month = _months[date.month - 1];
  return '${date.day} ${_t(month[0], month[1])} ${date.year}';
}

/// What the edit sheet did, so the caller can reload.
enum EpisodeEditAction { startMoved, endMoved, reopened, removed }

/// Edit one recorded period: move its start or end, undo an end she did
/// not mean, or remove it (cases PT-027, PT-051..PT-054, PT-056, PT-057).
///
/// Every change goes through [EpisodeCorrectionRepository]; nothing here
/// writes directly. A change that would take out entries she recorded is
/// previewed and needs her confirmation; a change made on another device in
/// the meantime, an offline phone or a server refusal leaves everything as
/// it was and says so, keeping her selection.
///
/// [onChanged] runs after every saved change, including an Undo of a
/// removal tapped after the sheet closed, so the caller can reload.
Future<EpisodeEditAction?> showEpisodeEditSheet(
  BuildContext context, {
  required BleedingEpisode episode,
  required bool isLatestEpisode,
  required bool hasOpenEpisode,
  VoidCallback? onChanged,
  BleedingEpisodeRepositoryImpl? episodes,
  @visibleForTesting EpisodeCorrectionRepository? repositoryOverride,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<EpisodeEditAction>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EpisodeEditSheet(
      episode: episode,
      isLatestEpisode: isLatestEpisode,
      hasOpenEpisode: hasOpenEpisode,
      messenger: messenger,
      onChanged: onChanged,
      repository: repositoryOverride ?? EpisodeCorrectionRepository(),
      episodes: episodes ?? BleedingEpisodeRepositoryImpl(),
    ),
  );
}

@visibleForTesting
class EpisodeEditSheet extends StatefulWidget {
  const EpisodeEditSheet({
    super.key,
    required this.episode,
    required this.isLatestEpisode,
    required this.hasOpenEpisode,
    required this.repository,
    required this.episodes,
    this.messenger,
    this.onChanged,
  });

  final BleedingEpisode episode;
  final bool isLatestEpisode;
  final bool hasOpenEpisode;
  final EpisodeCorrectionRepository repository;
  final BleedingEpisodeRepositoryImpl episodes;
  final ScaffoldMessengerState? messenger;
  final VoidCallback? onChanged;

  @override
  State<EpisodeEditSheet> createState() => _EpisodeEditSheetState();
}

enum _Mode { menu, start, end }

class _EpisodeEditSheetState extends State<EpisodeEditSheet> {
  _Mode _mode = _Mode.menu;
  DateTime? _newDate;
  ObservationFlow? _flow;
  bool _needsFlow = false;
  bool _saving = false;
  String? _message;

  // One operation id per intended change; a retry of the same change
  // (double tap, "Try again" after offline) reuses it, a different change
  // gets a new one.
  String _operationId = const Uuid().v4();
  String? _operationKey;

  BleedingEpisode get _episode => widget.episode;
  bool get _arabic => AppLocaleController.instance.isArabic;
  bool get _ended => _episode.lifecycleStatus == LifecycleStatus.ended;

  String _operationFor(String key) {
    if (_operationKey != key) {
      _operationKey = key;
      _operationId = const Uuid().v4();
    }
    return _operationId;
  }

  DateTime get _today {
    final now = AppClock.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate(_Mode mode) async {
    final today = _today;
    final DateTime first;
    final DateTime last;
    final DateTime initial;
    if (mode == _Mode.start) {
      first = DateTime(today.year - 100, today.month, today.day);
      last = _episode.endDate != null && _episode.endDate!.isBefore(today)
          ? _episode.endDate!
          : today;
      initial = _episode.startDate.isAfter(last) ? last : _episode.startDate;
    } else {
      first = _episode.startDate;
      last = today;
      final current = _episode.endDate ?? today;
      initial = current.isAfter(last) ? last : current;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: mode == _Mode.start
          ? _t('When did this period start?', 'متى بدأ هذا الحيض؟')
          : _t('First day with no bleeding', 'أول يوم بلا دم'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _mode = mode;
      _newDate = calendarDay(picked);
      _flow = null;
      _message = null;
      _needsFlow = false;
    });
    if (mode == _Mode.start) await _checkNeedsFlow(calendarDay(picked));
  }

  /// A new start day with no bleeding recorded on it needs a flow for the
  /// entry the server adds there; a day that already has one does not, so
  /// she is only asked when the answer is actually used.
  Future<void> _checkNeedsFlow(DateTime day) async {
    final result = await widget.episodes.getObservationsForEpisode(
      _episode.id!,
    );
    if (!mounted) return;
    final observations = result.dataOrNull;
    final supersededIds = {
      for (final o in observations ?? const <BleedingObservation>[])
        if (o.supersedesId != null) o.supersedesId!,
    };
    final hasEntry = (observations ?? const <BleedingObservation>[]).any(
      (o) =>
          !supersededIds.contains(o.id) &&
          calendarDaysBetween(o.observedDate, day) == 0 &&
          o.flow != ObservationFlow.none,
    );
    // An unreadable episode asks: a flow sent unnecessarily is ignored by
    // the server, a missing one would fail the save.
    setState(() => _needsFlow = observations == null || !hasEntry);
  }

  Future<void> _saveDateChange({bool retractConflicting = false}) async {
    final date = _newDate;
    if (date == null || _saving) return;
    if (_mode == _Mode.start && _needsFlow && _flow == null) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final offset = now.timeZoneOffset.inMinutes;
    final key =
        '${_mode.name}:${date.toIso8601String()}:${_flow?.value}:'
        '$retractConflicting';
    final result = _mode == _Mode.start
        ? await widget.repository.correctStart(
            clientOperationId: _operationFor(key),
            episode: _episode,
            newStartDate: date,
            flow: _flow ?? ObservationFlow.uncertain,
            timezone: timezone,
            utcOffsetMinutes: offset,
            retractConflicting: retractConflicting,
          )
        : await widget.repository.correctEnd(
            clientOperationId: _operationFor(key),
            episode: _episode,
            newEndDate: date,
            timezone: timezone,
            utcOffsetMinutes: offset,
            retractConflicting: retractConflicting,
          );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.status == EpisodeEditStatus.needsConfirmation) {
      final confirmed = await _confirmRetraction(result.conflictingCount);
      if (confirmed == true && mounted) {
        await _saveDateChange(retractConflicting: true);
      }
      return;
    }
    if (result.saved) {
      _finish(
        _mode == _Mode.start
            ? EpisodeEditAction.startMoved
            : EpisodeEditAction.endMoved,
        _mode == _Mode.start
            ? _t('Start date updated.', 'تم تعديل تاريخ البداية.')
            : _t('End date updated.', 'تم تعديل تاريخ النهاية.'),
      );
      return;
    }
    setState(() => _message = _messageFor(result));
  }

  Future<bool?> _confirmRetraction(int? count) {
    final n = count ?? 0;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _t('Some entries fall outside', 'بعض الإدخالات خارج المدة'),
        ),
        content: Text(
          _mode == _Mode.start
              ? _t(
                  '$n ${n == 1 ? 'entry was' : 'entries were'} recorded before '
                      '${episodeDateLabel(_newDate!)}. They will be taken off '
                      'your calendar. The change is kept in this period\'s '
                      'history.',
                  'يوجد $n من الإدخالات قبل ${episodeDateLabel(_newDate!)}. '
                      'ستُزال من تقويمكِ، ويبقى هذا التعديل محفوظاً في سجل '
                      'هذا الحيض.',
                )
              : _t(
                  '$n ${n == 1 ? 'entry with bleeding was' : 'entries with bleeding were'} '
                      'recorded on or after ${episodeDateLabel(_newDate!)}. '
                      'They will be taken off your calendar. The change is '
                      'kept in this period\'s history.',
                  'يوجد $n من إدخالات الدم في ${episodeDateLabel(_newDate!)} '
                      'أو بعده. ستُزال من تقويمكِ، ويبقى هذا التعديل محفوظاً '
                      'في سجل هذا الحيض.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('Keep my entries', 'إبقاء إدخالاتي')),
          ),
          FilledButton(
            key: const Key('episode-edit-confirm-retract'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('Change dates', 'تعديل التواريخ')),
          ),
        ],
      ),
    );
  }

  Future<void> _reopen() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await widget.repository.reopen(
      clientOperationId: _operationFor('reopen'),
      episodeId: _episode.id!,
      revisionToken: _episode.revisionToken,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.saved) {
      _finish(
        EpisodeEditAction.reopened,
        _t('This period is ongoing again.', 'هذا الحيض مستمر من جديد.'),
      );
      return;
    }
    setState(() => _message = _messageFor(result));
  }

  Future<void> _remove() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Remove this period?', 'إزالة هذا الحيض؟')),
        content: Text(
          _t(
            'The period ${_rangeLabel()} and every entry in it will be '
                'taken off your calendar. Predictions, reminders and '
                'Insights will be worked out again without it. You can undo '
                'this right after.',
            'سيُزال الحيض ${_rangeLabel()} وكل إدخالاته من تقويمكِ، وتُعاد '
                'التوقعات والتذكيرات والإحصاءات بدونه. يمكنكِ التراجع مباشرة '
                'بعد الإزالة.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            key: const Key('episode-edit-confirm-remove'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.haid),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('Remove', 'إزالة')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await widget.repository.remove(
      clientOperationId: _operationFor('remove'),
      episode: _episode,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!result.saved) {
      setState(() => _message = _messageFor(result));
      return;
    }
    final repository = widget.repository;
    final messenger = widget.messenger;
    final onChanged = widget.onChanged;
    final episodeId = _episode.id!;
    final restoreOperation = const Uuid().v4();
    Navigator.of(context).pop(EpisodeEditAction.removed);
    onChanged?.call();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('episode-removed-snackbar'),
        duration: const Duration(seconds: 8),
        content: Text(_t('Period removed.', 'تمت إزالة الحيض.')),
        action: SnackBarAction(
          label: _t('Undo', 'تراجع'),
          onPressed: () async {
            final restored = await repository.restore(
              clientOperationId: restoreOperation,
              episodeId: episodeId,
            );
            onChanged?.call();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  restored.saved
                      ? _t('Period restored.', 'تمت استعادة الحيض.')
                      : _messageFor(restored),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _finish(EpisodeEditAction action, String confirmation) {
    final messenger = widget.messenger;
    Navigator.of(context).pop(action);
    widget.onChanged?.call();
    messenger?.showSnackBar(SnackBar(content: Text(confirmation)));
  }

  String _rangeLabel() {
    final start = episodeDateLabel(_episode.startDate);
    final end = _episode.endDate;
    if (end == null) {
      return _t('that started on $start', 'الذي بدأ في $start');
    }
    return _t(
      'from $start to ${episodeDateLabel(end)}',
      'من $start إلى ${episodeDateLabel(end)}',
    );
  }

  static String _messageFor(EpisodeEditResult result) {
    switch (result.status) {
      case EpisodeEditStatus.offline:
        return _t(
          "You're offline, so nothing was changed. Connect to the internet "
              'and try again.',
          'أنتِ غير متصلة بالإنترنت، لذلك لم يتغير شيء. اتصلي بالإنترنت '
              'وحاولي مرة أخرى.',
        );
      case EpisodeEditStatus.changedElsewhere:
        return _t(
          'This period was changed on another device. Close this and open '
              'it again to see the latest version.',
          'تم تعديل هذا الحيض من جهاز آخر. أغلقي هذه النافذة وافتحيها مرة '
              'أخرى لرؤية آخر نسخة.',
        );
      case EpisodeEditStatus.rejected:
        final message = result.serverMessage ?? '';
        if (message.contains('overlap') || message.contains('would cover')) {
          return _t(
            'These dates overlap another period. Change that period first.',
            'هذه التواريخ تتداخل مع حيض آخر. عدّلي ذلك الحيض أولاً.',
          );
        }
        if (message.contains('future')) {
          return _t('That date is in the future.', 'هذا التاريخ في المستقبل.');
        }
        if (message.contains('another episode is open')) {
          return _t(
            'End your current period before reopening this one.',
            'أنهي حيضكِ الحالي قبل إعادة فتح هذا الحيض.',
          );
        }
        if (message.contains('later episode exists')) {
          return _t(
            'Only your most recent period can be reopened.',
            'يمكن إعادة فتح آخر حيض فقط.',
          );
        }
        return _t(
          "This change couldn't be saved. Your records are unchanged.",
          'تعذّر حفظ هذا التعديل. سجلاتكِ لم تتغير.',
        );
      case EpisodeEditStatus.needsConfirmation:
      case EpisodeEditStatus.saved:
        return '';
    }
  }

  /// A date she picked but has not saved yet.
  bool get _hasUnsavedEdit => _mode != _Mode.menu && _newDate != null;

  @override
  Widget build(BuildContext context) {
    return DiscardEditGuard(
      hasUnsavedChange: _hasUnsavedEdit,
      saving: _saving,
      child: _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
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
                  _t('Edit this period', 'تعديل هذا الحيض'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: AppTypography.serifFamily,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _ended
                      ? _t(
                          'Started ${episodeDateLabel(_episode.startDate)} · '
                              'no bleeding from ${episodeDateLabel(_episode.endDate!)}',
                          'بدأ ${episodeDateLabel(_episode.startDate)} · بلا دم '
                              'من ${episodeDateLabel(_episode.endDate!)}',
                        )
                      : _t(
                          'Started ${episodeDateLabel(_episode.startDate)} · ongoing',
                          'بدأ ${episodeDateLabel(_episode.startDate)} · مستمر',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (_mode == _Mode.menu) ..._menu() else ..._dateEditor(),
                if (_message != null && _message!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      key: const Key('episode-edit-message'),
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('episode-edit-close'),
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  child: Text(_t('Close', 'إغلاق')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _menu() => [
    _ActionTile(
      key: const Key('episode-edit-start'),
      icon: Icons.first_page_rounded,
      title: _t('Change start date', 'تغيير تاريخ البداية'),
      enabled: !_saving,
      onTap: () => _pickDate(_Mode.start),
    ),
    if (_ended)
      _ActionTile(
        key: const Key('episode-edit-end'),
        icon: Icons.last_page_rounded,
        title: _t('Change end date', 'تغيير تاريخ النهاية'),
        enabled: !_saving,
        onTap: () => _pickDate(_Mode.end),
      ),
    if (_ended && widget.isLatestEpisode && !widget.hasOpenEpisode)
      _ActionTile(
        key: const Key('episode-edit-reopen'),
        icon: Icons.undo_rounded,
        title: _t("I'm still bleeding", 'ما زال الدم مستمراً'),
        subtitle: _t(
          'Undo the end. The period continues until you end it again.',
          'التراجع عن النهاية. يستمر الحيض حتى تنهيه مرة أخرى.',
        ),
        enabled: !_saving,
        onTap: _reopen,
      ),
    _ActionTile(
      key: const Key('episode-edit-remove'),
      icon: Icons.delete_outline_rounded,
      title: _t('Remove this period', 'إزالة هذا الحيض'),
      subtitle: _t(
        'For a period recorded by mistake. You can undo it.',
        'لحيض سُجّل بالخطأ. يمكنكِ التراجع.',
      ),
      color: AppColors.haid,
      enabled: !_saving,
      onTap: _remove,
    ),
    if (_saving)
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator()),
      ),
  ];

  List<Widget> _dateEditor() {
    final date = _newDate!;
    final isStart = _mode == _Mode.start;
    final canSave = !_saving && (!isStart || !_needsFlow || _flow != null);
    return [
      Text(
        isStart
            ? _t('New start date', 'تاريخ البداية الجديد')
            : _t('First day with no bleeding', 'أول يوم بلا دم'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        key: const Key('episode-edit-date'),
        onPressed: _saving ? null : () => _pickDate(_mode),
        icon: const Icon(Icons.calendar_today_rounded, size: 18),
        label: Text(episodeDateLabel(date)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
      if (isStart && _needsFlow) ...[
        const SizedBox(height: 16),
        Text(
          _t('How was the flow that day?', 'كيف كان الدم في ذلك اليوم؟'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final flow in const [
              ObservationFlow.spotting,
              ObservationFlow.light,
              ObservationFlow.medium,
              ObservationFlow.heavy,
              ObservationFlow.uncertain,
            ])
              ChoiceChip(
                key: Key('episode-edit-flow-${flow.value}'),
                label: Text(_flowLabel(flow)),
                selected: _flow == flow,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _flow = flow),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('episode-edit-save'),
        onPressed: canSave ? _saveDateChange : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.tahara,
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(_t('Save', 'حفظ')),
      ),
      TextButton(
        onPressed: _saving
            ? null
            : () => setState(() {
                _mode = _Mode.menu;
                _message = null;
              }),
        child: Text(_t('Back', 'رجوع')),
      ),
    ];
  }

  static String _flowLabel(ObservationFlow flow) => switch (flow) {
    ObservationFlow.uncertain => _t("I'm not sure", 'لست متأكدة'),
    ObservationFlow.none => _t('None', 'لا يوجد'),
    ObservationFlow.spotting => _t('Spotting', 'تبقيع'),
    ObservationFlow.light => _t('Light', 'خفيف'),
    ObservationFlow.medium => _t('Medium', 'متوسط'),
    ObservationFlow.heavy => _t('Heavy', 'غزير'),
  };
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    required this.enabled,
    this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      minVerticalPadding: 12,
      leading: Icon(icon, color: color ?? AppColors.tahara),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
    );
  }
}

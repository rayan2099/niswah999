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
enum EpisodeEditAction {
  startMoved,
  endMoved,
  reopened,
  removed,
  split,
  merged,
}

/// Edit one recorded period: move its start or end, undo an end she did
/// not mean, remove it (cases PT-027, PT-051..PT-054, PT-056, PT-057),
/// split it in two or join it with the next one (PT-045, PT-046).
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

enum _Mode { menu, start, end, split }

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

  // Split: the day the second period started (one of her recorded
  // bleeding days) and the first part's first clean day, or unknown.
  List<DateTime>? _bleedingDays;
  DateTime? _secondStart;
  DateTime? _firstEnd;
  bool _firstEndUnknown = false;

  // Merge: the period right after this one, when there is one.
  BleedingEpisode? _nextEpisode;

  @override
  void initState() {
    super.initState();
    if (_ended) _loadNextEpisode();
  }

  Future<void> _loadNextEpisode() async {
    final result = await widget.episodes.getEpisodesForUser(_episode.userId);
    if (!mounted) return;
    BleedingEpisode? next;
    for (final e in result.dataOrNull ?? const <BleedingEpisode>[]) {
      if (e.id == null || e.id == _episode.id) continue;
      if (!e.startDate.isAfter(_episode.startDate)) continue;
      if (next == null || e.startDate.isBefore(next.startDate)) next = e;
    }
    // Unreadable list: no merge offered rather than a guessed neighbour.
    setState(() => _nextEpisode = next);
  }

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

  Future<void> _openSplit() async {
    setState(() {
      _mode = _Mode.split;
      _secondStart = null;
      _firstEnd = null;
      _firstEndUnknown = false;
      _bleedingDays = null;
      _message = null;
    });
    final result = await widget.episodes.getObservationsForEpisode(
      _episode.id!,
    );
    if (!mounted) return;
    final observations = result.dataOrNull;
    if (observations == null) {
      setState(() {
        _bleedingDays = const [];
        _message = _messageFor(
          const EpisodeEditResult(EpisodeEditStatus.offline),
        );
      });
      return;
    }
    final supersededIds = {
      for (final o in observations)
        if (o.supersedesId != null) o.supersedesId!,
    };
    final end = _episode.endDate;
    final days = {
      for (final o in observations)
        if (!supersededIds.contains(o.id) &&
            o.flow != ObservationFlow.none &&
            o.observedDate.isAfter(_episode.startDate) &&
            (end == null || o.observedDate.isBefore(end)))
          calendarDay(o.observedDate),
    }.toList()..sort();
    setState(() => _bleedingDays = days);
  }

  Future<void> _pickFirstEnd() async {
    final second = _secondStart!;
    final first = _episode.startDate.add(const Duration(days: 1));
    final last = second.subtract(const Duration(days: 1));
    final current = _firstEnd ?? last;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: last,
      helpText: _t(
        'First day with no bleeding (first period)',
        'أول يوم بلا دم (الحيض الأول)',
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _firstEnd = calendarDay(picked);
      _firstEndUnknown = false;
      _message = null;
    });
  }

  /// The first part needs at least one day between its start and the
  /// second start for a known clean day.
  bool get _firstEndPickable =>
      _secondStart != null &&
      calendarDaysBetween(_episode.startDate, _secondStart!) >= 2;

  Future<void> _saveSplit({bool confirm = false}) async {
    final second = _secondStart;
    if (second == null || _saving) return;
    if (_firstEnd == null && !_firstEndUnknown) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final now = AppClock.now();
    final timezone = await DeviceTimezone.currentId();
    final key =
        'split:${second.toIso8601String()}:'
        '${_firstEndUnknown ? 'unknown' : _firstEnd!.toIso8601String()}:'
        '$confirm';
    final result = await widget.repository.splitEpisode(
      clientOperationId: _operationFor(key),
      episode: _episode,
      secondStartDate: second,
      firstEndDate: _firstEndUnknown ? null : _firstEnd,
      timezone: timezone,
      utcOffsetMinutes: now.timeZoneOffset.inMinutes,
      confirm: confirm,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.status == EpisodeEditStatus.needsConfirmation) {
      final n = result.conflictingCount ?? 0;
      final confirmed = await _confirmMove(
        title: _t('Split this period?', 'تقسيم هذا الحيض؟'),
        body: _t(
          '$n ${n == 1 ? 'entry' : 'entries'} from '
              '${episodeDateLabel(second)} on will move to a new period. '
              'Nothing is deleted or changed, and days you did not record '
              'stay unrecorded. You can undo this right after.',
          'ستنتقل $n من الإدخالات من ${episodeDateLabel(second)} فما بعد '
              'إلى حيض جديد. لا يُحذف شيء ولا يتغير، والأيام التي لم '
              'تسجليها تبقى غير مسجّلة. يمكنكِ التراجع مباشرة بعد ذلك.',
        ),
        action: _t('Split', 'تقسيم'),
        confirmKey: const Key('episode-split-confirm'),
      );
      if (confirmed == true && mounted) await _saveSplit(confirm: true);
      return;
    }
    if (!result.saved) {
      setState(() => _message = _messageFor(result));
      return;
    }
    final repository = widget.repository;
    final episodeId = _episode.id!;
    final secondId = result.secondEpisodeId;
    final revisionId = result.revisionId;
    final undoOperation = const Uuid().v4();
    _finishWithUndo(
      EpisodeEditAction.split,
      _t('Period split in two.', 'تم تقسيم الحيض إلى حيضين.'),
      undo: secondId == null || revisionId == null
          ? null
          : () => repository.undoSplit(
              clientOperationId: undoOperation,
              episodeId: episodeId,
              secondEpisodeId: secondId,
              splitRevisionId: revisionId,
            ),
      undone: _t('Split undone.', 'تم التراجع عن التقسيم.'),
    );
  }

  Future<void> _merge({bool confirm = false}) async {
    final next = _nextEpisode;
    if (next == null || _saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await widget.repository.mergeEpisodes(
      clientOperationId: _operationFor('merge:${next.id}:$confirm'),
      first: _episode,
      second: next,
      confirm: confirm,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.status == EpisodeEditStatus.needsConfirmation) {
      final n = result.conflictingCount ?? 0;
      final confirmed = await _confirmMove(
        title: _t('Join these periods?', 'دمج هذين الحيضين؟'),
        body: _t(
          'The period that started ${episodeDateLabel(next.startDate)} and '
              'its $n ${n == 1 ? 'entry' : 'entries'} will become part of '
              'this one. Nothing is deleted or changed, and days you did '
              'not record between them stay unrecorded. You can undo this '
              'right after.',
          'سيصبح الحيض الذي بدأ في ${episodeDateLabel(next.startDate)} '
              'وإدخالاته ($n) جزءاً من هذا الحيض. لا يُحذف شيء ولا يتغير، '
              'والأيام التي لم تسجليها بينهما تبقى غير مسجّلة. يمكنكِ '
              'التراجع مباشرة بعد ذلك.',
        ),
        action: _t('Join', 'دمج'),
        confirmKey: const Key('episode-merge-confirm'),
      );
      if (confirmed == true && mounted) await _merge(confirm: true);
      return;
    }
    if (!result.saved) {
      setState(() => _message = _messageFor(result));
      return;
    }
    final repository = widget.repository;
    final episodeId = _episode.id!;
    final revisionId = result.revisionId;
    final undoOperation = const Uuid().v4();
    _finishWithUndo(
      EpisodeEditAction.merged,
      _t('Periods joined.', 'تم دمج الحيضين.'),
      undo: revisionId == null
          ? null
          : () => repository.undoMerge(
              clientOperationId: undoOperation,
              episodeId: episodeId,
              mergeRevisionId: revisionId,
            ),
      undone: _t('Join undone.', 'تم التراجع عن الدمج.'),
    );
  }

  Future<bool?> _confirmMove({
    required String title,
    required String body,
    required String action,
    required Key confirmKey,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  /// Closes the sheet and offers Undo in a snackbar that outlives it.
  void _finishWithUndo(
    EpisodeEditAction action,
    String confirmation, {
    required Future<EpisodeEditResult> Function()? undo,
    required String undone,
  }) {
    final messenger = widget.messenger;
    final onChanged = widget.onChanged;
    Navigator.of(context).pop(action);
    onChanged?.call();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('episode-moved-snackbar'),
        duration: const Duration(seconds: 8),
        content: Text(confirmation),
        action: undo == null
            ? null
            : SnackBarAction(
                label: _t('Undo', 'تراجع'),
                onPressed: () async {
                  final result = await undo();
                  onChanged?.call();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        result.saved ? undone : _messageFor(result),
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
        if (result.serverMessage?.contains('can no longer be undone') ??
            false) {
          return _t(
            'This can no longer be undone because the period changed since.',
            'لم يعد التراجع ممكناً لأن الحيض تغيّر منذ ذلك الحين.',
          );
        }
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
        if (message.contains('no bleeding is recorded on')) {
          return _t(
            'A period can only start on a day with bleeding you recorded.',
            'لا يبدأ الحيض إلا في يوم سجّلتِ فيه دماً.',
          );
        }
        if (message.contains('bleeding is recorded between')) {
          return _t(
            'You recorded bleeding after that day. Choose a later first day '
                'with no bleeding, or "I don\'t know".',
            'سجّلتِ دماً بعد ذلك اليوم. اختاري يوماً لاحقاً بلا دم، أو '
                '"لا أعرف".',
          );
        }
        if (message.contains('a corrected entry spans')) {
          return _t(
            'An entry you corrected crosses that day. Check that entry first.',
            'يوجد إدخال معدَّل يمتد عبر ذلك اليوم. راجعيه أولاً.',
          );
        }
        if (message.contains('another period lies between') ||
            message.contains('first period is still open')) {
          return _t(
            'Only a finished period and the one right after it can be '
                'joined.',
            'لا يُدمج إلا حيض منتهٍ مع الحيض الذي يليه مباشرة.',
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
  bool get _hasUnsavedEdit => _mode == _Mode.split
      ? _secondStart != null
      : _mode != _Mode.menu && _newDate != null;

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
                  key: const Key('episode-edit-summary'),
                  _episode.endUnknown
                      ? _t(
                          'Started ${episodeDateLabel(_episode.startDate)} · '
                              'end date not recorded',
                          'بدأ ${episodeDateLabel(_episode.startDate)} · '
                              'تاريخ الانتهاء غير مسجَّل',
                        )
                      : _ended
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
                if (_mode == _Mode.menu)
                  ..._menu()
                else if (_mode == _Mode.split)
                  ..._splitEditor()
                else
                  ..._dateEditor(),
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
        title: _episode.endUnknown
            ? _t('Add end date', 'إضافة تاريخ النهاية')
            : _t('Change end date', 'تغيير تاريخ النهاية'),
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
      key: const Key('episode-edit-split'),
      icon: Icons.call_split_rounded,
      title: _t('Split into two periods', 'تقسيمه إلى حيضين'),
      subtitle: _t(
        'For two periods recorded as one.',
        'لحيضين سُجّلا كحيض واحد.',
      ),
      enabled: !_saving,
      onTap: _openSplit,
    ),
    if (_ended && _nextEpisode != null)
      _ActionTile(
        key: const Key('episode-edit-merge'),
        icon: Icons.merge_rounded,
        title: _t('Join with the next period', 'دمجه مع الحيض التالي'),
        subtitle: _t(
          'The next one started ${episodeDateLabel(_nextEpisode!.startDate)}. '
              'For one period recorded as two.',
          'بدأ التالي في ${episodeDateLabel(_nextEpisode!.startDate)}. '
              'لحيض واحد سُجّل كحيضين.',
        ),
        enabled: !_saving,
        onTap: _merge,
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

  List<Widget> _splitEditor() {
    final days = _bleedingDays;
    final second = _secondStart;
    final canSave =
        !_saving && second != null && (_firstEnd != null || _firstEndUnknown);
    return [
      Text(
        _t(
          'Which day did the second period start?',
          'في أي يوم بدأ الحيض الثاني؟',
        ),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      if (days == null)
        const Center(child: CircularProgressIndicator())
      else if (days.isEmpty)
        Text(
          key: const Key('episode-split-no-days'),
          _t(
            'The second period has to start on a day with bleeding you '
                'recorded, after the first day. Record that day first.',
            'يجب أن يبدأ الحيض الثاني في يوم سجّلتِ فيه دماً بعد اليوم '
                'الأول. سجّلي ذلك اليوم أولاً.',
          ),
          style: const TextStyle(color: AppColors.textSecondary),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in days)
              ChoiceChip(
                key: Key(
                  'episode-split-day-${day.toIso8601String().substring(0, 10)}',
                ),
                label: Text(episodeDateLabel(day)),
                selected: second == day,
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                        _secondStart = day;
                        if (_firstEnd != null && !_firstEnd!.isBefore(day)) {
                          _firstEnd = null;
                        }
                        if (!_firstEndPickable) {
                          _firstEnd = null;
                          _firstEndUnknown = true;
                        }
                        _message = null;
                      }),
              ),
          ],
        ),
      if (second != null) ...[
        const SizedBox(height: 16),
        Text(
          _t(
            'When did the first one stop? (first day with no bleeding)',
            'متى انتهى الأول؟ (أول يوم بلا دم)',
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const Key('episode-split-first-end'),
          onPressed: _saving || !_firstEndPickable ? null : _pickFirstEnd,
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: Text(
            _firstEnd == null
                ? _t('Choose a day', 'اختاري يوماً')
                : episodeDateLabel(_firstEnd!),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        CheckboxListTile(
          key: const Key('episode-split-end-unknown'),
          contentPadding: EdgeInsets.zero,
          value: _firstEndUnknown,
          onChanged: _saving || !_firstEndPickable
              ? null
              : (value) => setState(() {
                  _firstEndUnknown = value ?? false;
                  if (_firstEndUnknown) _firstEnd = null;
                }),
          title: Text(_t("I don't know", 'لا أعرف')),
          subtitle: Text(
            _t(
              'The end stays unrecorded; nothing is guessed.',
              'تبقى النهاية غير مسجّلة؛ لا يُخمَّن شيء.',
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('episode-split-save'),
        onPressed: canSave ? _saveSplit : null,
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
            : Text(_t('Continue', 'متابعة')),
      ),
      TextButton(
        onPressed: _saving
            ? null
            : () => setState(() {
                _mode = _Mode.menu;
                _secondStart = null;
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

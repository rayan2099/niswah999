import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/calendar_days.dart';
import '../../data/repositories/bleeding_episode_repository_impl.dart';
import '../../domain/entities/bleeding_episode.dart';
import '../../domain/entities/load_result.dart';
import 'daily_checkin_sheet.dart';
import 'start_bleeding_sheet.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// What she wants to record for a day she tapped (the Today ring or a
/// Calendar day).
enum LogDayChoice { bleeding, symptomsAndNotes }

/// Asks whether a tap on a day is about bleeding or about symptoms/notes.
///
/// Bleeding is only ever recorded through the canonical
/// `bleeding_episodes`/`bleeding_observations` sheets (see
/// [logCanonicalBleedingForDay]); the legacy log sheet is offered only for
/// symptoms and notes ([CycleLogSheetMode.symptomsOnly]). A bleeding entry
/// written to `cycle_entries` alone never reaches Today's Fiqh state, so
/// Today would keep saying "Tahara" right after she logged bleeding.
/// Bleeding cannot be logged for a future day.
Future<LogDayChoice?> showLogDayChooser(
  BuildContext context, {
  required DateTime day,
}) {
  final isFuture = calendarDaysBetween(AppClock.now(), day) > 0;
  return showModalBottomSheet<LogDayChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isFuture)
            ListTile(
              key: const Key('log-day-choice-bleeding'),
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(_t('Bleeding', 'نزيف')),
              subtitle: Text(
                _t(
                  "Start a period, or log a day of the one you're tracking now",
                  'بدء حيض، أو تسجيل يوم من الحيض الذي تتابعينه الآن',
                ),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(LogDayChoice.bleeding),
            ),
          ListTile(
            key: const Key('log-day-choice-symptoms'),
            leading: const Icon(Icons.edit_note_rounded),
            title: Text(_t('Symptoms & notes', 'الأعراض والملاحظات')),
            onTap: () =>
                Navigator.of(sheetContext).pop(LogDayChoice.symptomsAndNotes),
          ),
        ],
      ),
    ),
  );
}

void _showCouldNotVerify(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        _t(
          "We couldn't verify your tracking data right now. Try again.",
          'تعذر التحقق من بيانات تتبعكِ الآن. يرجى المحاولة مجدداً.',
        ),
      ),
    ),
  );
}

/// Records bleeding on [day] through the canonical sheets only:
/// - an open episode covering [day]: today's check-in, or a backfill for an
///   earlier day of that episode;
/// - no open episode: the start-bleeding sheet, pre-set to [day] — unless
///   [day] is on or before the end of an episode she already ended, which
///   `start_bleeding_episode` rejects; she is pointed to the calendar's
///   correction flow instead.
///
/// Returns true when something was saved. A read failure is shown as
/// "couldn't verify", never treated as "no open episode".
Future<bool> logCanonicalBleedingForDay(
  BuildContext context, {
  required DateTime day,
  // Test seams (the dashboard's canonicalRepositoryOverride/
  // canonicalUserIdOverride pattern); production passes neither.
  @visibleForTesting BleedingEpisodeRepositoryImpl? repositoryOverride,
  @visibleForTesting String? userIdOverride,
}) async {
  final userId =
      userIdOverride ?? NiswahSupabase.clientOrNull?.auth.currentUser?.id;
  if (userId == null) return showStartBleedingSheet(context, initialDate: day);

  final repository = repositoryOverride ?? BleedingEpisodeRepositoryImpl();
  final result = await repository.getOpenEpisode(userId);
  if (!context.mounted) return false;
  if (result is LoadUnavailable) {
    _showCouldNotVerify(context);
    return false;
  }

  final episode = result.dataOrNull;
  final episodeId = episode?.id;
  if (episode == null || episodeId == null) {
    // Round-2 hardening (proposed): `start_bleeding_episode` rejects a
    // start on or before the end of any episode she already ended (an
    // open episode from that day would overlap it), and a day inside an
    // ended episode is changed through its own observations. Say so up
    // front instead of opening a start sheet that can only fail.
    final episodes = await repository.getEpisodesForUser(userId);
    if (!context.mounted) return false;
    if (episodes is LoadUnavailable) {
      _showCouldNotVerify(context);
      return false;
    }
    final endsOnOrAfterDay = (episodes.dataOrNull ?? const <BleedingEpisode>[])
        .any(
          (e) =>
              e.lifecycleStatus == LifecycleStatus.ended &&
              e.endDate != null &&
              calendarDaysBetween(day, e.endDate!) >= 0,
        );
    if (endsOnOrAfterDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('log-day-ended-episode-guidance'),
          content: Text(
            _t(
              "This day is within or before a period you've already "
                  "ended, so a new period can't start here. To change that "
                  'period\'s days, open the cycle calendar on Today and '
                  'choose "Correct this entry".',
              'هذا اليوم ضمن حيض أنهيتِه أو قبله، لذا لا يمكن بدء حيض '
                  'جديد فيه. لتعديل أيام ذلك الحيض، افتحي تقويم الدورة من '
                  'صفحة اليوم واختاري "تصحيح هذا الإدخال".',
            ),
          ),
        ),
      );
      return false;
    }
    if (!context.mounted) return false;
    return showStartBleedingSheet(context, initialDate: day);
  }
  if (calendarDaysBetween(episode.startDate, day) < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            'This day is before your current period started. Open the '
                'cycle calendar on Today to add or correct earlier days.',
            'هذا اليوم قبل بداية حيضكِ الحالي. افتحي تقويم الدورة من '
                'صفحة اليوم لإضافة الأيام السابقة أو تصحيحها.',
          ),
        ),
      ),
    );
    return false;
  }
  if (calendarDaysBetween(day, AppClock.now()) == 0) {
    final outcome = await showDailyCheckinSheet(
      context,
      episodeId: episodeId,
      episodeStartDate: episode.startDate,
    );
    return outcome != DailyCheckinOutcome.cancelled;
  }
  return showBackfillObservationSheet(
    context,
    episodeId: episodeId,
    episodeStartDate: episode.startDate,
    initialDate: calendarDay(day),
  );
}

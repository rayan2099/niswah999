import 'dart:convert';

import '../viewmodels/activity_inbox_controller.dart';
import '../../domain/entities/activity_notification.dart';
import '../../data/services/app_notification_session.dart';

import 'package:flutter/material.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/services/notification_refresh_coordinator.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/entities/notification_preference.dart';

String _nf(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Real notification history — what the bell icon opens. Not settings
/// (see NotificationSettingsScreen, now reached from Profile instead).
class NotificationFeedScreen extends StatefulWidget {
  const NotificationFeedScreen({super.key});

  @override
  State<NotificationFeedScreen> createState() => _NotificationFeedScreenState();
}

class _NotificationFeedScreenState extends State<NotificationFeedScreen> {
  @override
  void initState() {
    super.initState();
    NotificationLogController.instance.load();
    ActivityInboxController.instance.refresh();
    _enableNotifications();
  }

  Future<void> _enableNotifications() async {
    final granted = await NotificationService.instance.requestPermission();
    if (!mounted || !granted) return;
    await AppNotificationSession.instance.refreshRegistration();
    await NotificationRefreshCoordinator.refresh(
      userId: NiswahSupabase.clientOrNull?.auth.currentUser?.id,
    );
  }

  static (IconData, Color) _iconAndColor(NotificationType type) =>
      switch (type) {
        NotificationType.privateMessage => (
          Icons.chat_bubble_outline,
          AppColors.brandPrimary,
        ),
        NotificationType.communityComment || NotificationType.communityLike => (
          Icons.forum_outlined,
          AppColors.brandPrimary,
        ),
        NotificationType.fertility => (
          Icons.calendar_month_outlined,
          AppColors.brandPrimary,
        ),
        NotificationType.learning => (
          Icons.menu_book_outlined,
          AppColors.brandPrimary,
        ),
        NotificationType.cycle => (Icons.water_drop_outlined, AppColors.haid),
        NotificationType.pregnancy => (
          Icons.pregnant_woman_rounded,
          AppColors.nifas,
        ),
        NotificationType.wellbeing => (
          Icons.favorite_border_rounded,
          AppColors.brandPrimary,
        ),
        NotificationType.prayer => (Icons.mosque_outlined, AppColors.tahara),
        NotificationType.activeBleeding => (
          Icons.today_outlined,
          AppColors.haid,
        ),
      };

  String _relativeTime(DateTime createdAt, bool isArabic) {
    final diff = AppClock.now().difference(createdAt);
    if (diff.inMinutes < 1) return _nf('Just now', 'الآن');
    if (diff.inHours < 1) {
      return isArabic ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return isArabic ? 'منذ ${diff.inHours} س' : '${diff.inHours}h ago';
    }
    return isArabic ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return AnimatedBuilder(
      animation: Listenable.merge([
        NotificationLogController.instance,
        ActivityInboxController.instance,
      ]),
      builder: (context, _) {
        final activity = ActivityInboxController.instance;
        // A busy conversation or post shows as one row per day, not one per
        // message or comment; opening it marks the whole group read.
        final groups = activity.groups;
        final groupIds = {
          for (final g in groups) 'activity_${g.latest.id}': g.ids,
        };
        final entries = [
          ...NotificationLogController.instance.entries,
          for (final g in groups)
            NotificationLogEntry(
              id: 'activity_${g.latest.id}',
              type: NotificationType.values.firstWhere((t) => t.name == g.kind),
              titleAr: ActivityNotification.titleFor(
                g.kind,
                true,
                count: g.events.length,
              ),
              bodyAr: g.latest.body(true),
              titleEn: ActivityNotification.titleFor(
                g.kind,
                false,
                count: g.events.length,
              ),
              bodyEn: g.latest.body(false),
              createdAt: g.latest.createdAt,
              read: g.read,
              target: g.latest.target,
            ),
        ]..sort((a, b) => b.shownAt.compareTo(a.shownAt));
        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: Text(_nf('Notifications', 'التنبيهات')),
            actions: [
              if (activity.unavailable)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: _nf('Retry loading activity', 'إعادة تحميل النشاط'),
                  onPressed: activity.refresh,
                ),
              if (entries.any((entry) => !entry.read))
                TextButton(
                  onPressed: () async {
                    try {
                      await activity.markRead();
                      await NotificationLogController.instance.markAllRead();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _nf(
                                'Could not mark all updates read. Please retry.',
                                'تعذّر تحديد كل التحديثات كمقروءة. حاولي مجددًا.',
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(_nf('Mark all read', 'تحديد الكل كمقروء')),
                ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _nf(
                        activity.unavailable
                            ? 'Activity could not be loaded. Tap refresh to retry.'
                            : 'No notifications yet — reminders will appear here as they happen.',
                        activity.unavailable
                            ? 'تعذّر تحميل النشاط. اضغطي تحديث للمحاولة.'
                            : 'لا توجد تنبيهات بعد — ستظهر التذكيرات هنا عند حدوثها.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final (icon, color) = _iconAndColor(entry.type);
                    return InkWell(
                      onTap: () async {
                        if (entry.target != null) {
                          NotificationService.instance.enqueueTap(
                            jsonEncode(entry.target!.toJson()),
                          );
                        }
                        try {
                          if (groupIds[entry.id] case final ids?) {
                            await activity.markRead(ids: ids);
                          } else {
                            await NotificationLogController.instance.markRead(
                              entry.id,
                            );
                          }
                        } catch (_) {
                          /* Navigation still works when read sync is unavailable. */
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: entry.read
                                ? const Color(0xFFF3F4F6)
                                : color.withValues(alpha: .3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isArabic ? entry.titleAr : entry.titleEn,
                                    style: TextStyle(
                                      fontWeight: entry.read
                                          ? FontWeight.w600
                                          : FontWeight.w800,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isArabic ? entry.bodyAr : entry.bodyEn,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _relativeTime(entry.shownAt, isArabic),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!entry.read)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: const BoxDecoration(
                                  color: AppColors.brandSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

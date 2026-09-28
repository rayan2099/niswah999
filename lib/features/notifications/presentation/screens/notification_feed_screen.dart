import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/notification_log_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_theme.dart';
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
    NotificationService.instance.requestPermission();
  }

  static (IconData, Color) _iconAndColor(NotificationType type) =>
      switch (type) {
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
    final diff = DateTime.now().difference(createdAt);
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
      animation: NotificationLogController.instance,
      builder: (context, _) {
        final entries = NotificationLogController.instance.entries;
        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: Text(_nf('Notifications', 'التنبيهات')),
            actions: [
              if (entries.any((entry) => !entry.read))
                TextButton(
                  onPressed: () =>
                      NotificationLogController.instance.markAllRead(),
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
                        'No notifications yet — reminders will appear here as they happen.',
                        'لا توجد تنبيهات بعد — ستظهر التذكيرات هنا عند حدوثها.',
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
                      onTap: () =>
                          NotificationLogController.instance.markRead(entry.id),
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
                                    _relativeTime(entry.createdAt, isArabic),
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

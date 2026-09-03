import '../entities/notification_preference.dart';

abstract class NotificationRepository {
  Future<Map<NotificationType, NotificationPreference>> loadPreferences();

  Future<void> savePreferences(
    Map<NotificationType, NotificationPreference> preferences,
  );
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/activity_notification.dart';

abstract interface class ActivityNotificationRepository {
  Future<List<ActivityNotification>> load(String userId);
  Future<int> unreadCount(String userId);

  /// Marks [ids] read, or every unread event when [ids] is null.
  Future<void> markRead(String userId, {List<String>? ids});
  void Function() watch(String userId, void Function() changed);
}

class SupabaseActivityNotificationRepository
    implements ActivityNotificationRepository {
  SupabaseActivityNotificationRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<ActivityNotification>> load(String userId) async {
    final rows = await client
        .from('notification_inbox')
        .select('id,recipient_id,kind,target_id,created_at,read_at')
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(200);
    return [for (final row in rows) ?ActivityNotification.tryParse(row)];
  }

  @override
  Future<int> unreadCount(String userId) async => await client
      .from('notification_inbox')
      .count(CountOption.exact)
      .eq('recipient_id', userId)
      .isFilter('read_at', null);

  @override
  Future<void> markRead(String userId, {List<String>? ids}) async {
    if (ids != null && ids.isEmpty) return;
    // The database replaces this value with its own clock.
    var q = client
        .from('notification_inbox')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_id', userId)
        .isFilter('read_at', null);
    if (ids != null) q = q.inFilter('id', ids);
    await q;
  }

  @override
  void Function() watch(String userId, void Function() changed) {
    final channel = client
        .channel('activity-$userId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notification_inbox',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (_) => changed(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) changed();
        });
    return () {
      client.removeChannel(channel);
    };
  }
}

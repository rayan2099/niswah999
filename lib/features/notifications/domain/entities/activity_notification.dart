import 'notification_target.dart';

class ActivityNotification {
  const ActivityNotification({
    required this.id,
    required this.kind,
    required this.target,
    required this.createdAt,
    this.read = false,
  });
  final String id;
  final String kind;
  final NotificationTarget target;
  final DateTime createdAt;
  final bool read;
  factory ActivityNotification.fromJson(Map<String, dynamic> row) {
    final kind = row['kind'];
    if (!{
      'privateMessage',
      'communityComment',
      'communityLike',
    }.contains(kind)) {
      throw const FormatException('Unsupported activity');
    }
    final target = NotificationTarget.tryParse({
      'destination': kind == 'privateMessage' ? 'conversation' : 'post',
      'userId': row['recipient_id'],
      'targetId': row['target_id'],
    });
    if (target == null || row['id'] is! String) {
      throw const FormatException('Invalid activity');
    }
    return ActivityNotification(
      id: row['id'],
      kind: kind as String,
      target: target,
      createdAt: DateTime.parse(row['created_at'] as String),
      read: row['read_at'] != null,
    );
  }

  /// Rows of a kind this build does not know (added by a newer server) or
  /// with malformed fields are skipped instead of failing the whole inbox.
  static ActivityNotification? tryParse(Map<String, dynamic> row) {
    try {
      return ActivityNotification.fromJson(row);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String title(bool ar) => titleFor(kind, ar);
  String body(bool ar) => ar
      ? 'اضغطي لفتح التفاصيل في نِسواه.'
      : 'Tap to open the details in Niswah.';

  static String titleFor(String kind, bool ar, {int count = 1}) {
    final base = switch (kind) {
      'privateMessage' => ar ? 'رسالة جديدة' : 'New message',
      'communityComment' =>
        ar ? 'تعليق جديد على منشوركِ' : 'New comment on your post',
      _ => ar ? 'تفاعل جديد مع منشوركِ' : 'New activity on your post',
    };
    if (count < 2) return base;
    final grouped = switch (kind) {
      'privateMessage' => ar ? 'رسائل جديدة' : 'New messages',
      'communityComment' =>
        ar ? 'تعليقات جديدة على منشوركِ' : 'New comments on your post',
      _ => base,
    };
    return '$grouped ($count)';
  }

  /// Discreet phone-alert copy: the kind of activity only, never a name,
  /// message text or health detail. Mirrors the dispatch worker's copy.
  static String alertBody(String kind, bool ar) => switch (kind) {
    'privateMessage' =>
      ar ? 'لديكِ رسالة جديدة في نِسواه.' : 'You have a new message in Niswah.',
    'communityComment' =>
      ar ? 'تعليق جديد على منشوركِ.' : 'New comment on your post.',
    _ => ar ? 'تفاعل جديد مع منشوركِ.' : 'New activity on your post.',
  };
}

/// Several unread events about the same conversation or post on the same day
/// shown as one bell row; opening it marks every event in it read.
class ActivityGroup {
  const ActivityGroup(this.events);
  final List<ActivityNotification> events;
  ActivityNotification get latest => events.first;
  String get kind => latest.kind;
  List<String> get ids => [for (final e in events) e.id];
  bool get read => events.every((e) => e.read);
  int get unread => events.where((e) => !e.read).length;

  /// [events] must be newest first, as the inbox is loaded.
  static List<ActivityGroup> of(Iterable<ActivityNotification> events) {
    final groups = <String, List<ActivityNotification>>{};
    for (final e in events) {
      final local = e.createdAt.toLocal();
      final key =
          '${e.kind}|${e.target.targetId}|${e.read}|'
          '${local.year}-${local.month}-${local.day}';
      (groups[key] ??= []).add(e);
    }
    return [for (final g in groups.values) ActivityGroup(g)];
  }
}

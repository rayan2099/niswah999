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
  String title(bool ar) => switch (kind) {
    'privateMessage' => ar ? 'رسالة جديدة' : 'New message',
    'communityComment' =>
      ar ? 'تعليق جديد على منشوركِ' : 'New comment on your post',
    _ => ar ? 'تفاعل جديد مع منشوركِ' : 'New activity on your post',
  };
  String body(bool ar) => ar
      ? 'اضغطي لفتح التفاصيل في نِسواه.'
      : 'Tap to open the details in Niswah.';
}

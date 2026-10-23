/// Only known destinations and opaque identifiers are accepted from a phone
/// notification. Authorization is checked again when the target is opened.
enum NotificationDestination {
  calendar,
  prayer,
  pregnancy,
  wellbeing,
  conversation,
  post,
  aiChat,
  learning,
}

class NotificationTarget {
  const NotificationTarget({
    required this.destination,
    required this.userId,
    this.targetId,
  });
  final NotificationDestination destination;
  final String userId;
  final String? targetId;
  Map<String, dynamic> toJson() => {
    'destination': destination.name,
    'userId': userId,
    if (targetId != null) 'targetId': targetId,
  };
  static NotificationTarget? tryParse(Object? value) {
    if (value is! Map) return null;
    final destination = NotificationDestination.values
        .where((d) => d.name == value['destination'])
        .firstOrNull;
    final userId = value['userId'];
    final id = value['targetId'];
    if (destination == null ||
        userId is! String ||
        userId.isEmpty ||
        userId.length > 128 ||
        (id != null && (id is! String || id.isEmpty || id.length > 128))) {
      return null;
    }
    if ((destination == NotificationDestination.conversation ||
            destination == NotificationDestination.post ||
            destination == NotificationDestination.aiChat) &&
        id == null) {
      return null;
    }
    return NotificationTarget(
      destination: destination,
      userId: userId,
      targetId: id as String?,
    );
  }
}

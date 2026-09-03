/// A private 1:1 conversation thread between two users.
class PrivateConversation {
  final String id;
  final String participantOne;
  final String participantTwo;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PrivateConversation({
    required this.id,
    required this.participantOne,
    required this.participantTwo,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the id of the other participant given the current user's id.
  String otherParticipant(String currentUserId) =>
      currentUserId == participantOne ? participantTwo : participantOne;

  bool involves(String userId) =>
      userId == participantOne || userId == participantTwo;

  factory PrivateConversation.fromJson(Map<String, dynamic> json) {
    return PrivateConversation(
      id: json['id'] as String,
      participantOne: json['participant_one'] as String,
      participantTwo: json['participant_two'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'participant_one': participantOne,
    'participant_two': participantTwo,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

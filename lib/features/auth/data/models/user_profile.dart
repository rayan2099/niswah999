class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.isAnonymous = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool isAnonymous;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName:
          json['display_name'] as String? ?? json['full_name'] as String?,
      isAnonymous: json['anonymous_mode'] as bool? ?? false,
    );
  }
}

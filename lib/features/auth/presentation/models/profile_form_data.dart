class ProfileFormData {
  const ProfileFormData({
    required this.displayName,
    required this.email,
    this.phoneNumber,
    this.bio,
  });

  final String displayName;
  final String email;
  final String? phoneNumber;
  final String? bio;

  String? validate() {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      return 'Display name is required.';
    }

    if (trimmedName.length > 50) {
      return 'display name must be 50 characters or fewer.';
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      return 'Enter a valid email address.';
    }

    if (bio != null && bio!.trim().length > 200) {
      return 'Bio must be 200 characters or fewer.';
    }

    return null;
  }
}

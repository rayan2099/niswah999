import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.isAnonymous = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool isAnonymous;

  @override
  List<Object?> get props => [id, email, displayName, isAnonymous];
}

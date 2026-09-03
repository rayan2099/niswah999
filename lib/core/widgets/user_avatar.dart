import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rounded-square avatar — matches the app's existing avatar shape
/// elsewhere (no photo upload exists yet to justify a circular photo frame).
/// Named authors get a colored initial; anonymous authors get a neutral icon.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.displayName,
    this.isAnonymous = false,
    this.size = 42,
    this.dark = false,
  });

  final String displayName;
  final bool isAnonymous;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF303030) : AppColors.rosePale,
      borderRadius: BorderRadius.circular(size / 3),
    ),
    alignment: Alignment.center,
    child: isAnonymous
        ? Icon(
            Icons.person_outline_rounded,
            color: dark ? const Color(0xFFFFA6B3) : AppColors.brandSecondary,
            size: size * 0.5,
          )
        : Text(
            displayName.trim().isEmpty
                ? '?'
                : displayName.trim().characters.first.toUpperCase(),
            style: TextStyle(
              color: dark ? const Color(0xFFFFD6DC) : AppColors.roseInk,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.4,
            ),
          ),
  );
}

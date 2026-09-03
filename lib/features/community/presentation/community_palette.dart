import 'package:flutter/material.dart';

/// Resolved set of Community colors for the current brightness. Field names
/// match the values used throughout the feature's widgets.
class CommunityColors {
  const CommunityColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.blush,
    required this.blushStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.border,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color blush;
  final Color blushStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color border;
  final Color divider;
}

/// Theme-aware Community palette — dark by design in dark mode, and the
/// feature's original warm-rose look in light mode. Call [CommunityPalette.of]
/// once per `build` and reuse the result; it depends on
/// `Theme.of(context).brightness`, so it responds to the user's actual
/// light/dark/system preference instead of always rendering dark.
abstract final class CommunityPalette {
  static const dark = CommunityColors(
    background: Color(0xFF101010),
    surface: Color(0xFF1C1C1C),
    surfaceElevated: Color(0xFF222222),
    blush: Color(0xFFFFA6B3),
    blushStrong: Color(0xFFFFB0BA),
    text: Color(0xFFF7EDEE),
    textMuted: Color(0xFFC6B7BA),
    textFaint: Color(0xFF8F8588),
    border: Color(0xFF5E4147),
    divider: Color(0xFF2C292A),
  );

  static const light = CommunityColors(
    background: Color(0xFFFDFCFB),
    surface: Colors.white,
    surfaceElevated: Color(0xFFF9FAFB),
    blush: Color(0xFFBE123C),
    blushStrong: Color(0xFF881337),
    text: Color(0xFF1F2937),
    textMuted: Color(0xFF6B7280),
    textFaint: Color(0xFF9CA3AF),
    border: Color(0xFFFFE4E6),
    divider: Color(0x0A000000),
  );

  static CommunityColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

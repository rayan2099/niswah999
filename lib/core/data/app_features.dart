import 'package:flutter/material.dart';

import '../config/launch_features.dart';

/// A single marketing-facing feature card: icon + two-language label.
/// Deliberately has no route/navigation wiring of its own — every current
/// consumer ([SignInScreen]'s pre-auth showcase grid, the onboarding
/// completion screen's "this is what Niswah gives you" grid) is a static
/// display, not a tappable shortcut.
class AppFeature {
  const AppFeature({
    required this.icon,
    required this.iconColor,
    required this.labelEn,
    required this.labelAr,
    this.isCommunity = false,
  });

  final IconData icon;
  final Color iconColor;
  final String labelEn;
  final String labelAr;

  /// Shown only while community is in the build ([LaunchFeatures]).
  final bool isCommunity;
}

/// Onboarding fixes wave (2026-10-11), Part 9: the single source of truth
/// for "what Niswah gives you" feature cards — previously hardcoded only
/// inside [SignInScreen]'s pre-auth showcase grid. Extracted here so the
/// onboarding completion screen can show the same real product features
/// instead of inventing a second, disconnected list; [SignInScreen] now
/// reads from this list too, so the two can never drift apart.
const List<AppFeature> kAppFeatures = [
  AppFeature(
    icon: Icons.calendar_month_rounded,
    iconColor: Color(0xFFEF4444),
    labelEn: 'Cycle prediction',
    labelAr: 'تتبع الدورة',
  ),
  AppFeature(
    icon: Icons.favorite_rounded,
    iconColor: Color(0xFFF59E0B),
    labelEn: 'Purity planning',
    labelAr: 'تخطيط للحمل',
  ),
  AppFeature(
    icon: Icons.child_care_rounded,
    iconColor: Color(0xFF10B981),
    labelEn: 'Pregnancy prediction',
    labelAr: 'تتبع الحمل',
  ),
  AppFeature(
    icon: Icons.medical_services_outlined,
    iconColor: Color(0xFF3B82F6),
    labelEn: 'Smart doctor',
    labelAr: 'طبيبة ذكية',
  ),
  AppFeature(
    icon: Icons.groups_rounded,
    iconColor: Color(0xFFA855F7),
    labelEn: 'Women community',
    labelAr: 'مجتمع نسائي',
    isCommunity: true,
  ),
  AppFeature(
    icon: Icons.description_outlined,
    iconColor: Color(0xFF64748B),
    labelEn: 'PDF reports',
    labelAr: 'تقارير PDF',
  ),
  AppFeature(
    icon: Icons.nights_stay_rounded,
    iconColor: Color(0xFF14B8A6),
    labelEn: 'Dream interpretation',
    labelAr: 'تفسير الأحلام',
  ),
  AppFeature(
    icon: Icons.auto_awesome_rounded,
    iconColor: Color(0xFFEC4899),
    // Corrected from SignInScreen's own pre-existing "روؤى يومية" (an
    // extra ؤ) — the same typo fix the task's own spec text already uses.
    labelEn: 'Daily insights',
    labelAr: 'رؤى يومية',
  ),
];

/// [kAppFeatures] without the ones this build leaves out, so no card
/// advertises a feature she cannot open.
List<AppFeature> get launchAppFeatures => [
  for (final feature in kAppFeatures)
    if (LaunchFeatures.community || !feature.isCommunity) feature,
];

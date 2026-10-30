import 'package:flutter/material.dart';

import '../localization/app_locale_controller.dart';

class AppColors {
  // Brand Colors (matching web design)
  static const Color brandPrimary = Color(0xFFBE123C); // rose-600 (soft pink)
  static const Color brandSecondary = Color(0xFFFB7185); // pink-500
  static const Color brandBackground = Color(0xFFFDFCFB); // warm off-white

  // Semantic Colors
  static const Color tahara = Color(0xFF0D9488); // emerald-600 (clean/purity)
  static const Color haid = Color(0xFFBE123C); // rose-600
  static const Color istihadah = Color(0xFF4F46E5); // indigo-600
  static const Color nifas = Color(0xFFD97706); // amber-600 (postpartum)

  /// [tahara], darkened (hue/saturation preserved) to 4.63:1 against white —
  /// clears WCAG AA's 4.5:1 bar for normal-size text (AU-003). [tahara]
  /// itself only clears 3.74:1, which is fine for its icon/border/background
  /// uses (the applicable bar there is 3:1) but not for small text — use
  /// this variant specifically where [tahara] is a `Text` color, not the
  /// base color, so icons/borders/chips keep the original brand hue.
  static const Color taharaText = Color(0xFF0C8379);

  // Text Colors
  static const Color textPrimary = Color(0xFF1F2937); // gray-900
  static const Color textSecondary = Color(0xFF6B7280); // gray-500
  static const Color textTertiary = Color(0xFF9CA3AF); // gray-400
  static const Color emeraldInk = Color(0xFF064E3B); // emerald-900

  // Surface Colors
  static const Color surface = Colors.white;
  static const Color surfaceHover = Color(0xFFF9FAFB); // gray-50

  // Utility Colors
  static const Color success = Color(0xFF10B981); // emerald-500
  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color error = Color(0xFFEF4444); // red-500
  static const Color info = Color(0xFF3B82F6); // blue-500

  // Rose Accent (community feed)
  static const Color roseInk = Color(0xFF881337); // deep rose ink — headings
  static const Color rosePale = Color(
    0xFFFFF1F2,
  ); // pale rose — chip/badge fill
  static const Color roseBorder = Color(0xFFFFE4E6); // rose border

  // Shadow Color
  static const Color shadowColor = Color(0x0A000000); // black/5%

  // --- Onboarding premium palette (NISWAH onboarding redesign) ---
  // Additive, scoped to onboarding + the shared Madhhab selector. Deliberately
  // NOT wired into ColorScheme.fromSeed above -- that feeds every screen in
  // the app via Material's default theming, and this redesign is scoped to
  // onboarding, not an app-wide rebrand. Exact hex values as specified.
  static const Color deepPlum = Color(0xFF553F50); // headings, key icons
  static const Color mutedRose = Color(0xFFC66F84); // selected/highlight/active
  static const Color softBlush = Color(0xFFF6E8EC); // subtle selection bg
  static const Color warmIvory = Color(0xFFFCFAF8); // page background
  static const Color warmWhite = Color(0xFFFFFFFF); // cards/inputs
  static const Color slateGray = Color(0xFF777681); // secondary text
  static const Color softStone = Color(0xFFE8E2E3); // borders/separators
  static const Color sageGreen = Color(0xFF738F83); // informational/reassuring

  // Semantic tokens built from the palette above, so call sites express
  // intent (onboardingBackground) rather than repeating a hex choice.
  static const Color onboardingBackground = warmIvory;
  static const Color onboardingSurface = warmWhite;
  static const Color onboardingPrimaryText = deepPlum;
  static const Color onboardingSecondaryText = slateGray;
  static const Color onboardingPrimaryAction = mutedRose;
  static const Color onboardingAccent = mutedRose;
  static const Color onboardingSelectedBg = softBlush;
  static const Color onboardingBorder = softStone;
  static const Color onboardingInputFocus = mutedRose;
  static const Color onboardingDisabled = softStone;
  static const Color onboardingInformational = sageGreen;
  // Error/warning/success stay on the app-wide semantic colors above
  // (AppColors.error/.warning/.success) rather than new ones -- state colors
  // should be consistent app-wide, not redefined per feature.
}

class AppTypography {
  static const String sansFamily = 'Inter';
  static String get serifFamily =>
      AppLocaleController.instance.isArabic ? arabicFamily : 'Playfair Display';
  static const String arabicFamily = 'Cairo';

  static TextStyle arabic(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(fontFamily: arabicFamily, height: 1.6);

  /// App-wide text enlargement on top of the phone's own text-size setting.
  /// Testing feedback 2026-10-30 (rayan): text across the app was slightly
  /// too small; many screens use 9-11 pt sizes. One factor here enlarges
  /// every screen evenly instead of editing hundreds of font sizes.
  static const double appTextScale = 1.1;
}

/// The phone's text scaler with [AppTypography.appTextScale] applied on
/// top, so a person who already enlarged text in Settings keeps that and
/// gets the same small step up.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.base, {this.factor = AppTypography.appTextScale});

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize * factor);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.sansFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brandPrimary,
        primary: AppColors.brandPrimary,
        secondary: AppColors.brandSecondary,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.brandBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brandBackground,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.brandPrimary,
        unselectedItemColor: AppColors.textTertiary,
        elevation: 12,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: const BorderSide(color: AppColors.shadowColor, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.shadowColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.shadowColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandPrimary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: AppColors.textPrimary,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    const background = Color(0xFF101010);
    const surface = Color(0xFF1C1C1C);
    const surfaceElevated = Color(0xFF242021);
    const blush = Color(0xFFFFA6B3);
    const text = Color(0xFFF7EDEE);
    const textMuted = Color(0xFFC6B7BA);
    const border = Color(0xFF40383A);

    final scheme = ColorScheme.fromSeed(
      seedColor: blush,
      brightness: Brightness.dark,
      primary: blush,
      secondary: const Color(0xFFFF7F95),
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppTypography.sansFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      dividerColor: border,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: blush,
        unselectedItemColor: textMuted,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: surfaceElevated,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceElevated,
        modalBackgroundColor: surfaceElevated,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: Color(0xFF8F8588)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blush, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blush,
          foregroundColor: const Color(0xFF32171D),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blush,
          foregroundColor: const Color(0xFF32171D),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: TextStyle(color: text),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: text,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: text,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: text,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: text,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: text),
        bodyMedium: TextStyle(fontSize: 14, color: text),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textMuted,
        ),
      ),
    );
  }
}

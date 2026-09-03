import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_locale_controller.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Shared 1–5 description text for mood/energy/sleep, so the Wellbeing
/// check-in and the period log sheet always say the same thing for the
/// same number.
String moodRatingDescription(int value) => switch (value) {
  1 => _t('Very Sad', 'سيء جداً'),
  2 => _t('Sad', 'سيء'),
  3 => _t('Neutral', 'متوسط'),
  4 => _t('Good', 'جيد'),
  _ => _t('Excellent', 'ممتاز جداً'),
};

String energyRatingDescription(int value) => switch (value) {
  1 => _t('Exhausted', 'مرهق جداً'),
  2 => _t('Low Energy', 'خامل'),
  3 => _t('Active', 'نشاط متوسط'),
  4 => _t('Energetic', 'نشيط'),
  _ => _t('Peak Energy', 'قمة النشاط'),
};

String sleepRatingDescription(int value) => switch (value) {
  1 => _t('Insomnia', 'أرق شديد'),
  2 => _t('Poor Sleep', 'متقطع'),
  3 => _t('Okay Sleep', 'متوسط'),
  4 => _t('Good Sleep', 'عميق ومريح'),
  _ => _t('Perfect Sleep', 'نوم مثالي'),
};

/// The mood face changes expression with the rating — a bolt or a moon has
/// no natural "expression" to vary, but a face does.
IconData moodRatingIcon(int value) => switch (value) {
  1 => Icons.sentiment_very_dissatisfied_rounded,
  2 => Icons.sentiment_dissatisfied_rounded,
  3 => Icons.sentiment_neutral_rounded,
  4 => Icons.sentiment_satisfied_rounded,
  _ => Icons.sentiment_very_satisfied_rounded,
};

/// A labeled 1–5 rating scale: an icon + label header with a live status
/// pill describing the current value, and a row of 5 tappable numbers
/// below. Shared by the Wellbeing check-in (Dashboard) and the period log
/// sheet so mood/energy/sleep ratings look and behave identically wherever
/// they're logged.
class RatingScaleRow extends StatelessWidget {
  const RatingScaleRow({
    super.key,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.value,
    required this.onChanged,
    required this.descriptionBuilder,
    this.iconBuilder,
  });

  final String label;

  /// The header icon shown when [iconBuilder] is null or returns nothing
  /// different — e.g. a fixed bolt/moon icon for energy/sleep.
  final IconData icon;
  final Color activeColor;
  final int value;
  final ValueChanged<int> onChanged;

  /// Short status text for the current [value] (e.g. "Very Sad", "Peak
  /// Energy"), shown in the pill on the opposite side of the header.
  final String Function(int value) descriptionBuilder;

  /// Optional per-value icon (e.g. a face that changes expression with the
  /// mood rating). Falls back to [icon] when omitted.
  final IconData Function(int value)? iconBuilder;

  IconData get _displayIcon => iconBuilder?.call(value) ?? icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                _displayIcon,
                key: ValueKey(_displayIcon),
                color: activeColor,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF064E3B),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Container(
              key: ValueKey('$value'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                descriptionBuilder(value),
                style: TextStyle(
                  color: activeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6), // subtle track background
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (index) {
            final ratingVal = index + 1;
            final isSelected = ratingVal == value;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onChanged(ratingVal);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$ratingVal',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF4B5563),
                      fontSize: isSelected ? 16 : 14,
                      fontWeight: isSelected
                          ? FontWeight.w900
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ],
  );
}

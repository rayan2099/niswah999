import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_theme.dart';

class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dark = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.chip),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? (dark ? const Color(0xFFFFA6B3) : AppColors.brandPrimary)
            : (dark ? Colors.transparent : Colors.white),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: selected
              ? (dark ? const Color(0xFFFFA6B3) : AppColors.brandPrimary)
              : (dark ? const Color(0xFF5E4147) : AppColors.roseBorder),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? (dark ? const Color(0xFF32171D) : Colors.white)
              : (dark ? const Color(0xFFFFA6B3) : const Color(0xFF9F1239)),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

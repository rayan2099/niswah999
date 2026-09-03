import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/widgets/selectable_chip.dart';
import '../../domain/entities/community_category_x.dart';
import '../../domain/entities/community_post.dart';

/// Iterates [CommunityCategory.values] so every category always has a chip
/// — the previous hardcoded chip row silently dropped 2 of the 6 categories.
class CommunityCategoryChipBar extends StatelessWidget {
  const CommunityCategoryChipBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final CommunityCategory? selected;
  final ValueChanged<CommunityCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          SelectableChip(
            label: AppLocaleController.instance.text('All', 'الكل'),
            selected: selected == null,
            onTap: () => onSelect(null),
            dark: isDark,
          ),
          for (final category in CommunityCategory.values) ...[
            const SizedBox(width: 8),
            SelectableChip(
              label: category.label(),
              selected: selected == category,
              onTap: () => onSelect(category),
              dark: isDark,
            ),
          ],
        ],
      ),
    );
  }
}

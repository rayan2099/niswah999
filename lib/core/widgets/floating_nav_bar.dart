import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.items,
    this.onFABPressed,
    this.dark = false,
    this.showFab = true,
  }) : assert(items.length == 5, 'The floating navigation uses five tabs.');

  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final VoidCallback? onFABPressed;
  final List<FloatingNavItem> items;
  final bool dark;
  final bool showFab;

  static const double _dockHeight = 89;
  static const double _fabSize = 56;

  static const _rtlItemCenters = <double>[0.908, 0.774, 0.641, 0.292, 0.125];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, barConstraints) => SizedBox(
        height: 102 + bottomInset,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: _dockHeight + bottomInset,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF1C1C1C) : AppColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: dark
                          ? const Color(0xFF302A2C)
                          : const Color(0x0D000000),
                    ),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 12,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 7),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 7),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final rtl =
                            Directionality.of(context) == TextDirection.rtl;
                        return Stack(
                          children: [
                            for (var index = 0; index < items.length; index++)
                              Positioned(
                                left:
                                    constraints.maxWidth *
                                        (showFab
                                            ? (rtl
                                                  ? _rtlItemCenters[index]
                                                  : 1 - _rtlItemCenters[index])
                                            : (rtl
                                                  ? 1 -
                                                        ((index + 0.5) /
                                                            items.length)
                                                  : (index + 0.5) /
                                                        items.length)) -
                                    30,
                                width: 60,
                                top: 0,
                                bottom: 0,
                                child: _item(items[index]),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (showFab)
              Positioned(
                top: 0,
                left:
                    barConstraints.maxWidth *
                        (Directionality.of(context) == TextDirection.rtl
                            ? 0.466
                            : 0.534) -
                    _fabSize / 2,
                child: Semantics(
                  button: true,
                  label: 'Niswah AI',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onFABPressed,
                    child: Container(
                      width: _fabSize,
                      height: _fabSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE11D48),
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x38E11D48),
                            blurRadius: 15,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(FloatingNavItem item) => _NavBarItem(
    item: item,
    isSelected: selectedIndex == item.targetIndex,
    onTap: () => onItemTapped(item.targetIndex),
    dark: dark,
  );
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.dark,
  });

  final FloatingNavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final active = dark ? const Color(0xFFFFA6B3) : const Color(0xFFE11D48);
    final inactive = dark ? const Color(0xFFA89599) : const Color(0xFFDBB8C3);
    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      // Without this, the child Text's own semantics (the same string)
      // merges with this explicit label, so a screen reader would
      // announce it twice ("Home, Home, button") instead of once.
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: isSelected ? active : inactive, size: 24),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isSelected ? active : inactive,
                fontFamily: AppTypography.arabicFamily,
                fontSize: 8,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: isSelected ? active : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FloatingNavItem {
  const FloatingNavItem({
    required this.targetIndex,
    required this.icon,
    required this.label,
  });

  final int targetIndex;
  final IconData icon;
  final String label;
}

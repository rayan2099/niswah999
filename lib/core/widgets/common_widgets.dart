import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Reusable card component matching web design
class NiswahCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final double? elevation;

  const NiswahCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius ?? 32),
        border: Border.all(
          color: borderColor ?? AppColors.shadowColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius ?? 32),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Screen header with title
class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final EdgeInsets? padding;

  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: titleColor ?? AppColors.brandPrimary,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Centered mobile canvas container
class MobileCanvas extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  final MainAxisAlignment? mainAxisAlignment;

  const MobileCanvas({
    super.key,
    required this.children,
    this.padding,
    this.mainAxisAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisAlignment: mainAxisAlignment ?? MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

/// Section divider with optional label
class SectionDivider extends StatelessWidget {
  final String? label;
  final EdgeInsets? padding;

  const SectionDivider({
    super.key,
    this.label,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return Padding(
        padding: padding ?? const EdgeInsets.symmetric(vertical: 16),
        child: Divider(
          color: AppColors.shadowColor,
          height: 1,
        ),
      );
    }

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.shadowColor, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label!,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(child: Divider(color: AppColors.shadowColor, height: 1)),
        ],
      ),
    );
  }
}

/// Stat display card
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? backgroundColor;
  final Color? accentColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.backgroundColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return NiswahCard(
      backgroundColor: backgroundColor ?? AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: accentColor ?? AppColors.brandPrimary,
                ),
              ),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    unit!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// List tile matching web design
class NiswahListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const NiswahListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.shadowColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      icon,
                      color: AppColors.brandPrimary,
                      size: 24,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[trailing!] else ...[const SizedBox.shrink()],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

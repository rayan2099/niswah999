import 'package:flutter/material.dart';

import '../localization/app_locale_controller.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

class LoadErrorBanner extends StatelessWidget {
  const LoadErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md + 4),
    decoration: BoxDecoration(
      color: AppColors.rosePale,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFCDD5)),
    ),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.haid, size: 30),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9F1239), fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: onRetry,
          child: Text(AppLocaleController.instance.text('Retry', 'إعادة')),
        ),
      ],
    ),
  );
}

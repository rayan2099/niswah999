import 'package:flutter/material.dart';

import '../../../../../core/localization/app_locale_controller.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/common_widgets.dart';
import '../../domain/entities/prayer_entry.dart' as prayer_domain;
import '../viewmodels/prayer_tracking_view_model.dart';

String _pt(String en, String ar) => AppLocaleController.instance.text(en, ar);

class PrayerTrackingScreen extends StatefulWidget {
  const PrayerTrackingScreen({super.key});

  @override
  State<PrayerTrackingScreen> createState() => _PrayerTrackingScreenState();
}

class _PrayerTrackingScreenState extends State<PrayerTrackingScreen> {
  late final PrayerTrackingViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = PrayerTrackingViewModel();
    _viewModel.loadToday(userId: 'demo-user');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final schedule = _viewModel.getTodaySchedule();

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _viewModel.isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: _pt('Loading', 'جارٍ التحميل'),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      ScreenHeader(
                        title: _pt('Prayer Times', 'أوقات الصلاة'),
                        subtitle: _pt("Today's Schedule", 'جدول اليوم'),
                        titleColor: AppColors.success,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PrayerSummaryCard(schedule: schedule),
                            const SizedBox(height: 28),
                            if (_viewModel.errorMessage != null)
                              NiswahCard(
                                backgroundColor: AppColors.error.withValues(
                                  alpha: 0.1,
                                ),
                                child: Text(
                                  _viewModel.errorMessage!,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: AppColors.error),
                                ),
                              )
                            else
                              _PrayerListView(
                                viewModel: _viewModel,
                                userId: 'demo-user',
                              ),
                            const SizedBox(height: 120),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PrayerSummaryCard extends StatelessWidget {
  const _PrayerSummaryCard({required this.schedule});

  final prayer_domain.PrayerSchedule schedule;

  @override
  Widget build(BuildContext context) {
    return NiswahCard(
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.mosque_rounded,
                  color: AppColors.success,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pt('Today\'s Schedule', 'جدول اليوم'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _pt('Five daily prayers', 'الصلوات الخمس'),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PrayerTimeChip(
                  label: _pt('Fajr', 'الفجر'),
                  time: schedule.fajr,
                ),
                const SizedBox(width: 12),
                _PrayerTimeChip(
                  label: _pt('Dhuhr', 'الظهر'),
                  time: schedule.dhuhr,
                ),
                const SizedBox(width: 12),
                _PrayerTimeChip(label: _pt('Asr', 'العصر'), time: schedule.asr),
                const SizedBox(width: 12),
                _PrayerTimeChip(
                  label: _pt('Maghrib', 'المغرب'),
                  time: schedule.maghrib,
                ),
                const SizedBox(width: 12),
                _PrayerTimeChip(
                  label: _pt('Isha', 'العشاء'),
                  time: schedule.isha,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrayerTimeChip extends StatelessWidget {
  const _PrayerTimeChip({required this.label, required this.time});

  final String label;
  final prayer_domain.TimeOfDay time;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.shadowColor, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _PrayerListView extends StatelessWidget {
  const _PrayerListView({required this.viewModel, required this.userId});

  final PrayerTrackingViewModel viewModel;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final prayers = prayer_domain.PrayerName.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _pt('Daily Status', 'الحالة اليومية'),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
        ),
        ...prayers.asMap().entries.map((entry) {
          final prayerName = entry.value;
          final index = entry.key;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < prayers.length - 1 ? 12 : 0,
            ),
            child: _PrayerTile(
              prayerName: prayerName,
              status: viewModel.statusFor(prayerName),
              onChanged: (status) async {
                await viewModel.togglePrayerStatus(
                  userId: userId,
                  prayerName: prayerName,
                  status: status,
                );
              },
            ),
          );
        }),
      ],
    );
  }
}

class _PrayerTile extends StatelessWidget {
  const _PrayerTile({
    required this.prayerName,
    required this.status,
    required this.onChanged,
  });

  final prayer_domain.PrayerName prayerName;
  final prayer_domain.PrayerStatus status;
  final ValueChanged<prayer_domain.PrayerStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return NiswahCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  prayerName.name[0].toUpperCase() +
                      prayerName.name.substring(1),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusButton(
                label: _pt('Completed', 'صُلّيت'),
                selected: status == prayer_domain.PrayerStatus.completed,
                color: AppColors.success,
                onTap: () => onChanged(prayer_domain.PrayerStatus.completed),
              ),
              _StatusButton(
                label: _pt('Missed', 'فائتة'),
                selected: status == prayer_domain.PrayerStatus.missed,
                color: AppColors.warning,
                onTap: () => onChanged(prayer_domain.PrayerStatus.missed),
              ),
              _StatusButton(
                label: _pt('Excused', 'معذورة'),
                selected: status == prayer_domain.PrayerStatus.excused,
                color: AppColors.error,
                onTap: () => onChanged(prayer_domain.PrayerStatus.excused),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final prayer_domain.PrayerStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      prayer_domain.PrayerStatus.pending => (
        _pt('Pending', 'قادمة'),
        AppColors.textTertiary,
      ),
      prayer_domain.PrayerStatus.completed => (
        _pt('Completed', 'صُلّيت'),
        AppColors.success,
      ),
      prayer_domain.PrayerStatus.missed => (
        _pt('Missed', 'فائتة'),
        AppColors.warning,
      ),
      prayer_domain.PrayerStatus.excused => (
        _pt('Excused', 'معذورة'),
        AppColors.error,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : AppColors.surfaceHover,
          border: Border.all(
            color: selected ? color : AppColors.shadowColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? color : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

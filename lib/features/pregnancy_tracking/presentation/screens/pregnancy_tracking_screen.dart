import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../domain/controllers/pregnancy_calculator.dart';
import '../../domain/entities/pregnancy_milestone.dart';
import '../viewmodels/pregnancy_tracking_view_model.dart';

String _pg(String en, String ar) => AppLocaleController.instance.text(en, ar);

class PregnancyTrackingScreen extends StatefulWidget {
  const PregnancyTrackingScreen({super.key});

  @override
  State<PregnancyTrackingScreen> createState() =>
      _PregnancyTrackingScreenState();
}

class _PregnancyTrackingScreenState extends State<PregnancyTrackingScreen> {
  late final PregnancyTrackingViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = PregnancyTrackingViewModel();
    _viewModel.loadMilestones();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final milestone = _viewModel.currentMilestone;
        final trimesterLabel = switch (_viewModel.currentTrimester) {
          PregnancyTrimester.first => _pg('First Trimester', 'الثلث الأول'),
          PregnancyTrimester.second => _pg('Second Trimester', 'الثلث الثاني'),
          PregnancyTrimester.third => _pg('Third Trimester', 'الثلث الثالث'),
        };

        return Scaffold(
          appBar: AppBar(
            title: Text(_pg('Pregnancy tracking', 'متابعة الحمل')),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: _pg('Refresh', 'تحديث'),
                onPressed: _viewModel.loadMilestones,
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _viewModel.loadMilestones(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OverviewCard(
                      week: _viewModel.currentWeek,
                      trimester: trimesterLabel,
                      dueDate: _viewModel.dueDate,
                      label: milestone.label,
                    ),
                    const SizedBox(height: 20),
                    _MilestoneCard(milestone: milestone),
                    const SizedBox(height: 20),
                    _DailyTrackerCard(viewModel: _viewModel),
                    if (_viewModel.errorMessage != null) ...[
                      const SizedBox(height: 20),
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_viewModel.errorMessage!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.week,
    required this.trimester,
    required this.dueDate,
    required this.label,
  });

  final int week;
  final String trimester;
  final DateTime dueDate;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pregnant_woman_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  _pg('Pregnancy overview', 'نظرة عامة على الحمل'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _MetricTile(
                  label: _pg('Week', 'الأسبوع'),
                  value: '$week',
                  icon: Icons.calendar_month_rounded,
                ),
                const SizedBox(width: 12),
                _MetricTile(
                  label: _pg('Trimester', 'الثلث'),
                  value: trimester,
                  icon: Icons.auto_awesome_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${_pg('Estimated due date', 'موعد الولادة المتوقع')}: ${dueDate.day}/${dueDate.month}/${dueDate.year}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.milestone});

  final PregnancyMilestoneSnapshot milestone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pg('Current milestone', 'المرحلة الحالية'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '${_pg('Week', 'الأسبوع')} ${milestone.week}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              milestone.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              milestone.summary,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTrackerCard extends StatelessWidget {
  const _DailyTrackerCard({required this.viewModel});

  final PregnancyTrackingViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pg('Daily tracker', 'المتابعة اليومية'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: viewModel.hydrationTargetMet,
              onChanged: (value) =>
                  viewModel.setHydrationTargetMet(value ?? false),
              title: Text(_pg('Hydration goal met', 'تم تحقيق هدف شرب الماء')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: viewModel.movementLogged,
              onChanged: (value) => viewModel.setMovementLogged(value ?? false),
              title: Text(_pg('Movement logged', 'تم تسجيل الحركة')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: viewModel.symptomsTracked,
              onChanged: (value) =>
                  viewModel.setSymptomsTracked(value ?? false),
              title: Text(_pg('Symptoms tracked', 'تم تتبع الأعراض')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),
            TextField(
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _pg('Notes', 'ملاحظات'),
                border: const OutlineInputBorder(),
                hintText: _pg(
                  'Add a brief reflection or update for today…',
                  'أضيفي ملاحظة قصيرة عن يومكِ…',
                ),
              ),
              onChanged: viewModel.updateNotes,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: viewModel.isLoading
                    ? null
                    : viewModel.saveDailyTracker,
                icon: const Icon(Icons.save_rounded),
                label: Text(
                  viewModel.isLoading
                      ? _pg('Saving…', 'جارٍ الحفظ…')
                      : _pg('Save daily update', 'حفظ التحديث اليومي'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

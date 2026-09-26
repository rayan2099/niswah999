import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../domain/entities/notification_preference.dart';
import '../viewmodels/notification_settings_view_model.dart';

String _ns(String en, String ar) => AppLocaleController.instance.text(en, ar);

// Closure Blocker 7 — matches NotificationRefreshCoordinator's own
// pre-customization default, purely for display before she has ever set
// a preference; the scheduler applies this identical default
// independently, so the two can never disagree.
const _defaultActiveBleedingHour = 18;
const _defaultActiveBleedingMinute = 0;

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = NotificationSettingsViewModel();
    _viewModel.loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_ns('Notification settings', 'إعدادات التنبيهات')),
          ),
          body: SafeArea(
            child: _viewModel.isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: _ns('Loading', 'جارٍ التحميل'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: NotificationType.values.map((type) {
                      final preference =
                          _viewModel.preferences[type] ??
                          NotificationPreference(
                            type: type,
                            enabled: type == NotificationType.prayer,
                            leadTimeMinutes: 15,
                            channels: const ['local'],
                          );

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _label(type),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  Switch(
                                    value: preference.enabled,
                                    onChanged: (value) {
                                      _viewModel.updatePreference(
                                        type: type,
                                        enabled: value,
                                        leadTimeMinutes:
                                            preference.leadTimeMinutes,
                                        channels: preference.channels,
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Closure Blocker 7 — activeBleeding is a
                              // real once-a-day check-in at a chosen
                              // clock time, never a "lead time" before
                              // some other event; the generic
                              // leadTimeMinutes slider every other type
                              // uses was a false control here (the
                              // scheduler never read it).
                              if (type == NotificationType.activeBleeding)
                                _ReminderTimeRow(
                                  hour:
                                      preference.preferredHour ??
                                      _defaultActiveBleedingHour,
                                  minute:
                                      preference.preferredMinute ??
                                      _defaultActiveBleedingMinute,
                                  onChanged: (hour, minute) {
                                    _viewModel.updatePreference(
                                      type: type,
                                      enabled: preference.enabled,
                                      leadTimeMinutes:
                                          preference.leadTimeMinutes,
                                      channels: preference.channels,
                                      preferredHour: hour,
                                      preferredMinute: minute,
                                    );
                                  },
                                )
                              else ...[
                                Text(
                                  '${_ns('Lead time', 'وقت التنبيه المسبق')}: ${preference.leadTimeMinutes} ${_ns('minutes', 'دقيقة')}',
                                ),
                                const SizedBox(height: 12),
                                Slider(
                                  value: preference.leadTimeMinutes.toDouble(),
                                  min: 0,
                                  max: 120,
                                  divisions: 12,
                                  label:
                                      '${preference.leadTimeMinutes} ${_ns('min', 'د')}',
                                  onChanged: (value) {
                                    _viewModel.updatePreference(
                                      type: type,
                                      enabled: preference.enabled,
                                      leadTimeMinutes: value.round(),
                                      channels: preference.channels,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        );
      },
    );
  }

  String _label(NotificationType type) {
    return switch (type) {
      NotificationType.prayer => _ns(
        'Daily prayer reminders',
        'تذكيرات الصلاة اليومية',
      ),
      NotificationType.cycle => _ns(
        'Cycle tracking reminders',
        'تذكيرات تتبع الدورة',
      ),
      NotificationType.pregnancy => _ns(
        'Pregnancy milestone updates',
        'تحديثات مراحل الحمل',
      ),
      NotificationType.wellbeing => _ns(
        'Daily wellbeing check-in',
        'تذكير الحالة النفسية اليومي',
      ),
      NotificationType.activeBleeding => _ns(
        'Daily check-in reminder',
        'تذكير المتابعة اليومية',
      ),
    };
  }
}

/// Closure Blocker 7 — the real control for [NotificationType.
/// activeBleeding]'s chosen time of day, replacing the generic (and
/// previously unused) lead-time slider for this one reminder type.
class _ReminderTimeRow extends StatelessWidget {
  const _ReminderTimeRow({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_ns('Reminder time', 'وقت التذكير')}: ${time.format(context)}',
          ),
        ),
        TextButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (picked != null) onChanged(picked.hour, picked.minute);
          },
          child: Text(_ns('Change', 'تغيير')),
        ),
      ],
    );
  }
}

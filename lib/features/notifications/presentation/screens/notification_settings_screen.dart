import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/services/notification_service.dart';
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
  const NotificationSettingsScreen({super.key, this.notificationsEnabled});

  /// Reads whether the OS lets the app show notifications (`null` = unknown).
  /// Defaults to the real [NotificationService]; tests inject their own.
  final Future<bool?> Function()? notificationsEnabled;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  late final NotificationSettingsViewModel _viewModel;

  /// `false` = the OS will not show this app's notifications, so every switch
  /// below can read ON while nothing can ever appear. `null` = unknown.
  bool? _osNotificationsEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = NotificationSettingsViewModel();
    _viewModel.loadPreferences();
    _refreshOsPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// She may have just turned notifications on in the phone's settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOsPermission();
  }

  Future<void> _refreshOsPermission() async {
    final check =
        widget.notificationsEnabled ??
        NotificationService.instance.areNotificationsEnabled;
    final enabled = await check();
    if (!mounted) return;
    setState(() => _osNotificationsEnabled = enabled);
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
                    children: [
                      if (_osNotificationsEnabled == false)
                        const _NotificationsBlockedNotice(),
                      ...NotificationType.values.map((type) {
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
                                    value: preference.leadTimeMinutes
                                        .toDouble(),
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
                      }),
                    ],
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

/// Shown while the OS does not let the app show notifications — otherwise
/// every switch on this screen can read ON while no reminder can ever appear
/// (a silent failure, found by the notification acceptance persona).
class _NotificationsBlockedNotice extends StatelessWidget {
  const _NotificationsBlockedNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('notifications-blocked-notice'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notifications_off_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ns(
                      'Notifications are not allowed for Niswah',
                      'التنبيهات غير مسموح بها لنِسواه',
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ns(
                      'Reminders cannot appear until you allow notifications '
                          "for Niswah in your phone's settings.",
                      'لن تظهر التذكيرات حتى تسمحي بالتنبيهات لنِسواه من '
                          'إعدادات هاتفكِ.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

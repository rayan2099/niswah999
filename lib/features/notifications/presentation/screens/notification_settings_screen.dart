import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../domain/entities/notification_preference.dart';
import '../viewmodels/notification_settings_view_model.dart';

String _ns(String en, String ar) => AppLocaleController.instance.text(en, ar);

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
                ? const Center(child: CircularProgressIndicator())
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
    };
  }
}

import 'package:flutter/material.dart';

import '../../../../core/config/launch_features.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/notification_delivery_preferences.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/device_timezone.dart';
import '../../data/services/app_notification_session.dart';
import '../../domain/services/notification_refresh_coordinator.dart';

class NotificationControlsCard extends StatefulWidget {
  const NotificationControlsCard({super.key});
  @override
  State<NotificationControlsCard> createState() =>
      _NotificationControlsCardState();
}

class _NotificationControlsCardState extends State<NotificationControlsCard> {
  final _prefs = NotificationDeliveryPreferences.instance;
  bool _busy = true;
  String? _error;
  String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);
  @override
  void initState() {
    super.initState();
    AppNotificationSession.instance.availability.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppNotificationSession.instance.availability.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    final client = NiswahSupabase.clientOrNull,
        user = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    try {
      await _prefs.load();
      if (client != null && user != null) {
        final row = await client
            .from('notification_preferences')
            .select()
            .eq('user_id', user)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        if (client.auth.currentUser?.id != user || !mounted) return;
        if (row != null) {
          _prefs.apply(row);
          await _prefs.save();
        }
      }
    } catch (_) {
      _error = _t(
        'Activity settings could not be synced. Retry your changes.',
        'تعذّرت مزامنة إعدادات النشاط. أعيدي المحاولة.',
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _change(Map<String, dynamic> changes) async {
    if (_busy) return;
    final client = NiswahSupabase.clientOrNull,
        user = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    final session = NotificationService.instance.sessionGeneration;
    final old = _prefs.toJson(), next = {...old, ...changes};
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Validate before persisting; quiet windows cannot mean every hour.
      _prefs.apply(next);
      final zone = await DeviceTimezone.currentId(forceRefresh: true);
      if (_prefs.quietEnabled && zone == null) {
        throw StateError('Timezone unavailable');
      }
      if (client != null && user != null) {
        await client
            .from('notification_preferences')
            .upsert({
              ...next,
              'user_id': user,
              // An unreadable zone must not overwrite the last known one.
              'timezone': ?zone,
              'locale': AppLocaleController.instance.isArabic ? 'ar' : 'en',
            })
            .timeout(const Duration(seconds: 10));
        if (client.auth.currentUser?.id != user ||
            session != NotificationService.instance.sessionGeneration) {
          return;
        }
      }
      _prefs.apply(next);
      await _prefs.save(snapshot: next);
      if (changes.entries.any(
        (e) =>
            {'messages', 'comments', 'likes'}.contains(e.key) &&
            e.value == true,
      )) {
        await NotificationService.instance.requestPermission();
        await AppNotificationSession.instance.refreshRegistration();
      }
      await NotificationRefreshCoordinator.refresh(userId: user);
    } catch (_) {
      if (client?.auth.currentUser?.id == user &&
          session == NotificationService.instance.sessionGeneration) {
        _prefs.apply(old);
      }
      _error = _t(
        'Could not save these changes. Please try again.',
        'تعذّر حفظ التغييرات. حاولي مجددًا.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enablePhoneAlerts() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final granted = await NotificationService.instance.requestPermission();
      if (granted) {
        await AppNotificationSession.instance.refreshRegistration();
      } else {
        _error = _t(
          'Notifications are blocked for Niswah. Allow them in your phone settings.',
          'التنبيهات محظورة لتطبيق نِسواه. اسمحي بها من إعدادات هاتفكِ.',
        );
      }
    } catch (_) {
      _error = _t(
        'Phone alerts could not be turned on. Please try again.',
        'تعذّر تفعيل تنبيهات الهاتف. حاولي مجددًا.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _time(bool start) async {
    final minute = start ? _prefs.quietStart : _prefs.quietEnd;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (time != null && mounted) {
      await _change({
        start ? 'quiet_start' : 'quiet_end': time.hour * 60 + time.minute,
      });
    }
  }

  String _clock(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            LaunchFeatures.community
                ? _t(
                    'Messages, community & quiet hours',
                    'الرسائل والمجتمع وساعات الهدوء',
                  )
                : _t('Quiet hours', 'ساعات الهدوء'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!AppNotificationSession.instance.phoneAlertsConfigured) ...[
            Text(
              _t(
                'Phone alerts are not active on this device. Activity is still available in the inbox.',
                'تنبيهات الهاتف غير مفعّلة على هذا الجهاز. يبقى النشاط متاحًا في صندوق التنبيهات.',
              ),
            ),
            // Messages and comments are on by default, so without this a
            // person would have to toggle a switch off and on to be asked.
            if (AppNotificationSession.enabled)
              TextButton(
                onPressed: _busy ? null : _enablePhoneAlerts,
                child: Text(_t('Turn on phone alerts', 'تفعيل تنبيهات الهاتف')),
              ),
          ],
          // Community alerts are hidden with community ([LaunchFeatures]).
          if (LaunchFeatures.community) ...[
            SwitchListTile(
              title: Text(
                _t(
                  'Phone alerts for new messages',
                  'تنبيهات الهاتف للرسائل الجديدة',
                ),
              ),
              value: _prefs.messages,
              onChanged: _busy ? null : (v) => _change({'messages': v}),
            ),
            SwitchListTile(
              title: Text(_t('Comments on my posts', 'التعليقات على منشوراتي')),
              value: _prefs.comments,
              onChanged: _busy ? null : (v) => _change({'comments': v}),
            ),
            SwitchListTile(
              title: Text(
                _t('Grouped likes on my posts', 'إعجابات مجمّعة على منشوراتي'),
              ),
              value: _prefs.likes,
              onChanged: _busy ? null : (v) => _change({'likes': v}),
            ),
          ],
          SwitchListTile(
            title: Text(_t('Quiet hours', 'ساعات الهدوء')),
            value: _prefs.quietEnabled,
            onChanged: _busy ? null : (v) => _change({'quiet_enabled': v}),
          ),
          if (_prefs.quietEnabled) ...[
            ListTile(
              title: Text(_t('From', 'من')),
              trailing: Text(_clock(_prefs.quietStart)),
              onTap: _busy ? null : () => _time(true),
            ),
            ListTile(
              title: Text(_t('Until', 'إلى')),
              trailing: Text(_clock(_prefs.quietEnd)),
              onTap: _busy ? null : () => _time(false),
            ),
            Text(
              _t(
                'Scheduled reminders inside this window are skipped. Choose reminder times outside it. Incoming activity stays in your inbox.',
                'تُتجاوز التذكيرات المجدولة ضمن هذه الفترة. اختاري أوقاتها خارجها. يبقى النشاط الوارد في صندوق التنبيهات.',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

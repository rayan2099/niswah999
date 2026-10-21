import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/utils/app_clock.dart';
import '../../domain/services/prayer_schedule_builder.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

const prayerMethods = {
  'muslimWorldLeague': ['Muslim World League', 'رابطة العالم الإسلامي'],
  'ummAlQura': ['Umm al-Qura', 'أم القرى'],
  'egyptian': ['Egyptian Survey Authority', 'الهيئة المصرية للمساحة'],
  'dubai': ['Dubai', 'دبي'],
  'northAmerica': ['ISNA', 'أمريكا الشمالية ISNA'],
  'karachi': ['Karachi', 'كراتشي'],
};

String prayerMethodLabel(String method) {
  final names = prayerMethods[method];
  return names == null ? method : _t(names[0], names[1]);
}

Future<void> showPrayerSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PrayerSettingsSheet(),
    );

class _PrayerSettingsSheet extends StatefulWidget {
  const _PrayerSettingsSheet();
  @override
  State<_PrayerSettingsSheet> createState() => _PrayerSettingsSheetState();
}

class _PrayerSettingsSheetState extends State<_PrayerSettingsSheet> {
  final controller = PrayerLocationController.instance;
  bool busy = false;
  String? error;

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        error = _t(
          'Unable to save or detect location. Check permissions and try again.',
          'تعذر الحفظ أو تحديد الموقع. تحققي من الأذونات وحاولي مجددًا.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseZone() async {
    PrayerScheduleBuilder.initializeZones();
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    final result = await showSearch<String?>(
      context: context,
      delegate: _ZoneSearch(zones),
    );
    final location = controller.selectedOrNull;
    if (result == null || location == null || !mounted) return;
    await perform(
      () => controller.select(
        PrayerLocation(
          latitude: location.latitude,
          longitude: location.longitude,
          label: location.label,
          timezoneId: result,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final location = controller.selectedOrNull;
      final validMethod = prayerMethods.containsKey(controller.method);
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _t('Prayer settings', 'إعدادات مواقيت الصلاة'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                'Confirm your place, timezone and local calculation convention. Refresh GPS after travelling. Calculated times can differ from your local mosque.',
                'تأكدي من الموقع والمنطقة الزمنية وطريقة الحساب المعتمدة محليًا. حدّثي الموقع بعد السفر. قد تختلف المواقيت المحسوبة عن مسجدكِ.',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final preset in PrayerLocationController.presets)
              ListTile(
                title: Text(
                  prayerLocationLabel(
                    preset,
                    isArabic: AppLocaleController.instance.isArabic,
                  ),
                ),
                trailing: location == preset ? const Icon(Icons.check) : null,
                enabled: !busy,
                onTap: () => perform(() => controller.select(preset)),
              ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      await controller.useDeviceLocation();
                    }),
              icon: const Icon(Icons.my_location),
              label: Text(
                _t('Use / refresh GPS location', 'تحديد / تحديث الموقع الحالي'),
              ),
            ),
            if (location != null) ...[
              Text(
                prayerLocationLabel(
                  location,
                  isArabic: AppLocaleController.instance.isArabic,
                ),
              ),
              ListTile(
                title: Text(
                  _t(
                    'Timezone — tap to confirm or change',
                    'المنطقة الزمنية — اضغطي للتأكيد أو التغيير',
                  ),
                ),
                subtitle: Text(
                  '${location.timezoneId ?? _t('Required', 'مطلوبة')}${location.timezoneConfirmed ? '' : _t(' — choose and confirm the timezone for this location', ' — اختاري وأكدي المنطقة الزمنية لهذا الموقع')}',
                ),
                onTap: busy ? null : chooseZone,
              ),
            ],
            DropdownButtonFormField<String>(
              initialValue: validMethod ? controller.method : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('Calculation method', 'طريقة الحساب'),
              ),
              items: prayerMethods.keys
                  .map(
                    (key) => DropdownMenuItem(
                      value: key,
                      child: Text(prayerMethodLabel(key)),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (method) {
                      if (method != null) {
                        perform(
                          () => controller.configure(
                            method: method,
                            hanafiAsr: controller.hanafiAsr,
                          ),
                        );
                      }
                    },
            ),
            SwitchListTile(
              title: Text(_t('Hanafi Asr calculation', 'حساب العصر الحنفي')),
              subtitle: Text(
                _t(
                  'Off: standard shadow factor. This setting does not change your menstrual fiqh madhhab.',
                  'عند الإيقاف: حساب العصر المعتاد. هذا الإعداد لا يغيّر مذهب أحكام الحيض.',
                ),
              ),
              value: controller.hanafiAsr,
              onChanged: busy
                  ? null
                  : (value) => perform(
                      () => controller.configure(
                        method: controller.method,
                        hanafiAsr: value,
                        ramadanAdjustmentUntil:
                            controller.ramadanAdjustmentUntil,
                      ),
                    ),
            ),
            if (controller.method == 'ummAlQura')
              ListTile(
                title: Text(
                  _t(
                    'Ramadan: Isha +30 minutes',
                    'رمضان: إضافة ٣٠ دقيقة للعشاء',
                  ),
                ),
                subtitle: Text(
                  controller.ramadanAdjustmentUntil == null
                      ? _t(
                          'Off. Confirm Ramadan locally, then choose its final date.',
                          'متوقفة. تحققي من رمضان محليًا ثم اختاري تاريخ آخر يوم.',
                        )
                      : '${_t('Through', 'حتى')} ${controller.ramadanAdjustmentUntil!.toIso8601String().substring(0, 10)}',
                ),
                trailing: controller.ramadanAdjustmentUntil == null
                    ? null
                    : IconButton(
                        tooltip: _t('Remove adjustment', 'إلغاء الإضافة'),
                        icon: const Icon(Icons.clear),
                        onPressed: busy
                            ? null
                            : () => perform(
                                () => controller.configure(
                                  method: controller.method,
                                  hanafiAsr: controller.hanafiAsr,
                                ),
                              ),
                      ),
                onTap: busy
                    ? null
                    : () async {
                        final now = AppClock.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final until = await showDatePicker(
                          context: context,
                          initialDate: today,
                          firstDate: today,
                          lastDate: today.add(const Duration(days: 30)),
                        );
                        if (until != null && mounted) {
                          await perform(
                            () => controller.configure(
                              method: controller.method,
                              hanafiAsr: controller.hanafiAsr,
                              ramadanAdjustmentUntil: until,
                            ),
                          );
                        }
                      },
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(_t('Done', 'تم')),
            ),
          ],
        ),
      );
    },
  );
}

class _ZoneSearch extends SearchDelegate<String?> {
  _ZoneSearch(this.zones)
    : super(
        searchFieldLabel: _t(
          'Search city or timezone',
          'ابحثي عن مدينة أو منطقة زمنية',
        ),
      );
  final List<String> zones;
  static const labels = {
    'Asia/Riyadh': ['Saudi Arabia — Riyadh', 'السعودية — الرياض'],
    'Asia/Dubai': ['UAE — Dubai', 'الإمارات — دبي'],
    'Africa/Cairo': ['Egypt — Cairo', 'مصر — القاهرة'],
    'America/New_York': ['New York', 'نيويورك'],
    'America/Toronto': ['Toronto', 'تورونتو'],
    'America/Vancouver': ['Vancouver', 'فانكوفر'],
    'Europe/London': ['London', 'لندن'],
    'Europe/Paris': ['Paris', 'باريس'],
  };
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
  @override
  Widget buildSuggestions(BuildContext context) {
    final matches = zones
        .where(
          (zone) => '$zone ${labels[zone]?.join(' ') ?? ''}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) => ListTile(
        title: Text(
          labels[matches[index]] == null
              ? matches[index]
              : _t(labels[matches[index]]![0], labels[matches[index]]![1]),
        ),
        subtitle: labels[matches[index]] == null ? null : Text(matches[index]),
        onTap: () => close(context, matches[index]),
      ),
    );
  }
}

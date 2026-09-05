import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

class GhuslGuideScreen extends StatefulWidget {
  const GhuslGuideScreen({super.key});

  @override
  State<GhuslGuideScreen> createState() => _GhuslGuideScreenState();
}

class _GhuslGuideScreenState extends State<GhuslGuideScreen> {
  int step = 0;
  int washes = 0;
  final Set<int> checks = {};
  final Set<String> options = {};

  late final List<
    ({
      String title,
      String body,
      IconData icon,
      List<String> checks,
      bool counter,
    })
  >
  steps = [
    (
      title: _t('Make the intention', 'النية'),
      body: _t(
        'Intend in your heart to purify yourself from major ritual impurity.',
        'انوي بقلبكِ رفع الحدث الأكبر والتطهر.',
      ),
      icon: Icons.pan_tool_outlined,
      checks: const [],
      counter: false,
    ),
    (
      title: _t('Wash both hands', 'غسل اليدين'),
      body: _t(
        'Wash both hands thoroughly three times.',
        'اغسلي يديكِ جيداً ثلاث مرات.',
      ),
      icon: Icons.waves_rounded,
      checks: const [],
      counter: true,
    ),
    (
      title: _t('Remove impurity', 'إزالة النجاسة'),
      body: _t(
        'Wash away every visible trace of impurity.',
        'أزيلي كل أثر ظاهر للنجاسة.',
      ),
      icon: Icons.cleaning_services_outlined,
      checks: const [],
      counter: false,
    ),
    (
      title: _t('Perform wudu', 'الوضوء'),
      body: _t(
        'Perform a complete wudu as you do for prayer.',
        'توضئي وضوءاً كاملاً كما تتوضئين للصلاة.',
      ),
      icon: Icons.water_drop_outlined,
      checks: [
        _t('Wash the face', 'غسل الوجه'),
        _t('Wash the arms', 'غسل اليدين إلى المرفقين'),
        _t('Wipe the head', 'مسح الرأس'),
        _t('Wash the feet', 'غسل القدمين'),
      ],
      counter: false,
    ),
    (
      title: _t('Wash the right side', 'غسل الجانب الأيمن'),
      body: _t(
        'Pour water over the right side three times.',
        'أفيضي الماء على الجانب الأيمن ثلاث مرات.',
      ),
      icon: Icons.chevron_right_rounded,
      checks: const [],
      counter: true,
    ),
    (
      title: _t('Wash the left side', 'غسل الجانب الأيسر'),
      body: _t(
        'Pour water over the left side three times.',
        'أفيضي الماء على الجانب الأيسر ثلاث مرات.',
      ),
      icon: Icons.chevron_left_rounded,
      checks: const [],
      counter: true,
    ),
    (
      title: _t('Complete coverage', 'التأكد من عموم الماء'),
      body: _t(
        'Make sure water has reached every part of the body.',
        'تأكدي من وصول الماء إلى جميع أجزاء البدن.',
      ),
      icon: Icons.verified_user_outlined,
      checks: [
        _t('Hair roots', 'أصول الشعر'),
        _t('Behind the ears', 'خلف الأذنين'),
        _t('Underarms', 'تحت الإبطين'),
        _t('Navel', 'السرة'),
        _t('Between toes', 'بين أصابع القدمين'),
      ],
      counter: false,
    ),
  ];

  bool get complete => steps[step].counter
      ? washes == 3
      : steps[step].checks.isEmpty ||
            checks.length == steps[step].checks.length;

  @override
  Widget build(BuildContext context) {
    final item = steps[step];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF064E3B)),
          tooltip: _t('Close', 'إغلاق'),
          onPressed: () => Navigator.pop(context),
        ),
        title: LinearProgressIndicator(
          value: (step + 1) / steps.length,
          minHeight: 6,
          borderRadius: BorderRadius.circular(99),
          color: const Color(0xFF10B981),
          backgroundColor: const Color(0xFFF3F4F6),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 22),
            child: Center(
              child: Text(
                '${step + 1}/${steps.length}',
                style: const TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontFamily: AppTypography.serifFamily,
                    fontSize: 30,
                    height: 1.15,
                    color: const Color(0xFF064E3B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.body,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 30),
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      item.icon,
                      color: const Color(0xFFA7F3D0),
                      size: 128,
                    ),
                  ),
                ),
                if (step == 0) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFD1FAE5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'بِسْمِ الله',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: AppTypography.arabicFamily,
                            color: const Color(0xFF064E3B),
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _t('In the name of Allah', 'باسم الله'),
                          style: const TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (item.counter) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: washes > i
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF3F4F6),
                          child: washes > i
                              ? const Icon(Icons.check, color: Colors.white)
                              : Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: FilledButton.tonal(
                      onPressed: washes < 3
                          ? () => setState(() => washes++)
                          : null,
                      child: Text(_t('TAP TO WASH', 'اضغطي بعد كل غسلة')),
                    ),
                  ),
                ],
                if (item.checks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ...item.checks.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CheckTile(
                        label: e.value,
                        active: checks.contains(e.key),
                        onTap: () => setState(
                          () => checks.contains(e.key)
                              ? checks.remove(e.key)
                              : checks.add(e.key),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              28,
              18,
              28,
              MediaQuery.paddingOf(context).bottom + 18,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0x0D000000))),
            ),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _pill('Locs / braids', 'ضفائر'),
                      _pill('Acrylic nails', 'أظافر صناعية'),
                      _pill('Wound / cast', 'جرح أو جبيرة'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: step == 0
                          ? null
                          : () => setState(() {
                              step--;
                              washes = 0;
                              checks.clear();
                            }),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: complete
                            ? () {
                                if (step == steps.length - 1) {
                                  _complete();
                                } else {
                                  setState(() {
                                    step++;
                                    washes = 0;
                                    checks.clear();
                                  });
                                }
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          step == steps.length - 1
                              ? _t('Finish Ghusl', 'إتمام الغسل')
                              : _t('Next', 'التالي'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String en, String ar) {
    final label = _t(en, ar);
    final active = options.contains(en);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        selected: active,
        selectedColor: const Color(0xFF059669),
        labelStyle: TextStyle(
          color: active ? Colors.white : const Color(0xFF9CA3AF),
        ),
        onSelected: (_) =>
            setState(() => active ? options.remove(en) : options.add(en)),
      ),
    );
  }

  void _complete() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF059669),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(Icons.auto_awesome, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text(
            _t('Alhamdulillah', 'الحمد لله'),
            style: TextStyle(
              fontFamily: AppTypography.serifFamily,
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _t('You are now in a state of Tahara', 'أنتِ الآن على طهارة'),
            style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 18),
          ),
          const SizedBox(height: 44),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF047857),
            ),
            child: Text(_t('Return home', 'العودة للرئيسية')),
          ),
        ],
      ),
    ),
  );
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFECFDF5) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? const Color(0xFFA7F3D0) : const Color(0x0D000000),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFF064E3B)
                    : const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          CircleAvatar(
            radius: 12,
            backgroundColor: active
                ? const Color(0xFF10B981)
                : Colors.transparent,
            child: Icon(
              active ? Icons.check : null,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    ),
  );
}

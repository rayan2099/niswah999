import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';

String _j(String en, String ar) => AppLocaleController.instance.text(en, ar);

class GuidedJourneysScreen extends StatelessWidget {
  const GuidedJourneysScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final data = [
      (
        _j('Understanding Your Cycle', 'فهم دورتكِ'),
        _j(
          'Build a confident foundation in cycle and Fiqh knowledge.',
          'ابني أساساً واثقاً في معرفة الدورة وأحكامها.',
        ),
        '30 ${_j('days', 'يوماً')}',
        Icons.calendar_month_outlined,
      ),
      (
        _j('Purity Essentials', 'أساسيات الطهارة'),
        _j(
          'A practical path through Tahara, Haid and Istihada.',
          'مسار عملي في الطهارة والحيض والاستحاضة.',
        ),
        '7 ${_j('days', 'أيام')}',
        Icons.menu_book_outlined,
      ),
      (
        _j('Pregnancy, Month by Month', 'الحمل شهراً بشهر'),
        _j(
          'Gentle guidance for every stage of pregnancy.',
          'إرشاد لطيف لكل مرحلة من مراحل الحمل.',
        ),
        _j('Month-by-month', 'شهراً بشهر'),
        Icons.favorite_border,
      ),
      (
        _j('Postpartum Recovery', 'التعافي بعد الولادة'),
        _j(
          'Spiritual and physical support through Nifas.',
          'دعم روحي وجسدي خلال فترة النفاس.',
        ),
        '40 ${_j('days', 'يوماً')}',
        Icons.auto_awesome_outlined,
      ),
      (
        _j('Living with PCOS', 'التعايش مع تكيس المبايض'),
        _j(
          'Track patterns with clarity and self-compassion.',
          'تتبعي الأنماط بوضوح ورحمة مع نفسكِ.',
        ),
        _j('Ongoing', 'مستمر'),
        Icons.verified_user_outlined,
      ),
      (
        _j('Preparing for Motherhood', 'الاستعداد للأمومة'),
        _j(
          'A mindful 90-day preparation journey.',
          'رحلة واعية للاستعداد خلال ٩٠ يوماً.',
        ),
        '90 ${_j('days', 'يوماً')}',
        Icons.bolt_outlined,
      ),
    ];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Color(0xFF064E3B)),
        ),
        title: Text(
          _j('Guided Journeys', 'الرحلات الإرشادية'),
          style: TextStyle(
            fontFamily: AppTypography.serifFamily,
            color: const Color(0xFF064E3B),
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF0F766E)],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Stack(
              children: [
                const PositionedDirectional(
                  end: -4,
                  top: -6,
                  child: Icon(
                    Icons.auto_awesome,
                    color: Color(0x26FFFFFF),
                    size: 100,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _j('Your path to clarity', 'طريقكِ إلى الوضوح'),
                      style: TextStyle(
                        fontFamily: AppTypography.serifFamily,
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: 250,
                      child: Text(
                        _j(
                          'Small daily lessons, rooted in faith and made for your life.',
                          'دروس يومية قصيرة، راسخة في الإيمان ومصممة لحياتكِ.',
                        ),
                        style: const TextStyle(
                          color: Color(0xCCECFDF5),
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ...data.asMap().entries.map(
            (e) => _JourneyCard(
              item: e.value,
              locked: e.key > 0,
              progress: e.key == 0,
              onTap: () => _lesson(context, e.value.$1),
            ),
          ),
        ],
      ),
    );
  }

  void _lesson(BuildContext context, String title) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF064E3B),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 60,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppTypography.serifFamily,
                  color: const Color(0xFF064E3B),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _j(
                  'In this lesson, we explore the foundational concepts within the context of your Fiqh school.',
                  'في هذا الدرس نستكشف المفاهيم الأساسية في سياق مذهبكِ الفقهي.',
                ),
                style: const TextStyle(color: Color(0xFF6B7280), height: 1.65),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(_j('Complete today', 'إكمال درس اليوم')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.item,
    required this.locked,
    required this.progress,
    required this.onTap,
  });
  final (String, String, String, IconData) item;
  final bool locked, progress;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0x0D000000)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(item.$4, color: const Color(0xFF059669)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          color: Color(0xFF064E3B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        item.$3.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF059669),
                          fontSize: 9,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (locked)
                  const Icon(
                    Icons.lock_outline,
                    color: Color(0xFFD1D5DB),
                    size: 19,
                  ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              item.$2,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (progress) ...[
              const SizedBox(height: 15),
              const LinearProgressIndicator(
                value: .4,
                color: Color(0xFF10B981),
                backgroundColor: Color(0xFFECFDF5),
                borderRadius: BorderRadius.all(Radius.circular(9)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

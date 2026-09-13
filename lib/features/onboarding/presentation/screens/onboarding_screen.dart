import 'package:flutter/material.dart';

import '../../../../core/auth/auth_controller.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/marital_status_controller.dart';
import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../cycle_tracking/data/repositories/cycle_tracking_repository_impl.dart';
import '../../../cycle_tracking/domain/entities/cycle_log.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart'
    show Madhhab;
import '../../../cycle_tracking/presentation/models/cycle_log_form_data.dart';

String _tr(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

/// Matches the order of both the English and Arabic choice lists in the
/// Madhhab step below.
const _madhhabOrder = [
  Madhhab.hanafi,
  Madhhab.maliki,
  Madhhab.shafii,
  Madhhab.hanbali,
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.initialStep = 1,
  });
  final VoidCallback onFinished;
  final int initialStep;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Streamlined onboarding flow (9 steps). Only ever shown to an already-
/// authenticated user — main.dart's root router (AUTH-002's contract)
/// gates every path here behind `auth.isAuthenticated == true`, so there
/// is deliberately no login/signup step in this state machine (AUTH-008):
/// 1 Splash → 2 Language → 3 Madhhab → 4 Married → 5 Location
/// → 6 Last Period → 7 Period Length → 8 Privacy → 9 Welcome
class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalSteps = 9;

  late int _step = widget.initialStep.clamp(1, _totalSteps);
  // Derived from the app-wide, SharedPreferences-persisted controller — not
  // a local copy — so a step re-selecting language stays in sync even if
  // this State is recreated mid-onboarding (e.g. by the router rebuilding
  // after an out-of-process email-confirmation session lands), instead of
  // silently resetting to English regardless of what was already chosen
  // and persisted (AUTH-007).
  bool get _arabic => AppLocaleController.instance.isArabic;
  String? _madhhab;
  bool? _isMarried;
  DateTime? _periodDate;
  double _haidLength = 5;
  bool _anonymous = false;

  @override
  void initState() {
    super.initState();
    // A returning user re-routed through onboarding (e.g. after signing
    // out) already has a saved answer — show it selected instead of blank,
    // otherwise re-selecting anything (or the step just looking unanswered)
    // silently overwrites their real answer via setMarried below.
    _isMarried = MaritalStatusController.instance.isMarried;
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: AppColors.brandBackground,
      body: SafeArea(
        child: Column(
          children: [
            if (_step > 1)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _step / _totalSteps),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: Colors.black.withValues(alpha: .04),
                  color: const Color(0xFFFDA4AF),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  if (_step > 2 && _step < _totalSteps)
                    PositionedDirectional(
                      top: 12,
                      start: 12,
                      child: IconButton(
                        onPressed: () => setState(() => _step--),
                        tooltip: _t('Back', 'رجوع'),
                        icon: Icon(
                          // A chevron is not a directional glyph in
                          // Flutter's icon font — it must be swapped
                          // explicitly, or "back" points visually toward
                          // reading-end in RTL instead of reading-start.
                          _arabic
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0.08, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: ScaleTransition(
                                scale: Tween(
                                  begin: .97,
                                  end: 1.0,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: ConstrainedBox(
                          key: ValueKey(_step),
                          constraints: const BoxConstraints(maxWidth: 390),
                          child: _screen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _screen() => switch (_step) {
    1 => _Splash(onNext: _next),
    2 => _Language(
      arabic: _arabic,
      onSelect: (v) => setState(() => AppLocaleController.instance.setArabic(v)),
      onNext: _next,
    ),
    // AUTH-008: step 3 used to be an embedded SignInScreen (login/signup)
    // here. It is removed — by the time any user ever reaches
    // OnboardingScreen at all, main.dart's own root router has already
    // required `auth.isAuthenticated == true` (see its own routing
    // contract doc comment); a login step inside onboarding was therefore
    // always redundant for every real path, and both forward navigation
    // (a fresh instance starting at step 1) and Back from Madhhab landed
    // an already-authenticated user on a live Sign In/Sign Up screen —
    // proven, reproducible, the exact defect the owner reported.
    3 => _Choices(
      title: _t('What is your Fiqh Madhhab?', 'ما مذهبكِ الفقهي؟'),
      subtitle: _t(
        'This helps us personalize Haid and prayer guidance.',
        'يساعدنا ذلك في تخصيص أحكام الحيض والصلاة.',
      ),
      choices: _madhhabChoices,
      selected: _madhhab == null ? {} : {_madhhab!},
      rules: _arabic
          ? const [
              'حد أدنى 3 أيام · حد أقصى 10 أيام',
              'لا يوجد حد أدنى · حد أقصى 15 يوماً',
              'حد أدنى 24 ساعة · حد أقصى 15 يوماً',
              'حد أدنى 24 ساعة · حد أقصى 15 يوماً',
            ]
          : const [
              '3-day min · 10-day max',
              'No minimum · 15-day max',
              '24-hour min · 15-day max',
              '24-hour min · 15-day max',
            ],
      onToggle: (v) {
        setState(() => _madhhab = v);
        MadhhabController.instance.select(
          _madhhabOrder[_madhhabChoices.indexOf(v)],
        );
      },
      onNext: _madhhab == null ? null : _next,
    ),
    4 => _Choices(
      title: _t('Are you married?', 'هل أنتِ متزوجة؟'),
      subtitle: _t(
        'This controls spouse-only pregnancy tools and reports.',
        'يُستخدم لإظهار أدوات الحمل وتقرير الزوج للمتزوجات فقط.',
      ),
      choices: _arabic ? const ['نعم', 'لا'] : const ['Yes', 'No'],
      selected: _isMarried == null
          ? {}
          : {_isMarried! ? (_arabic ? 'نعم' : 'Yes') : (_arabic ? 'لا' : 'No')},
      onToggle: (value) {
        final married = value == 'Yes' || value == 'نعم';
        setState(() => _isMarried = married);
        MaritalStatusController.instance.setMarried(married);
      },
      onNext: _isMarried == null ? null : _next,
    ),
    5 => _Location(
      onSelected: (location) =>
          PrayerLocationController.instance.select(location),
      onUseCurrentLocation: () => _useDeviceLocation(),
      onNext: _next,
    ),
    6 => _LastPeriod(
      selected: _periodDate,
      onSelect: (v) => setState(() => _periodDate = v),
      onNext: _periodDate == null ? null : _next,
      onUnsure: () {
        setState(() => _periodDate = null);
        _next();
      },
    ),
    7 => _NumberStep(
      title: _t('How long is your period?', 'كم تستمر مدة الحيض؟'),
      description: _madhhab == 'Hanafi' || _madhhab == 'حنفي'
          ? _t('Hanafi maximum: 10 days', 'الحد الأقصى للحنفية: 10 أيام')
          : _t('Madhhab maximum: 15 days', 'الحد الأقصى للمذهب: 15 يوماً'),
      value: _haidLength,
      min: 2,
      max: _madhhab == 'Hanafi' || _madhhab == 'حنفي' ? 10 : 15,
      onChanged: (v) => setState(() => _haidLength = v),
      onNext: _next,
    ),
    8 => _Privacy(
      anonymous: _anonymous,
      onAnonymous: (v) => _setAnonymousMode(v),
      onNext: _next,
    ),
    _ => _Welcome(onComplete: () => _completeOnboarding()),
  };

  String _t(String en, String ar) => _arabic ? ar : en;

  /// Matches the order of [_madhhabOrder] above.
  List<String> get _madhhabChoices => _arabic
      ? const ['حنفي', 'مالكي', 'شافعي', 'حنبلي']
      : const ['Hanafi', 'Maliki', "Shafi'i", 'Hanbali'];

  void _next() => setState(() => _step = (_step + 1).clamp(1, _totalSteps));

  /// Seeds a real cycle log from the last-period date/length answered in
  /// steps 6-7 (unless the user tapped "I'm not sure"), so onboarding's
  /// answer actually counts toward the app's cycle history instead of being
  /// silently discarded. This screen is only ever reached already
  /// authenticated (main.dart's root router requires it), so a real user id
  /// is always available.
  Future<void> _completeOnboarding() async {
    final periodDate = _periodDate;
    if (periodDate != null) {
      final userId =
          NiswahSupabase.clientOrNull?.auth.currentUser?.id ?? 'local-user';
      final days = _haidLength.round().clamp(1, 15);
      final repository = CycleTrackingRepositoryImpl();
      for (var i = 0; i < days; i++) {
        final data = CycleLogFormData(
          date: periodDate.add(Duration(days: i)),
          flow: i == days - 1 ? FlowLevel.light : FlowLevel.medium,
          cycleDay: i + 1,
        );
        await repository.saveCycleLog(data.toCycleLog(userId: userId));
      }
    }

    // AUTH-002: the durable, server-side completion flag — the ONLY
    // signal the root router trusts to decide onboarding is done. Written
    // here, and only here, at the real end of the flow. Best-effort: a
    // network failure must not trap the user on the Welcome screen (she
    // already answered every question), but it does mean she could see
    // onboarding again next launch if this specific write fails — an
    // honest, narrow, already-logged-out-loud tradeoff, not a silent one.
    try {
      await AuthRepositoryImpl().markOnboardingCompleted();
    } catch (_) {
      // Swallowed deliberately — see comment above. The local optimistic
      // update below still lets her proceed to the dashboard this session.
    }
    AuthController.instance.setOnboardingCompletedLocally(true);

    widget.onFinished();
  }

  Future<void> _useDeviceLocation() async {
    try {
      await PrayerLocationController.instance.useDeviceLocation();
      if (mounted) _next();
    } on LocationServiceDisabled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Turn on location services to use your current location.',
                'فعّلي خدمة الموقع لاستخدام موقعكِ الحالي.',
              ),
            ),
          ),
        );
      }
    } on LocationPermissionDenied {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Location permission denied — pick a city instead.',
                'تم رفض إذن الموقع، يمكنكِ اختيار مدينة بدلاً من ذلك.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Unable to get your location right now.',
                'تعذر تحديد موقعكِ الآن.',
              ),
            ),
          ),
        );
      }
    }
  }

  /// Best-effort: onboarding doesn't block progress on this write — the
  /// Settings toggle (profile_screen.dart) offers a retry path if it fails.
  Future<void> _setAnonymousMode(bool value) async {
    setState(() => _anonymous = value);
    try {
      final repository = AuthRepositoryImpl();
      final currentUser = await repository.currentUser;
      if (currentUser == null) return;
      await repository.updateProfile(
        displayName: currentUser.displayName ?? '',
        email: currentUser.email,
        anonymousMode: value,
      );
    } catch (_) {
      // Swallowed — see doc comment above.
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.onNext});
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Niswah',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: 48,
          color: const Color(0xFF9F1239),
          fontFamily: AppTypography.serifFamily,
        ),
      ),
      const SizedBox(height: 13),
      Text(
        _tr('YOUR CYCLE. YOUR FAITH. YOUR SPACE.', 'دورتكِ. دينكِ. مساحتكِ.'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: const Color(0xFFFB7185),
          fontSize: 10,
          letterSpacing: 2.1,
          fontWeight: FontWeight.w700,
          fontFamily: AppLocaleController.instance.isArabic
              ? AppTypography.arabicFamily
              : null,
        ),
      ),
      const SizedBox(height: 42),
      FilledButton(
        onPressed: onNext,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE11D48),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
          shape: const StadiumBorder(),
        ),
        child: Text(_tr('Get Started', 'ابدئي')),
      ),
    ],
  );
}



class _Language extends StatelessWidget {
  const _Language({
    required this.arabic,
    required this.onSelect,
    required this.onNext,
  });
  final bool arabic;
  final ValueChanged<bool> onSelect;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Choose your language', 'اختاري لغتكِ')),
      const SizedBox(height: 30),
      Row(
        children: [
          Expanded(
            child: _SelectCard(
              title: 'العربية',
              subtitle: 'Arabic',
              selected: arabic,
              onTap: () => onSelect(true),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _SelectCard(
              title: 'English',
              subtitle: 'English',
              selected: !arabic,
              onTap: () => onSelect(false),
            ),
          ),
        ],
      ),
      const SizedBox(height: 28),
      _Continue(onPressed: onNext),
    ],
  );
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.title,
    required this.subtitle,
    required this.choices,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    this.rules,
  });
  final String title, subtitle;
  final List<String> choices;
  final Set<String> selected;
  final List<String>? rules;
  final ValueChanged<String> onToggle;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(title),
      const SizedBox(height: 8),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 28),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: choices.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
        ),
        itemBuilder: (_, i) => _SelectCard(
          title: choices[i],
          subtitle: rules?[i] ?? '',
          selected: selected.contains(choices[i]),
          onTap: () => onToggle(choices[i]),
        ),
      ),
      const SizedBox(height: 28),
      _Continue(onPressed: onNext),
    ],
  );
}

class _Location extends StatelessWidget {
  const _Location({
    required this.onSelected,
    required this.onUseCurrentLocation,
    required this.onNext,
  });
  final ValueChanged<PrayerLocation> onSelected;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Where are you located?', 'أين تسكنين؟')),
      const SizedBox(height: 8),
      Text(
        _tr(
          'Used only to calculate accurate prayer times.',
          'نستخدم موقعكِ فقط لحساب مواقيت الصلاة بدقة.',
        ),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 26),
      FilledButton.icon(
        onPressed: onUseCurrentLocation,
        icon: const Icon(Icons.navigation_rounded),
        label: Text(_tr('Use current location', 'استخدام موقعي الحالي')),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: const Color(0xFFFFF1F2),
          foregroundColor: AppColors.haid,
        ),
      ),
      const SizedBox(height: 22),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          _tr('POPULAR CITIES', 'مدن شائعة'),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 9,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in PrayerLocationController.presets)
            ActionChip(
              label: Text(
                prayerLocationLabel(
                  preset,
                  isArabic: AppLocaleController.instance.isArabic,
                ),
              ),
              onPressed: () {
                onSelected(preset);
                onNext();
              },
            ),
        ],
      ),
      const SizedBox(height: 22),
      TextButton(
        onPressed: onNext,
        child: Text(_tr('Skip for now', 'تخطي الآن')),
      ),
    ],
  );
}

class _LastPeriod extends StatelessWidget {
  const _LastPeriod({
    required this.selected,
    required this.onSelect,
    required this.onNext,
    required this.onUnsure,
  });
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback? onNext;
  final VoidCallback onUnsure;
  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      31,
      (i) => DateTime.now().subtract(Duration(days: 30 - i)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Title(
          _tr('When did your last period start?', 'متى بدأ آخر حيض لديكِ؟'),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: AppColors.shadowColor, blurRadius: 20),
            ],
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemBuilder: (_, i) {
              final day = days[i];
              final active =
                  selected != null && DateUtils.isSameDay(selected, day);
              return InkWell(
                onTap: () => onSelect(day),
                customBorder: const CircleBorder(),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? const Color(0xFFFDA4AF)
                        : Colors.transparent,
                    border: DateUtils.isSameDay(day, DateTime.now())
                        ? Border.all(color: const Color(0xFFFB7185))
                        : null,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        _Continue(onPressed: onNext),
        TextButton(
          onPressed: onUnsure,
          child: Text(_tr('I’m not sure', 'لست متأكدة')),
        ),
      ],
    );
  }
}

class _NumberStep extends StatelessWidget {
  const _NumberStep({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onNext,
  });
  final String title, description;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(title),
      const SizedBox(height: 8),
      Text(
        description,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 45),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${value.round()}',
              style: const TextStyle(
                fontSize: 68,
                color: Color(0xFFFB7185),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: _tr(' days', ' أيام'),
              style: TextStyle(fontSize: 20, color: const Color(0x66BE123C)),
            ),
          ],
        ),
        style: TextStyle(fontFamily: AppTypography.serifFamily),
      ),
      const SizedBox(height: 24),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: (max - min).round(),
        activeColor: const Color(0xFFFB7185),
        inactiveColor: const Color(0xFFFFF1F2),
        onChanged: onChanged,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text('${min.round()}'), Text('${max.round()}')],
      ),
      const SizedBox(height: 36),
      _Continue(onPressed: onNext),
    ],
  );
}

class _Privacy extends StatelessWidget {
  const _Privacy({
    required this.anonymous,
    required this.onAnonymous,
    required this.onNext,
  });
  final bool anonymous;
  final ValueChanged<bool> onAnonymous;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Title(_tr('Anonymous Mode', 'الوضع المجهول')),
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF881337),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            // A Material ancestor is needed here — without it, this
            // SwitchListTile paints its ink splashes against the colored
            // Container above instead of onto its own layer, which Flutter
            // flags as invisible-ink and refuses to render on interaction.
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: anonymous,
                onChanged: onAnonymous,
                activeTrackColor: const Color(0xFFFDA4AF),
                title: Text(
                  _tr('Hide my identity', 'إخفاء هويتي'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                secondary: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFDA4AF),
                ),
              ),
            ),
            Text(
              _tr(
                'Hide identifying details throughout the community while keeping your health data private.',
                'أخفي بياناتكِ التعريفية في المجتمع مع الحفاظ على خصوصية بياناتكِ الصحية.',
              ),
              style: const TextStyle(
                color: Color(0xAAFFF1F2),
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _Continue(onPressed: onNext),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onComplete});
  final VoidCallback onComplete;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF1F2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: Color(0xFFFB7185),
          size: 38,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        _tr('You’re all set!', 'كل شيء جاهز!'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
          color: const Color(0xFF881337),
          fontFamily: AppTypography.serifFamily,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _tr(
          'Your personalized cycle, Fiqh, wellbeing, and privacy experience is ready.',
          'تجربتكِ المخصصة للدورة والفقه والرفاه والخصوصية جاهزة.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFFFE4E6)),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 16,
          children: [
            _Feature(Icons.auto_awesome_rounded, _tr('Niswah AI', 'نسوة AI')),
            _Feature(Icons.insights_rounded, _tr('Insights', 'الرؤى')),
            _Feature(Icons.menu_book_rounded, _tr('Journeys', 'الرحلات')),
            _Feature(Icons.shield_outlined, _tr('Privacy', 'الخصوصية')),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _Continue(
        label: _tr('Get Started', 'ابدئي'),
        onPressed: onComplete,
        strong: true,
      ),
    ],
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.displayMedium?.copyWith(
      fontFamily: AppTypography.serifFamily,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF4B3430),
    ),
  );
}

class _Continue extends StatelessWidget {
  const _Continue({
    required this.onPressed,
    this.label = 'Continue',
    this.strong = false,
  });
  final VoidCallback? onPressed;
  final String label;
  final bool strong;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      backgroundColor: strong
          ? const Color(0xFFE11D48)
          : const Color(0xFFFB7185),
      disabledBackgroundColor: const Color(0xFFF3F4F6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    child: Text(
      label == 'Continue' ? _tr('Continue', 'متابعة') : label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? const Color(0xFFFDA4AF) : AppColors.shadowColor,
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          // FittedBox(scaleDown) matches the same fixed-dimension/large-
          // text-scale treatment already applied to the dashboard (AU-006)
          // — this grid cell has a fixed aspect ratio, so title+subtitle
          // text would otherwise overflow it at large OS text-scale
          // settings instead of shrinking to fit.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF881337)
                        : AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 8,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (selected)
            const PositionedDirectional(
              top: 0,
              end: 0,
              child: Icon(
                Icons.check_rounded,
                color: Color(0xFFFB7185),
                size: 17,
              ),
            ),
        ],
      ),
    ),
  );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 125,
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFFB7185), size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF881337),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

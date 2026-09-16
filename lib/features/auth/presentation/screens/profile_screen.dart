import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/marital_status_controller.dart';
import '../../../../core/preferences/pregnancy_status_controller.dart';
import '../../../../core/preferences/ttc_mode_controller.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../../core/preferences/prayer_location_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_theme_controller.dart';
import '../../../../core/widgets/niswah_loading_indicator.dart';
import '../../../legal/presentation/screens/data_export_screen.dart';
import '../../../madhhab_resolution/presentation/madhhab_resolution_screen.dart';
import '../../../legal/presentation/screens/privacy_policy_screen.dart';
import 'sign_in_screen.dart';
import '../../../private_messaging/presentation/screens/conversations_screen.dart';
import '../../../private_messaging/domain/repositories/private_messaging_repository_base.dart';
import '../../../private_messaging/presentation/viewmodels/conversations_view_model.dart';
import '../../../private_messaging/presentation/widgets/unread_messages_badge.dart';
import '../../../private_messaging/private_messaging_locator.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import '../../../doctor_report/presentation/screens/doctor_report_screen.dart';
import '../../../fiqh_report/presentation/screens/fiqh_report_screen.dart';
import '../../../husband_report/presentation/screens/husband_report_screen.dart';
import '../../../notifications/presentation/screens/notification_settings_screen.dart';
import '../../../pregnancy_profile/data/repositories/pregnancy_profile_repository.dart';
import '../../../pregnancy_profile/domain/entities/pregnancy_profile.dart';
import '../../../pregnancy_profile/domain/services/pregnancy_status_engine.dart';
import '../../../wellbeing/presentation/screens/wellbeing_report_screen.dart';
import '../viewmodels/profile_view_model.dart';

String _pr(String en, String ar) => AppLocaleController.instance.text(en, ar);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileViewModel _viewModel;
  String _language = AppLocaleController.instance.isArabic ? 'AR' : 'EN';
  int _badgeRefresh = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileViewModel()..loadCurrentUser();
    PregnancyStatusController.instance.load();
    TtcModeController.instance.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      _viewModel,
      MaritalStatusController.instance,
      MadhhabController.instance,
      PrayerLocationController.instance,
      PregnancyStatusController.instance,
      TtcModeController.instance,
      AppThemeController.instance,
    ]),
    builder: (context, _) {
      final user = _viewModel.user;
      final isAnonymous = user?.isAnonymous ?? false;
      final name = isAnonymous
          ? _pr('Anonymous sister', 'أخت مجهولة')
          : (user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!
                : _pr('Sister', 'أختي'));
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: Directionality(
            textDirection: AppLocaleController.instance.isArabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    child: Text(
                      _pr('Profile', 'الملف الشخصي'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            color: const Color(0xFF8E244D),
                            fontFamily: AppTypography.serifFamily,
                          ),
                    ),
                  ),
                ),
                if (_viewModel.isLoading)
                  SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.brandSecondary,
                      backgroundColor: Colors.transparent,
                      semanticsLabel: _pr(
                        'Loading profile',
                        'جارٍ تحميل الملف الشخصي',
                      ),
                    ),
                  ),
                if (_viewModel.errorMessage != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    sliver: SliverToBoxAdapter(
                      child: _ProfileLoadError(
                        onRetry: _viewModel.loadCurrentUser,
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 132),
                  sliver: SliverList.list(
                    children: [
                      _IdentityCard(name: name, isAnonymous: isAnonymous),
                      const SizedBox(height: 24),
                      // Community actions are surfaced at the top so new
                      // messages and invitations are immediately visible.
                      _SectionTitle(_pr('Community', 'المجتمع')),
                      const SizedBox(height: 10),
                      _SettingsGroup(
                        children: [
                          _ActionRow(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: _pr('Messages', 'الرسائل'),
                            onTap: _openPrivateMessages,
                            trailing: UnreadMessagesBadge(
                              key: ValueKey(_badgeRefresh),
                              repository: _messagingRepository,
                            ),
                          ),
                          _ActionRow(
                            icon: Icons.share_outlined,
                            title: _pr('Invite a Friend', 'دعوة صديقة'),
                            onTap: () async {
                              await Clipboard.setData(
                                const ClipboardData(
                                  text: 'Niswah — cycle tracking with care and clarity.',
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _pr(
                                        'Invitation copied',
                                        'تم نسخ نص الدعوة',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(
                        _pr('Prayer Times Settings', 'إعدادات مواقيت الصلاة'),
                      ),
                      const SizedBox(height: 10),
                      _LocationCard(
                        city: prayerLocationLabel(
                          PrayerLocationController.instance.resolved,
                          isArabic: AppLocaleController.instance.isArabic,
                        ),
                        onChange: _showCitySheet,
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(_pr('Health Profile', 'الملف الصحي')),
                      const SizedBox(height: 10),
                      _SettingsGroup(
                        children: [
                          _ToggleRow(
                            icon: Icons.people_outline_rounded,
                            title: _pr('I am married', 'أنا متزوجة'),
                            subtitle: _pr(
                              'Shows pregnancy tools and the husband report',
                              'يُظهر أدوات الحمل وتقرير الزوج',
                            ),
                            value: MaritalStatusController.instance.isMarried,
                            onChanged:
                                MaritalStatusController.instance.setMarried,
                          ),
                          _ToggleRow(
                            icon: Icons.pregnant_woman_rounded,
                            title: _pr(
                              'I am currently pregnant',
                              'أنا حامل حالياً',
                            ),
                            subtitle: _pr(
                              'Opens pregnancy setup, dashboard, and report',
                              'يفتح إعداد أسبوع الحمل ثم يعرض لوحة الحمل والتقرير',
                            ),
                            value:
                                PregnancyStatusController.instance.isPregnant,
                            onChanged: (value) => value
                                ? _showPregnancySetupSheet()
                                : PregnancyStatusController.instance
                                      .deactivate(),
                          ),
                          _ToggleRow(
                            icon: Icons.child_friendly_outlined,
                            title: _pr(
                              'Postpartum Mode (Nifas)',
                              'وضع ما بعد الولادة (النفاس)',
                            ),
                            subtitle: _pr(
                              'Starts nifas from today and adjusts prayer/fasting status',
                              'عند تفعيله يبدأ النفاس من اليوم، وتُعلّق الصلاة والصوم حسب الحالة',
                            ),
                            value: PregnancyStatusController
                                .instance
                                .isNifasActive,
                            onChanged: (value) => value
                                ? _startNifas()
                                : PregnancyStatusController.instance
                                      .deactivate(),
                          ),
                          _ToggleRow(
                            icon: Icons.favorite_border_rounded,
                            title: _pr('TTC Mode', 'وضع التخطيط للحمل (TTC)'),
                            subtitle: _pr(
                              'Shows the privacy window and pregnancy chance in Calendar and improves the husband report',
                              'يظهر نافذة الخصوصية وفرصة الحمل في التقويم ويحسّن تقرير الزوج',
                            ),
                            value: TtcModeController.instance.enabled,
                            onChanged: TtcModeController.instance.setEnabled,
                            last: true,
                          ),
                        ],
                      ),
                      if (PregnancyStatusController.instance.isPregnant) ...[
                        const SizedBox(height: 12),
                        _PregnancyActiveBanner(
                          week: PregnancyStatusController.instance.currentWeek,
                        ),
                      ],
                      if (TtcModeController.instance.enabled) ...[
                        const SizedBox(height: 12),
                        const _TtcActiveBanner(),
                      ],
                      const SizedBox(height: 30),
                      _SectionTitle(_pr('Fiqh Madhhab', 'المذهب الفقهي')),
                      const SizedBox(height: 10),
                      // Madhhab Resolution Gate wave (2026-09-16), Section
                      // 16: "غير محدد حالياً" must be permanently exposed
                      // while not yet SELECTED, with a guided-help action
                      // reusing the SAME canonical resolver as the
                      // Log-my-Haidh gate. The existing direct-edit grid
                      // below (unchanged — already lets her pick any school,
                      // including its own "I don't know" option, and change
                      // her mind freely between them, per the pre-existing,
                      // already-tested Fiqh Remediation Wave 1 semantics)
                      // stays always visible and is not replaced by this
                      // wave — this block only adds the missing guided path
                      // alongside it, never a second, separate decision
                      // mechanism.
                      if (!MadhhabController.instance.isSelected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MadhhabUnresolvedBanner(
                            onHelpMeChoose: () => showMadhhabResolutionFlow(
                              context,
                              entryContext: MadhhabResolutionContext.settings,
                              start: MadhhabResolutionStart.guided,
                            ),
                          ),
                        ),
                      _MadhhabGrid(
                        // Fiqh Remediation Wave 1 (Section K): reflects
                        // the real three-state model — 'unknown' when the
                        // user explicitly said so, nothing highlighted
                        // when UNSET, never a guessed madhhab.
                        selected:
                            MadhhabController.instance.state ==
                                MadhhabSelectionState.unknown
                            ? 'unknown'
                            : (MadhhabController
                                      .instance
                                      .selectedOrNull
                                      ?.name ??
                                  ''),
                        onSelected: (value) => value == 'unknown'
                            ? MadhhabController.instance.selectUnknown()
                            : MadhhabController.instance.selectMadhhab(
                                Madhhab.values.byName(value.toLowerCase()),
                              ),
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(
                        _pr('Privacy Settings', 'إعدادات الخصوصية'),
                      ),
                      const SizedBox(height: 10),
                      _SettingsGroup(
                        children: [
                          _ToggleRow(
                            icon: Icons.visibility_off_outlined,
                            title: _pr('Anonymous Mode', 'الوضع المجهول'),
                            value: isAnonymous,
                            onChanged: _viewModel.isSaving
                                ? null
                                : (value) async {
                                    try {
                                      await _viewModel.setAnonymousMode(value);
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(error.toString()),
                                              ),
                                            );
                                      }
                                    }
                                  },
                          ),
                          _ActionRow(
                            icon: Icons.privacy_tip_outlined,
                            title: _pr('Privacy Policy', 'سياسة الخصوصية'),
                            onTap: () => _open(const PrivacyPolicyScreen()),
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(_pr('Notifications', 'التنبيهات')),
                      const SizedBox(height: 10),
                      _SettingsGroup(
                        children: [
                          _ActionRow(
                            icon: Icons.notifications_outlined,
                            title: _pr(
                              'Notification settings',
                              'إعدادات التنبيهات',
                            ),
                            onTap: () =>
                                _open(const NotificationSettingsScreen()),
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(_pr('Data Export', 'تصدير البيانات')),
                      const SizedBox(height: 10),
                      _SettingsGroup(
                        children: [
                          _ExportRow(
                            icon: Icons.download_outlined,
                            title: _pr('Export Fiqh Log', 'تصدير سجل فقهي'),
                            onTap: () => _open(const FiqhReportScreen()),
                          ),
                          _ExportRow(
                            icon: Icons.download_outlined,
                            title: _pr(
                              "Export Doctor's Report",
                              'تصدير تقرير للطبيبة',
                            ),
                            onTap: () => _open(const DoctorReportScreen()),
                          ),
                          _ExportRow(
                            icon: Icons.favorite_border_rounded,
                            title: _pr(
                              'Mental state report',
                              'تقرير الحالة النفسية',
                            ),
                            onTap: () => _open(const WellbeingReportScreen()),
                          ),
                          if (MaritalStatusController.instance.isMarried)
                            _ExportRow(
                              icon: Icons.download_outlined,
                              title: _pr('Husband Report', 'تقرير الزوج'),
                              onTap: () =>
                                  _open(HusbandReportScreen(displayName: name)),
                            ),
                          _ExportRow(
                            icon: Icons.data_object_rounded,
                            title: _pr(
                              'Export My Data (JSON)',
                              'تصدير بياناتي (JSON)',
                            ),
                            onTap: () => _open(const DataExportScreen()),
                            last: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(_pr('Appearance', 'المظهر')),
                      const SizedBox(height: 10),
                      _ThemeModeRow(
                        value: AppThemeController.instance.themeMode,
                        onChanged: AppThemeController.instance.setThemeMode,
                      ),
                      const SizedBox(height: 30),
                      _SectionTitle(_pr('Language', 'اللغة')),
                      const SizedBox(height: 10),
                      _LanguageRow(
                        value: _language,
                        onChanged: (value) {
                          setState(() => _language = value);
                          AppLocaleController.instance.setArabic(value == 'AR');
                        },
                      ),
                      const SizedBox(height: 36),

                      FilledButton(
                        onPressed: _viewModel.isSaving ? null : _signOut,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: const Color(0xFFF43F5E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _pr('Sign Out', 'تسجيل الخروج'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: (_viewModel.isSaving || _isDeletingAccount)
                            ? null
                            : _confirmAndDeleteAccount,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          foregroundColor: const Color(0xFF991B1B),
                          side: const BorderSide(color: Color(0xFF991B1B)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isDeletingAccount
                            ? NiswahLoadingIndicator(
                                size: NiswahLoadingSize.small,
                                color: const Color(0xFF991B1B),
                                semanticsLabel: _pr(
                                  'Deleting account',
                                  'جارٍ حذف الحساب',
                                ),
                              )
                            : Text(
                                _pr('Delete Account', 'حذف الحساب'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(height: 18),
                      const Center(
                        child: Text(
                          'Niswah v1.0.0',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 9,
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
    },
  );

  // AUTH-008: this used to manually push OnboardingScreen (via its old,
  // now-removed embedded login step) as an ad hoc way to let the user sign
  // back in — exactly the "hard-code a login step to cover session loss"
  // anti-pattern the root auth guard exists to prevent. `_viewModel
  // .signOut()` performs a real Supabase sign-out, which AuthController's
  // own `onAuthStateChange` listener already reacts to (`isAuthenticated`
  // flips false, `notifyListeners()` fires) — main.dart's root router
  // reactively shows SignInScreen on its own; no manual navigation here
  // is needed, or correct, for this same reason.
  Future<void> _signOut() async {
    try {
      await _viewModel.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  bool _isDeletingAccount = false;

  /// PC-002: wires the existing `delete_my_account()` RPC into the client
  /// for the first time. Requires an explicit, destructive-action
  /// confirmation dialog before doing anything irreversible — no
  /// accidental one-tap deletion.
  Future<void> _confirmAndDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_pr('Delete your account?', 'حذف حسابكِ؟')),
        content: Text(
          _pr(
            'This permanently deletes your account and all associated '
                'data — cycle logs, pregnancy data, chat history, and '
                'community posts. This cannot be undone.',
            'سيؤدي هذا إلى حذف حسابكِ وجميع البيانات المرتبطة به نهائياً '
                '— سجلات الدورة، بيانات الحمل، سجل المحادثات، ومنشورات '
                'المجتمع. لا يمكن التراجع عن هذا الإجراء.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_pr('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF991B1B),
            ),
            child: Text(_pr('Delete', 'حذف')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await _viewModel.deleteAccount();
      if (mounted) {
        // The session is already cleared by this point (AuthRepositoryImpl
        // signs out locally after the RPC succeeds) — this navigates to
        // the same unauthenticated entry point sign-out uses, rather than
        // claiming success without confirming the app actually reflects
        // it (no false success).
        await Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute(builder: (_) => const SignInScreen()),
          (route) => false,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _pr(
                "Couldn't delete your account. Please try again.",
                'تعذّر حذف حسابكِ. يُرجى المحاولة مرة أخرى.',
              ),
            ),
          ),
        );
      }
    }
  }

  void _open(Widget screen) => Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen),
  );

  /// Resolves the messaging repository — always the real, Supabase-backed
  /// one. **No demo-mode/mock fallback here** (PJ-005/CQ-007): this
  /// screen is only reachable from inside `NiswahHomeShell`, which the
  /// root router (`main.dart`) already gates behind
  /// `AuthController.isAuthenticated` — a genuinely unauthenticated user
  /// is shown `SignInScreen` before ever reaching this screen at all. A
  /// null user id here can therefore only mean a session that was valid a
  /// moment ago has since died — not a deliberate "browse without an
  /// account" state. Silently substituting fabricated named-contact
  /// conversations in that case previously gave no indication anything
  /// was wrong; `_openPrivateMessages` now checks for this explicitly and
  /// shows an honest prompt instead of ever calling this getter with no
  /// session.
  PrivateMessagingRepositoryBase get _messagingRepository =>
      privateMessagingRepository;

  void _openPrivateMessages() {
    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pr(
              'Your session has ended. Please sign in again to use messaging.',
              'انتهت جلستكِ. يُرجى تسجيل الدخول مرة أخرى لاستخدام الرسائل.',
            ),
          ),
        ),
      );
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ConversationsScreen(
              viewModel: ConversationsViewModel(
                repository: _messagingRepository,
                currentUserId: userId,
              ),
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _badgeRefresh++);
        });
    // Rebuild on return so the unread badge refreshes.
  }

  /// Starts nifas locally (existing behavior, drives the dashboard's nifas
  /// card) and — when a real user is signed in — additively upserts
  /// `pregnancy_profile.is_postpartum`/`postpartum_start_date` so the
  /// "طبيبة" chat backend picks up the mode switch too. The local toggle
  /// stays authoritative on a sync failure (reverting it would be a worse
  /// UX regression than an unpersonalized chat) but the failure is reported
  /// and surfaced — not silently discarded (RR-003).
  Future<void> _startNifas() async {
    await PregnancyStatusController.instance.startNifas();

    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await PregnancyProfileRepository().markPostpartumStarted(userId);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'ProfileScreen._startNifas',
        feature: 'pregnancy_profile',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pr(
              "Nifas tracking has started on this device, but couldn't sync to your account — the chat may not be personalized yet.",
              'بدأ تتبع النفاس على هذا الجهاز، لكن تعذّرت المزامنة مع حسابك — قد لا تكون المحادثة مخصّصة بعد.',
            ),
          ),
        ),
      );
    }
  }

  /// Mirrors the web app flow: toggling "I am currently pregnant" ON opens
  /// a pregnancy setup sheet asking for the current week (1–40) before
  /// activating tracking.
  Future<void> _showPregnancySetupSheet() async {
    final activated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => const _PregnancySetupSheet(),
    );
    if (activated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pr('Pregnancy tracking is active', 'تم تفعيل تتبع الحمل'),
          ),
        ),
      );
    }
  }

  void _showCitySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.brandBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _pr('Choose your city', 'اختاري مدينتكِ'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF881337),
                fontFamily: AppTypography.serifFamily,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(height: 8),
            for (final preset in PrayerLocationController.presets)
              ListTile(
                leading: Icon(
                  preset == PrayerLocationController.instance.selectedOrNull
                      ? Icons.check_circle_rounded
                      : Icons.location_on_outlined,
                  color:
                      preset == PrayerLocationController.instance.selectedOrNull
                      ? AppColors.success
                      : AppColors.textTertiary,
                ),
                title: Text(
                  prayerLocationLabel(
                    preset,
                    isArabic: AppLocaleController.instance.isArabic,
                  ),
                ),
                onTap: () {
                  PrayerLocationController.instance.select(preset);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet replicating the web app's "إعداد تتبع الحمل" setup:
/// week stepper (1–40), quick-select chips (4/8/12/20/32), info cards,
/// activate and cancel buttons.
class _PregnancySetupSheet extends StatefulWidget {
  const _PregnancySetupSheet();

  @override
  State<_PregnancySetupSheet> createState() => _PregnancySetupSheetState();
}

class _PregnancySetupSheetState extends State<_PregnancySetupSheet> {
  int _week = 1;
  FastingStatus _fastingStatus = FastingStatus.notApplicable;
  final List<String> _highRiskFlags = [];
  final _highRiskFlagController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  static const _quickWeeks = [4, 8, 12, 20, 32];

  @override
  void dispose() {
    _highRiskFlagController.dispose();
    super.dispose();
  }

  void _addHighRiskFlag() {
    final text = _highRiskFlagController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _highRiskFlags.add(text);
      _highRiskFlagController.clear();
    });
  }

  Future<void> _activate() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final now = DateTime.now();
    final draftProfile = PregnancyProfile(
      id: '',
      userId: '',
      trackingBasis: TrackingBasis.manualWeek,
      manualWeekValue: _week,
      manualWeekSetAt: now,
      highRiskFlags: _highRiskFlags,
      fastingStatus: _fastingStatus,
    );

    // Keeps the local, device-only controller (used by the dashboard's
    // pregnancy overview) accurate regardless of which tracking basis was
    // chosen here.
    final effectiveWeek =
        PregnancyStatusEngine.getStatus(draftProfile, now).week ?? _week;
    await PregnancyStatusController.instance.activate(startWeek: effectiveWeek);

    final userId = NiswahSupabase.clientOrNull?.auth.currentUser?.id;
    if (userId != null) {
      try {
        await PregnancyProfileRepository().upsert(
          PregnancyProfile(
            id: '',
            userId: userId,
            trackingBasis: draftProfile.trackingBasis,
            referenceDate: draftProfile.referenceDate,
            manualWeekValue: draftProfile.manualWeekValue,
            manualWeekSetAt: draftProfile.manualWeekSetAt,
            highRiskFlags: draftProfile.highRiskFlags,
            fastingStatus: draftProfile.fastingStatus,
          ),
        );
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'ProfileScreen._showPregnancySetupSheet',
          feature: 'pregnancy_profile',
        );
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = _pr(
            "Couldn't sync to your account — pregnancy tracking is on for this device, but the chat may not be personalized yet. Check your connection and try again.",
            'تعذّر المزامنة مع حسابك — تفعّل تتبع الحمل على هذا الجهاز، لكن قد لا تكون المحادثة مخصّصة بعد. تحققي من الاتصال وحاولي مرة أخرى.',
          );
        });
        return;
      }
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF1F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: AppColors.haid,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _pr('Pregnancy Setup', 'إعداد تتبع الحمل'),
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF881337),
                    fontFamily: AppTypography.serifFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _pr(
                    'Choose your current pregnancy week, and we will track your pregnancy automatically from day one.',
                    'اختاري أسبوع الحمل الحالي مرة واحدة، وسنتابع رحلة الحمل تلقائياً من يوم التفعيل.',
                  ),
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7F8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFFFE4E9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pr(
                                'Which pregnancy week are you in now?',
                                'في أي أسبوع أنتِ الآن؟',
                              ),
                              textAlign: isArabic
                                  ? TextAlign.right
                                  : TextAlign.left,
                              style: const TextStyle(
                                color: Color(0xFF881337),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: _pr(
                                    'Increase week',
                                    'زيادة الأسبوع',
                                  ),
                                  onPressed: _week < 40
                                      ? () => setState(() => _week++)
                                      : null,
                                  icon: const Icon(
                                    Icons.add_rounded,
                                    color: AppColors.haid,
                                    size: 20,
                                  ),
                                ),
                                Text(
                                  '$_week',
                                  style: const TextStyle(
                                    color: AppColors.haid,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: _pr(
                                    'Decrease week',
                                    'إنقاص الأسبوع',
                                  ),
                                  onPressed: _week > 1
                                      ? () => setState(() => _week--)
                                      : null,
                                  icon: const Icon(
                                    Icons.remove_rounded,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (final quickWeek in _quickWeeks) ...[
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _week = quickWeek),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _week == quickWeek
                                        ? const Color(0xFFFFF1F2)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _week == quickWeek
                                          ? const Color(0xFFFFCDD5)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _pr('Week $quickWeek', 'أسبوع $quickWeek'),
                                    style: TextStyle(
                                      color: _week == quickWeek
                                          ? AppColors.haid
                                          : AppColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (quickWeek != _quickWeeks.last)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _PregnancyInfoCard(
                              icon: Icons.calendar_month_outlined,
                              iconColor: AppColors.success,
                              text: _pr(
                                'We will start counting pregnancy from the chosen week, then adjust automatically after each update.',
                                'سنعتبر بداية الحمل من الأسبوع المختار، ثم نحسب الأسبوع تلقائياً بعد كل تحديث.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PregnancyInfoCard(
                              icon: Icons.shield_outlined,
                              iconColor: const Color(0xFF4F46E5),
                              text: _pr(
                                'You can pause or stop pregnancy tracking at any time.',
                                'يمكنك إيقاف وضع الحمل لاحقاً من اللوك الشخصي في أي وقت.',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _pr('Fasting status', 'حالة الصيام'),
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xFF881337),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final status in FastingStatus.values)
                      InkWell(
                        onTap: () => setState(() => _fastingStatus = status),
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _fastingStatus == status
                                ? const Color(0xFFFFF1F2)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: _fastingStatus == status
                                  ? const Color(0xFFFFCDD5)
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Text(
                            switch (status) {
                              FastingStatus.notApplicable => _pr(
                                'Not applicable',
                                'لا ينطبق',
                              ),
                              FastingStatus.fasting => _pr('Fasting', 'صائمة'),
                              FastingStatus.notFasting => _pr(
                                'Not fasting',
                                'غير صائمة',
                              ),
                              FastingStatus.unsure => _pr(
                                'Not sure',
                                'غير متأكدة',
                              ),
                            },
                            style: TextStyle(
                              color: _fastingStatus == status
                                  ? AppColors.haid
                                  : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _pr(
                    'Anything your doctor should keep in mind? (optional)',
                    'هل هناك ما يجب أن يعرفه طبيبك؟ (اختياري)',
                  ),
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xFF881337),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('pregnancy-setup-risk-flag-input'),
                        controller: _highRiskFlagController,
                        onSubmitted: (_) => _addHighRiskFlag(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _pr(
                            'e.g. gestational diabetes, twins',
                            'مثال: سكري الحمل، توأم',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('pregnancy-setup-risk-flag-add'),
                      tooltip: _pr('Add', 'إضافة'),
                      onPressed: _addHighRiskFlag,
                      icon: const Icon(Icons.add_circle, color: AppColors.haid),
                    ),
                  ],
                ),
                if (_highRiskFlags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final flag in _highRiskFlags)
                        Chip(
                          label: Text(
                            flag,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onDeleted: () =>
                              setState(() => _highRiskFlags.remove(flag)),
                        ),
                    ],
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCDD5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF9F1239),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                NiswahLoadingButton(
                  key: const Key('pregnancy-setup-activate'),
                  loading: _isSaving,
                  onPressed: _activate,
                  label: _pr('Activate Pregnancy Tracking', 'تفعيل تتبع الحمل'),
                  loadingSemanticsLabel: _pr('Saving', 'جارٍ الحفظ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.haid,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  key: const Key('pregnancy-setup-cancel'),
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    _pr('Cancel', 'إلغاء'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PregnancyInfoCard extends StatelessWidget {
  const _PregnancyInfoCard({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF3F4F6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

/// Green confirmation banner shown under the Health Profile group once
/// pregnancy tracking is active — matching the web app's Today/profile state.
class _PregnancyActiveBanner extends StatelessWidget {
  const _PregnancyActiveBanner({required this.week});

  final int week;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD1FAE5)),
    ),
    child: Text(
      _pr(
        'Pregnancy tracking is active (week $week). Planning for birth and nifas — after logging the birth, nifas mode starts automatically.',
        'تتبع الحمل نشط (الأسبوع $week). وضع التخطيط للحمل والنفاس مُفعّل، وبعد تسجيل الولادة يبدأ وضع النفاس تلقائياً.',
      ),
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Color(0xFF065F46),
        fontSize: 10.5,
        height: 1.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _TtcActiveBanner extends StatelessWidget {
  const _TtcActiveBanner();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFECDD3)),
    ),
    child: Text(
      _pr(
        'TTC Mode is active: open Calendar to see the privacy window and pregnancy chance',
        'وضع التخطيط نشط: افتحي التقويم لرؤية نافذة الخصوصية وفرصة الحمل',
      ),
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Color(0xFF9F1239),
        fontSize: 10.5,
        height: 1.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFCDD5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: AppColors.haid, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _pr('Profile could not be loaded.', 'تعذر تحميل الملف الشخصي.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9F1239)),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(_pr('Retry', 'إعادة'))),
      ],
    ),
  );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.name, required this.isAnonymous});
  final String name;
  final bool isAnonymous;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: _cardDecoration(context, 32),
    child: Row(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF1F2),
            shape: BoxShape.circle,
          ),
          child: Text(
            name.characters.first.toUpperCase(),
            style: TextStyle(
              color: AppColors.brandSecondary,
              fontFamily: AppTypography.serifFamily,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF881337),
                        fontFamily: AppTypography.serifFamily,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'PLUS',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                isAnonymous ? _pr('Guest', 'زائرة') : _pr('Member', 'عضوة'),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.city, required this.onChange});
  final String city;
  final VoidCallback onChange;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFD1FAE5)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.success,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                city,
                style: TextStyle(
                  color: AppColors.emeraldInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3),
              Text(
                _pr('City selected', 'تم تحديد المدينة'),
                style: TextStyle(color: AppColors.textTertiary, fontSize: 9),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onChange,
          child: Text(
            _pr('Change City', 'تغيير المدينة'),
            style: TextStyle(
              color: AppColors.brandSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Madhhab Resolution Gate wave (2026-09-16), Section 16: shown instead of
/// the direct-edit grid whenever the user has not yet reached
/// [MadhhabSelectionState.selected] (covers both UNSET and UNKNOWN — the
/// charter's own wording, "if UNKNOWN," is read as "not yet resolved,"
/// since UNSET is the same underlying "nothing to show her" situation).
/// Madhhab Resolution Gate wave (2026-09-16), Section 16: the "غير محدد
/// حالياً" status the charter requires be permanently exposed while not
/// SELECTED, plus one action into the guided resolver — shown *alongside*
/// the always-visible `_MadhhabGrid` below (which already lets her pick a
/// school, or "I don't know", directly), not instead of it. No "Choose
/// Madhhab" button here: the grid immediately below already is that
/// action, so a second copy of it would be a redundant, competing control
/// for the same choice.
class _MadhhabUnresolvedBanner extends StatelessWidget {
  const _MadhhabUnresolvedBanner({required this.onHelpMeChoose});
  final VoidCallback onHelpMeChoose;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.shadowColor),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _pr('Not yet determined', 'غير محدد حالياً'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: onHelpMeChoose,
          child: Text(_pr('Help me choose', 'ساعديني في الاختيار')),
        ),
      ],
    ),
  );
}

class _MadhhabGrid extends StatelessWidget {
  const _MadhhabGrid({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'hanafi',
        _pr('Hanafi', 'حنفي'),
        _pr(
          'Min Haid: 3 days, Max Haid: 10 days',
          'أقل الحيض 3 أيام، وأكثره 10 أيام',
        ),
      ),
      (
        'shafii',
        _pr("Shafi'i", 'شافعي'),
        _pr(
          'Min Haid: 24h, Max Haid: 15 days',
          'أقل الحيض يوم وليلة، وأكثره 15 يوماً',
        ),
      ),
      (
        'maliki',
        _pr('Maliki', 'مالكي'),
        _pr(
          'No Min Haid, Max Haid: 15 days',
          'لا حد لأقل الحيض، وأكثره 15 يوماً',
        ),
      ),
      (
        'hanbali',
        _pr('Hanbali', 'حنبلي'),
        _pr(
          'Min Haid: 24h, Max Haid: 15 days',
          'أقل الحيض يوم وليلة، وأكثره 15 يوماً',
        ),
      ),
      // Fiqh Remediation Wave 1 (Section K — change Madhhab): a durable,
      // first-class UNKNOWN state must remain reachable here too, not
      // only at onboarding — see MadhhabController.selectUnknown().
      ('unknown', _pr('I don\'t know', 'لا أعرف'), ''),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 122,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = values[index];
        final active = selected == item.$1;
        // Fiqh Remediation Wave 1 — Pre-E4 Verification (Section 2): same
        // fix as onboarding's _SelectCard — selection was previously
        // conveyed only visually. `excludeSemantics: true` stops the child
        // Text's own label from merging in and doubling the announcement.
        return Semantics(
          button: true,
          selected: active,
          label: item.$3.isEmpty ? item.$2 : '${item.$2}, ${item.$3}',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => onSelected(item.$1),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFFFF1F2) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: active
                      ? const Color(0xFFFFCDD5)
                      : AppColors.shadowColor,
                ),
              ),
              // Fiqh Remediation Wave 1 — Pre-E4 Verification (Section 1):
              // this tile is inside a fixed-height grid cell
              // (`mainAxisExtent: 122`) — a real overflow was found here at
              // 200% text scale (AU-006's own fix was never applied to this
              // grid). Restructured to match `_SelectCard`'s already-working
              // Stack + FittedBox(scaleDown) + PositionedDirectional icon
              // pattern, which is compatible with FittedBox's unbounded
              // child constraints (a `Row`+`Expanded` title/icon layout is
              // not — that combination is what overflowed).
              child: Stack(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.topStart,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          style: TextStyle(
                            color: active
                                ? const Color(0xFF881337)
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (item.$3.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.$3,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (active)
                    const PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Icon(
                        Icons.check_rounded,
                        color: AppColors.brandSecondary,
                        size: 17,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    decoration: _cardDecoration(context, 28),
    child: Column(children: children),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.last = false,
  });
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.shadowColor)),
    ),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.brandSecondary, size: 20),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF881337),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 8.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: const Color(0xFF4FC36B),
          activeThumbColor: Colors.white,
          inactiveTrackColor: const Color(0xFFE5E7EB),
          inactiveThumbColor: Colors.white,
        ),
      ],
    ),
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.last = false,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool last;

  /// Optional trailing widget (e.g. an unread-count badge).
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.shadowColor)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF881337), size: 20),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: const Color(0xFF881337),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.last = false,
  });
  final IconData icon;
  final String title;
  final bool last;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.shadowColor)),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.brandSecondary, size: 20),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF881337),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            _pr('Download', 'تحميل'),
            style: TextStyle(color: AppColors.brandSecondary, fontSize: 9),
          ),
        ),
      ],
    ),
  );
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final options = <(ThemeMode, IconData, String)>[
      (
        ThemeMode.system,
        Icons.brightness_auto_rounded,
        _pr('System', 'تلقائي'),
      ),
      (ThemeMode.light, Icons.light_mode_outlined, _pr('Light', 'فاتح')),
      (ThemeMode.dark, Icons.dark_mode_outlined, _pr('Dark', 'داكن')),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: options
            .map(
              (option) => Expanded(
                child: Semantics(
                  button: true,
                  selected: value == option.$1,
                  child: InkWell(
                    onTap: () => onChanged(option.$1),
                    borderRadius: BorderRadius.circular(15),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: value == option.$1
                            ? colors.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            option.$2,
                            size: 20,
                            color: value == option.$1
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            option.$3,
                            style: TextStyle(
                              color: value == option.$1
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(context, 24),
    child: Row(
      children: [
        const Icon(
          Icons.language_rounded,
          color: AppColors.brandSecondary,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _pr('Language', 'اللغة'),
            style: TextStyle(
              color: Color(0xFF881337),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _LanguageChoice(
          label: 'EN',
          selected: value == 'EN',
          onTap: () => onChanged('EN'),
        ),
        const SizedBox(width: 4),
        _LanguageChoice(
          label: 'AR',
          selected: value == 'AR',
          onTap: () => onChanged('AR'),
        ),
      ],
    ),
  );
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF1F2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.brandSecondary : AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Text(
    value,
    style: const TextStyle(
      color: AppColors.textTertiary,
      fontSize: 9,
      letterSpacing: 1.15,
      fontWeight: FontWeight.w700,
    ),
  );
}

BoxDecoration _cardDecoration(BuildContext context, double radius) =>
    BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.045),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet();
  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  String selected = 'annual';
  @override
  Widget build(BuildContext context) {
    final features = [
      (_pr('Advanced Fiqh guidance', 'إرشاد فقهي متقدم'), Icons.auto_awesome),
      (_pr('Guided journeys and insights', 'رحلات إرشادية ورؤى'), Icons.bolt),
      (
        _pr('Private, secure experience', 'تجربة خاصة وآمنة'),
        Icons.shield_outlined,
      ),
      (
        _pr('PCOS and endometriosis support', 'دعم التكيس وبطانة الرحم'),
        Icons.favorite_border,
      ),
      (_pr('FSA/HSA eligible', 'مؤهل لـ FSA/HSA'), Icons.credit_card),
    ];
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .95,
      ),
      padding: EdgeInsets.fromLTRB(
        28,
        26,
        28,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF059669)),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _pr('Unlock Niswah Plus', 'افتحي مزايا نسوة بلس'),
            style: TextStyle(
              fontFamily: AppTypography.serifFamily,
              color: const Color(0xFF064E3B),
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _pr(
              'Deeper insight, clearer guidance, and support made for every stage.',
              'رؤى أعمق وإرشاد أوضح ودعم لكل مرحلة.',
            ),
            style: const TextStyle(color: Color(0x9960596B), height: 1.55),
          ),
          const SizedBox(height: 24),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(f.$2, color: const Color(0xFF059669), size: 17),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      f.$1,
                      style: const TextStyle(
                        color: Color(0xFF064E3B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _plan('monthly', _pr('Monthly', 'شهري'), r'$9.99 / month'),
          const SizedBox(height: 10),
          _plan(
            'annual',
            _pr('Annual', 'سنوي'),
            r'$79.99 / year',
            badge: _pr('SAVE 20%', 'وفري ٢٠٪'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              minimumSize: const Size.fromHeight(58),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
            child: Text(_pr('Start free trial', 'ابدئي التجربة المجانية')),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _pr(
                'TERMS OF SERVICE   •   RESTORE PURCHASE',
                'الشروط   •   استعادة المشتريات',
              ),
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 9,
                letterSpacing: .8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plan(String id, String title, String price, {String? badge}) {
    final active = selected == id;
    return InkWell(
      onTap: () => setState(() => selected = id),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFECFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active ? const Color(0xFF10B981) : const Color(0x0D000000),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF064E3B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          badge,
                          style: const TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    price,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 12,
              backgroundColor: active
                  ? const Color(0xFF10B981)
                  : const Color(0xFFE5E7EB),
              child: active
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

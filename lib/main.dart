import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_environment.dart';
import 'core/errors/app_error_reporter.dart';
import 'core/localization/app_locale_controller.dart';
import 'core/network/supabase_client.dart';
import 'core/preferences/marital_status_controller.dart';
import 'core/preferences/madhhab_controller.dart';
import 'core/preferences/notification_log_controller.dart';
import 'core/preferences/prayer_location_controller.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'core/widgets/floating_nav_bar.dart';
import 'features/notifications/domain/services/notification_refresh_coordinator.dart';
import 'features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'features/auth/presentation/screens/profile_screen.dart';
import 'features/auth/presentation/screens/sign_in_screen.dart';
import 'features/community/presentation/screens/community_board_screen.dart';
import 'features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart';
import 'features/cycle_tracking/presentation/viewmodels/cycle_tracking_view_model.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/insights/presentation/screens/insights_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';

/// TEMPORARY DEBUG FLAG — set to true only for local preview of
/// the onboarding flow. When true, the app skips signup/login and
/// opens onboarding directly at the Madhhab step.
const bool kDebugSkipSignup = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Widget-build-time errors and platform-level async errors don't pass
  // through the zone guard below — without these two hooks they fall
  // through to Flutter's default handling with no team-visible signal at
  // all (the exact gap RR-002/OB-002 identified). Both route through the
  // same funnel as the zone guard's handler.
  FlutterError.onError = (details) {
    AppErrorReporter.report(
      details.exception,
      details.stack,
      context: 'FlutterError',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppErrorReporter.report(error, stack, context: 'PlatformDispatcher');
    return true;
  };

  // Config loading is startup-critical: if it fails, the app must show a
  // visible error, not hang indefinitely on the native splash screen (the
  // failure mode DC-004 identified). This is deliberately outside
  // runZonedGuarded below, which exists for a different purpose — see its
  // own comment.
  try {
    await dotenv.load();
    await AppEnvironment.load();
  } catch (error, stack) {
    AppErrorReporter.report(error, stack, context: 'startup config load');
    runApp(_StartupErrorApp(error: error));
    return;
  }

  // A deep link with a stale/reused/invalid Supabase auth code (e.g. a
  // confirmation link opened twice) throws an uncaught AuthApiException
  // from inside supabase_flutter's own internal deeplink handling — this
  // guard keeps that from taking down the whole app. Errors caught here
  // (and anything else uncaught in an async gap during the app's lifetime)
  // are reported, not silently discarded.
  runZonedGuarded(
    () async {
      await NiswahSupabase.initialize();
      AuthController.instance.init();
      await AppLocaleController.instance.load();
      await AppThemeController.instance.load();
      await MaritalStatusController.instance.load();
      await MadhhabController.instance.load();
      await PrayerLocationController.instance.load();
      await NotificationLogController.instance.load();
      await NotificationService.instance.initialize();

      runApp(const NiswahApp());
    },
    (error, stack) {
      AppErrorReporter.report(error, stack, context: 'runZonedGuarded');
    },
  );
}

/// Shown only when startup-critical config fails to load — replaces an
/// indefinite native-splash hang with a visible, minimal error state.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Niswah could not start.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NiswahApp extends StatelessWidget {
  const NiswahApp({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppLocaleController.instance,
        AuthController.instance,
        AppThemeController.instance,
      ]),
      builder: (context, _) {
        final arabic = AppLocaleController.instance.isArabic;
        final baseTheme = AppTheme.lightTheme;
        final baseDarkTheme = AppTheme.darkTheme;
        final theme = arabic
            ? baseTheme.copyWith(
                textTheme: baseTheme.textTheme.apply(
                  fontFamily: AppTypography.arabicFamily,
                ),
                primaryTextTheme: baseTheme.primaryTextTheme.apply(
                  fontFamily: AppTypography.arabicFamily,
                ),
              )
            : baseTheme;
        final darkTheme = arabic
            ? baseDarkTheme.copyWith(
                textTheme: baseDarkTheme.textTheme.apply(
                  fontFamily: AppTypography.arabicFamily,
                ),
                primaryTextTheme: baseDarkTheme.primaryTextTheme.apply(
                  fontFamily: AppTypography.arabicFamily,
                ),
              )
            : baseDarkTheme;
        return MaterialApp(
          title: 'Niswah',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: darkTheme,
          themeMode: AppThemeController.instance.themeMode,
          locale: AppLocaleController.instance.locale,
          builder: (context, child) => Directionality(
            textDirection: AppLocaleController.instance.textDirection,
            child: child!,
          ),
          home: kDebugSkipSignup
              ? OnboardingScreen(
                  initialStep: 4,
                  onFinished: () =>
                      Navigator.of(context).pushReplacementNamed('/'),
                )
              : !AuthController.instance.isAuthenticated
              ? const SignInScreen()
              : AuthController.instance.isNewSignUp
              // Step 3 of onboarding is itself a login step — skip straight
              // past splash/language/login to Madhhab (step 4), since this
              // user is already authenticated by the time they land here.
              ? OnboardingScreen(
                  initialStep: 4,
                  onFinished: AuthController.instance.clearNewSignUp,
                )
              : NiswahHomeShell(initialIndex: initialTabIndex),
          routes: {
            '/onboarding': (routeContext) => OnboardingScreen(
              onFinished: () =>
                  Navigator.of(routeContext).pushReplacementNamed('/'),
            ),
          },
          // A Supabase auth-callback deep link (e.g. niswah://login-callback
          // ?code=...) doesn't match any named route — supabase_flutter's
          // own AppLinks listener already handles it separately to exchange
          // the session, so this only needs to swallow the resulting
          // "unknown route" push quietly instead of throwing. Pops itself
          // on the next frame so it never lingers on top of the real screen.
          onUnknownRoute: (settings) => PageRouteBuilder(
            opaque: false,
            pageBuilder: (routeContext, _, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(routeContext).canPop()) {
                  Navigator.of(routeContext).pop();
                }
              });
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}

class NiswahHomeShell extends StatefulWidget {
  const NiswahHomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<NiswahHomeShell> createState() => _NiswahHomeShellState();
}

class _NiswahHomeShellState extends State<NiswahHomeShell>
    with WidgetsBindingObserver {
  late int _selectedIndex;
  // Shared by Today/Calendar/Insights so a log saved on one tab is
  // reflected on the others immediately — the tabs live in an
  // IndexedStack and never remount, so a screen-owned instance would
  // otherwise keep showing stale data until the app restarts.
  late final CycleTrackingViewModel _cycleViewModel;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 4);
    _cycleViewModel = CycleTrackingViewModel()..loadLogs();
    WidgetsBinding.instance.addObserver(this);
    // Recompute what should be scheduled the moment the home shell is
    // reachable (i.e. the user is signed in) — mirrors how the reports
    // recompute fresh each time they're opened, applied to scheduling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotifications();
      // App-start retry trigger — one of two triggers (with app-resume,
      // below) that make CycleTrackingViewModel.saveLog's "backs up
      // automatically" wording actually true rather than aspirational
      // copy (RR-001). A bounded, one-pass sweep per trigger — not a
      // timer/loop — so this can never spin indefinitely.
      unawaited(_cycleViewModel.retryPendingSync());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotifications();
      // App-resume retry trigger — see the app-start trigger in initState
      // for why this exists and what it does/doesn't guarantee.
      unawaited(_cycleViewModel.retryPendingSync());
    }
  }

  void _refreshNotifications() {
    NotificationRefreshCoordinator.refresh(
      userId: NiswahSupabase.clientOrNull?.auth.currentUser?.id,
    );
  }

  List<_NavPage> get _pages => [
    _NavPage(
      title: 'Today',
      icon: Icons.home_rounded,
      screen: DashboardScreen(
        onProfileTap: () => setState(() => _selectedIndex = 4),
        viewModel: _cycleViewModel,
      ),
    ),
    _NavPage(
      title: 'Calendar',
      icon: Icons.calendar_month_rounded,
      screen: CycleTrackingScreen(viewModel: _cycleViewModel),
    ),
    _NavPage(
      title: 'Insights',
      icon: Icons.bar_chart_rounded,
      screen: InsightsScreen(viewModel: _cycleViewModel),
    ),
    _NavPage(
      title: 'Community',
      icon: Icons.groups_rounded,
      screen: CommunityBoardScreen(),
    ),
    _NavPage(
      title: 'Profile',
      icon: Icons.person_rounded,
      screen: ProfileScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ar = AppLocaleController.instance.isArabic;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages.map((page) => page.screen).toList(),
      ),
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        onFABPressed: () {
          // Open AI chat or primary action
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (context) => const DrNiswahChatScreen(),
            ),
          );
        },
        dark: Theme.of(context).brightness == Brightness.dark,
        showFab: _selectedIndex != 3,
        items: [
          FloatingNavItem(
            targetIndex: 0,
            icon: Icons.home_outlined,
            label: ar ? 'اليوم' : 'Today',
          ),
          FloatingNavItem(
            targetIndex: 1,
            icon: Icons.calendar_month_outlined,
            label: ar ? 'التقويم' : 'Calendar',
          ),
          FloatingNavItem(
            targetIndex: 2,
            icon: Icons.bar_chart_outlined,
            label: ar ? 'الرؤى' : 'Insights',
          ),
          FloatingNavItem(
            targetIndex: 3,
            icon: Icons.groups_outlined,
            label: ar ? 'المجتمع' : 'Community',
          ),
          FloatingNavItem(
            targetIndex: 4,
            icon: Icons.person_outline_rounded,
            label: ar ? 'الملف الشخصي' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _NavPage {
  const _NavPage({
    required this.title,
    required this.icon,
    required this.screen,
  });

  final String title;
  final IconData icon;
  final Widget screen;
}

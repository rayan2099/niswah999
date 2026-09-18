import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
import 'core/storage/local_sensitive_data_cleanup.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'core/utils/device_timezone.dart';
import 'core/widgets/floating_nav_bar.dart';
import 'core/widgets/niswah_loading_indicator.dart';
import 'features/notifications/domain/services/notification_refresh_coordinator.dart';
import 'features/ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/screens/profile_screen.dart';
import 'features/auth/presentation/screens/sign_in_screen.dart';
import 'features/community/presentation/screens/community_board_screen.dart';
import 'features/cycle_tracking/data/repositories/bleeding_episode_repository_impl.dart';
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

  // Config loading is startup-critical: if it fails, the app must show a
  // visible error, not hang indefinitely on the native splash screen (the
  // failure mode DC-004 identified). This must also run before Sentry can
  // be configured below, since the DSN itself comes from this config — a
  // config-load failure this early can only reach `debugPrint`, not Sentry.
  // This is deliberately outside runZonedGuarded below, which exists for a
  // different purpose — see its own comment.
  try {
    await dotenv.load();
    await AppEnvironment.load();
  } catch (error, stack) {
    AppErrorReporter.report(error, stack, context: 'startup config load');
    runApp(_StartupErrorApp(error: error));
    return;
  }

  // `options.dsn` left empty (no Sentry project configured yet, e.g. local
  // dev) makes the SDK a documented no-op transport — it still initializes
  // cleanly but sends nothing, so this call is always safe to make.
  await SentryFlutter.init((options) {
    options.dsn = AppEnvironment.sentryDsn;
    options.environment = AppEnvironment.appEnvironment;
    // We deliberately do not rely on SentryFlutter's own automatic
    // FlutterError/PlatformDispatcher hooks — this app already has its own
    // versions of both (registered below) that funnel through
    // AppErrorReporter alongside every repository's manual report() calls.
    // Wiring AppErrorReporter.onReport to Sentry.captureException (below)
    // is the single point where any of those paths reaches Sentry, so nothing
    // is ever reported twice.
    options.beforeSend = (event, hint) => _scrubBeforeSend(event);
  }, appRunner: () => _runApp());
}

/// The actual app bootstrap, run inside Sentry's zone via `appRunner` so
/// Sentry's native (Android/iOS) crash capture is active for the app's
/// entire lifetime — but see `SentryFlutter.init` above for why Sentry's own
/// Dart-level FlutterError/PlatformDispatcher hooks are not used directly.
Future<void> _runApp() async {
  // The one and only place AppErrorReporter reaches a real destination.
  // Every existing call site (FlutterError.onError, PlatformDispatcher.onError,
  // runZonedGuarded, and ~40+ repository catch blocks) already funnels
  // through AppErrorReporter.report() — wiring this hook here, rather than
  // adding Sentry calls at each of those sites, is what makes all of them
  // reach Sentry without any of them changing.
  AppErrorReporter
      .onReport = (error, stack, {context, feature, retryAttempt, recordId}) {
    if (AppEnvironment.sentryDsn.isEmpty) return;
    unawaited(
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          if (context != null) scope.setTag('context', context);
          if (feature != null) scope.setTag('feature', feature);
          if (retryAttempt != null) {
            scope.setContexts('retry', {'attempt': retryAttempt});
          }
          // recordId is an opaque id only (never record content) by
          // AppErrorReporter's own contract — safe as an extra.
          if (recordId != null) scope.setContexts('record', {'id': recordId});
        },
      ),
    );
  };

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
      // Best-effort retry of any account-deletion local cleanup that
      // didn't fully complete on a prior run — not startup-critical, so
      // deliberately not awaited; failures are reported internally via
      // AppErrorReporter rather than surfaced here.
      unawaited(retryPendingLocalSensitiveDataCleanups());
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

/// Defense-in-depth text scrub applied to every outgoing Sentry event,
/// on top of (not instead of) AppErrorReporter's own existing discipline of
/// only ever passing opaque record ids — never auth tokens, API keys, or
/// record/message content — into its fields. Redacts values that look like
/// bearer tokens or API keys if any ever end up in an exception's own
/// message text (e.g. from a third-party package we don't control).
/// Public and `@visibleForTesting` so this pattern-matching is covered by a
/// real unit test rather than only by code review.
@visibleForTesting
String scrubSecretsForSentry(String input) => input
    .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9\-_.]+'), 'Bearer [redacted]')
    .replaceAll(
      RegExp(r'eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+'),
      '[redacted-jwt]',
    );

SentryEvent? _scrubBeforeSend(SentryEvent event) {
  for (final exception in event.exceptions ?? const []) {
    final value = exception.value;
    if (value != null) exception.value = scrubSecretsForSentry(value);
  }

  return event;
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

/// AUTH-012: shown instead of an indefinite spinner whenever an
/// authenticated session's onboarding-status check fails for any reason
/// (missing `public.users` row, RLS denial, network/timeout, a stale
/// session referencing a deleted account). Offers a real recovery path —
/// retry re-runs the same check the app would have tried on its own;
/// sign out is the honest way forward for a session this device can never
/// resolve on its own (e.g. one referencing an account that no longer
/// exists), rather than silently fabricating a routing decision.
class _AuthGateErrorScreen extends StatefulWidget {
  const _AuthGateErrorScreen();

  @override
  State<_AuthGateErrorScreen> createState() => _AuthGateErrorScreenState();
}

class _AuthGateErrorScreenState extends State<_AuthGateErrorScreen> {
  bool _signingOut = false;

  Future<void> _retry() => AuthController.instance.refreshOnboardingStatus();

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthRepositoryImpl().signOut();
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: '_AuthGateErrorScreen.signOut',
        feature: 'auth',
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arabic = AppLocaleController.instance.isArabic;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  arabic
                      ? 'تعذر تحميل حسابك'
                      : "We couldn't load your account.",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  arabic
                      ? 'تحققي من اتصالك وحاولي مرة أخرى.'
                      : 'Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _signingOut ? null : _retry,
                  child: Text(arabic ? 'إعادة المحاولة' : 'Retry'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _signingOut ? null : _signOut,
                  child: _signingOut
                      ? NiswahLoadingIndicator(
                          size: NiswahLoadingSize.small,
                          contrast: NiswahLoadingContrast.dark,
                        )
                      : Text(arabic ? 'تسجيل الخروج' : 'Sign out'),
                ),
              ],
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
          home: _buildHome(context),
          routes: {
            // Not currently navigated to anywhere in the app (root
            // routing in _buildHome already shows OnboardingScreen
            // whenever needed) — kept for any future direct-navigation
            // use, with the same completion-persistence contract as the
            // main path so it can never silently skip it.
            '/onboarding': (routeContext) => OnboardingScreen(
              onFinished: () {
                AuthController.instance.setOnboardingCompletedLocally(true);
                Navigator.of(routeContext).pushReplacementNamed('/');
              },
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

  /// AUTH-002's routing contract — the ONLY place this decision is made,
  /// per finding evidence in
  /// production-readiness-results/master/00_04_MASTER_FINDING_REGISTER.md:
  ///
  /// STATE 1: not authenticated -> SignInScreen.
  /// STATE 2 (email-confirmation-pending) is handled entirely inside
  ///   SignInScreen itself (`_awaitingEmailConfirmation`) — it never
  ///   reaches this router, since no session exists yet.
  /// STATE "checking" (authenticated, onboarding status not yet known) ->
  ///   a brief loading indicator, never a guess — this is the state that
  ///   used to be silently treated as "onboarding complete" by the old
  ///   `isNewSignUp` heuristic, which is exactly how a freshly-confirmed
  ///   new user could reach the dashboard without ever completing
  ///   onboarding (AUTH-002).
  /// STATE 3/5 (onboarding incomplete, whether brand-new or partially
  ///   done): OnboardingScreen. `isNewSignUp` is consulted ONLY to decide
  ///   the initial step (skip the redundant login step for a user who is
  ///   already authenticated in this same process) — never to decide
  ///   whether onboarding is shown at all.
  /// STATE 4 (onboarding complete): NiswahHomeShell.
  Widget _buildHome(BuildContext context) {
    if (kDebugSkipSignup) {
      return OnboardingScreen(
        initialStep: 2,
        onFinished: () => Navigator.of(context).pushReplacementNamed('/'),
      );
    }

    final auth = AuthController.instance;
    if (!auth.isAuthenticated) {
      return const SignInScreen();
    }

    // AUTH-012 (Startup Auth-Gate Infinite-Spinner Investigation): each of
    // these 4 states is now real and distinguishable — in particular,
    // `error` is never collapsed into `loading`, so a backend failure
    // (missing public.users row, RLS denial, network/timeout, a stale
    // session referencing a deleted account) always reaches a real,
    // recoverable screen instead of an indefinite spinner.
    switch (auth.onboardingStatus) {
      case OnboardingStatus.loading:
        return Scaffold(
          body: Center(
            child: NiswahLoadingIndicator(
              size: NiswahLoadingSize.large,
              contrast: NiswahLoadingContrast.dark,
              semanticsLabel: AppLocaleController.instance.text(
                'Loading',
                'جارٍ التحميل',
              ),
            ),
          ),
        );
      case OnboardingStatus.error:
        return const _AuthGateErrorScreen();
      case OnboardingStatus.incomplete:
      case OnboardingStatus.complete:
        break;
    }

    if (auth.onboardingStatus == OnboardingStatus.incomplete) {
      return OnboardingScreen(
        // AUTH-008/AUTH-009: onboarding itself has no login step and no
        // language step any more (this branch already proves
        // `auth.isAuthenticated == true`, and AppLocaleController is
        // already the sole language authority) — splash is the only step
        // before Madhhab, and skipping it for a signup that just
        // completed in this same process is a pure UX nicety, never a
        // correctness requirement. Any other case (a returning-but-not-
        // onboarded user, a confirmation-driven session from a fresh
        // process) starts at step 1, which is correct and safe — never
        // skipped based on a guess.
        initialStep: auth.isNewSignUp ? 2 : 1,
        onFinished: () {
          auth.clearNewSignUp();
          auth.setOnboardingCompletedLocally(true);
        },
      );
    }

    return NiswahHomeShell(initialIndex: initialTabIndex);
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
      // Menstrual Data Integrity charter, PR #4 completion wave, Fix D:
      // replays any bleeding_episodes start/end operation that reached
      // the server and committed but never got the chance to tell the
      // app so (the process was killed first) — the same app-start
      // trigger that already recovers the legacy cycle_entries model.
      unawaited(BleedingEpisodeRepositoryImpl().reconcilePendingOperations());
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
      // Hardening 3: the device's timezone may genuinely have changed
      // while the app was backgrounded (travel, or a manual change) —
      // DeviceTimezone must never answer with a value cached from before
      // the app went to the background. Invalidated before
      // _refreshNotifications so any reminder recomputation it triggers
      // already sees the real current zone, never a stale one.
      DeviceTimezone.invalidateCache();
      _refreshNotifications();
      // App-resume retry trigger — see the app-start trigger in initState
      // for why this exists and what it does/doesn't guarantee.
      unawaited(_cycleViewModel.retryPendingSync());
      unawaited(BleedingEpisodeRepositoryImpl().reconcilePendingOperations());
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

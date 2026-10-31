import 'package:flutter/widgets.dart';

/// Observes the app's root navigator, so screens opened over the home
/// screen can be closed when the account changes. An observer rather than
/// a navigator GlobalKey: a key would carry the navigator's routes over
/// when the app widget itself is replaced.
final NavigatorObserver appNavigatorObserver = NavigatorObserver();

/// Closes every screen, sheet and dialog opened over the home screen when
/// the signed-in account changes or the session ends (journeys NJ-071,
/// NJ-182, NJ-232).
///
/// The auth gate swaps the home screen on sign-out, but routes pushed on
/// top of it (a data export, a report, a chat, an edit sheet) used to stay
/// open above the sign-in screen and could still show, copy or save the
/// previous account's data after another account signed in. Nothing is
/// saved or discarded here: each screen's own dispose and account checks
/// still decide what happens to work in progress.
class AccountRouteBoundary {
  AccountRouteBoundary({
    required this.auth,
    required this.currentAccount,
    NavigatorObserver? navigatorObserver,
  }) : navigatorObserver = navigatorObserver ?? appNavigatorObserver,
       _account = currentAccount() {
    auth.addListener(_changed);
  }

  final Listenable auth;
  final String? Function() currentAccount;
  final NavigatorObserver navigatorObserver;
  String? _account;

  void _changed() {
    final next = currentAccount();
    if (next == _account) return;
    final previous = _account;
    _account = next;
    // Signing in from signed out leaves the sign-in sheet to close itself:
    // nothing over the sign-in screen belongs to an account yet.
    if (previous == null) return;
    navigatorObserver.navigator?.popUntil((route) => route.isFirst);
  }

  void dispose() => auth.removeListener(_changed);
}

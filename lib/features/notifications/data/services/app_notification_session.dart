import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/services/notification_refresh_coordinator.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/notification_delivery_preferences.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/device_timezone.dart';
import '../../domain/entities/activity_notification.dart';
import '../../domain/entities/notification_target.dart';
import '../../presentation/viewmodels/activity_inbox_controller.dart';
import '../repositories/activity_notification_repository.dart';

class AppNotificationSession {
  AppNotificationSession._();
  static final instance = AppNotificationSession._();
  static const enabled = bool.fromEnvironment('NISWAH_PUSH_ENABLED');
  SupabaseClient? _client;
  FirebaseMessaging? _messaging;
  StreamSubscription<AuthState>? _auth;
  final _subscriptions = <StreamSubscription>[];
  Future<void>? _initializing;
  Future<void>? _refreshing;
  Future<void>? _registrationTail;
  int _generation = 0;
  String? _userId;
  String? _token;
  String? activeConversation;
  Object? _conversationOwner;
  bool Function()? conversationIsVisible;
  void showConversation(String id, Object owner, bool Function() visible) {
    activeConversation = id;
    _conversationOwner = owner;
    conversationIsVisible = visible;
  }

  void hideConversation(Object owner) {
    if (identical(owner, _conversationOwner)) {
      activeConversation = null;
      _conversationOwner = null;
      conversationIsVisible = null;
    }
  }

  final _seen = <String>{};
  final availability = ValueNotifier<bool>(false);
  bool get phoneAlertsConfigured => availability.value;
  ActivityNotificationRepository? Function()? _repositoryFactory;
  void restoreSession() => _bind(_client?.auth.currentUser?.id);

  Future<void> stop() async {
    _generation++;
    await _auth?.cancel();
    _auth = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _client = null;
    _userId = null;
    _token = null;
    _messaging = null;
    _seen.clear();
    availability.value = false;
    ActivityInboxController.instance.bind(null, null);
  }

  Future<void> start(
    SupabaseClient client, {
    ActivityNotificationRepository? Function()? repositoryFactory,
  }) async {
    if (identical(_client, client)) return;
    await _auth?.cancel();
    _client = client;
    _repositoryFactory = repositoryFactory;
    _bind(client.auth.currentUser?.id);
    _auth = client.auth.onAuthStateChange.listen((event) {
      final id = event.session?.user.id;
      if (id != _userId) _bind(id);
    });
    unawaited(refreshRegistration());
  }

  void _bind(String? id) {
    _generation++;
    _refreshing = null;
    availability.value = false;
    _userId = id;
    activeConversation = null;
    _seen.clear();
    ActivityInboxController.instance.bind(
      id,
      id == null
          ? null
          : (_repositoryFactory?.call() ??
                SupabaseActivityNotificationRepository(_client!)),
    );
    unawaited(refreshRegistration());
  }

  Future<void> _initializeProvider() async {
    if (!enabled ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    if (_messaging != null) return;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final appId = ios
        ? const String.fromEnvironment('FIREBASE_IOS_APP_ID')
        : const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    const key = String.fromEnvironment('FIREBASE_API_KEY');
    const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (appId.isEmpty ||
        !appId.contains(ios ? ':ios:' : ':android:') ||
        key.isEmpty ||
        sender.isEmpty ||
        project.isEmpty) {
      return;
    }
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: key,
        appId: appId,
        messagingSenderId: sender,
        projectId: project,
      ),
    );
    final messaging = _messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen(
        (m) => unawaited(handleForegroundData(m.data)),
      ),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((m) => handleTapData(m.data)),
    );
    _subscriptions.add(
      messaging.onRegistered.listen((token) => unawaited(_tryRegister(token))),
    );
    final initial = await messaging.getInitialMessage();
    if (initial != null) handleTapData(initial.data);
  }

  Future<void> refreshRegistration() {
    final pending = _refreshing;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = _refreshRegistration().whenComplete(() {
      if (identical(_refreshing, operation)) _refreshing = null;
    });
    _refreshing = operation;
    return operation;
  }

  Future<void> _refreshRegistration() async {
    if (_client == null || _userId == null) return;
    final generation = _generation;
    try {
      final client = _client!, user = _userId!;
      final zone = await DeviceTimezone.currentId(forceRefresh: true)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (generation != _generation) return;
      if (zone != null) {
        final delivery = NotificationDeliveryPreferences.instance;
        final before = delivery.toJson();
        final context = {
          'timezone': zone,
          'locale': AppLocaleController.instance.isArabic ? 'ar' : 'en',
        };
        final row = await client
            .from('notification_preferences')
            .update(context)
            .eq('user_id', user)
            .select()
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        if (generation != _generation) return;
        if (row == null) {
          // Someone who never opened the activity settings has no row, and
          // the server would otherwise phrase every alert in its default
          // language. Seed it from this device's current controls.
          await client
              .from('notification_preferences')
              .upsert({
                ...before,
                ...context,
                'user_id': user,
              }, ignoreDuplicates: true)
              .timeout(const Duration(seconds: 10));
          if (generation != _generation) return;
        }
        if (row != null && mapEquals(before, delivery.toJson())) {
          final controls = {for (final key in before.keys) key: row[key]};
          if (!mapEquals(before, controls)) {
            delivery.apply(controls);
            await delivery.save(snapshot: controls);
            if (generation != _generation) return;
            await NotificationRefreshCoordinator.refresh(userId: user);
          }
        }
      }
      if (generation != _generation) return;
      await (_initializing ??= _initializeProvider().whenComplete(
        () => _initializing = null,
      ));
      if (generation != _generation || _messaging == null) return;
      final settings = await _messaging!.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await _messaging!.getAPNSToken() == null) {
        return;
      }
      if (generation != _generation) return;
      await _messaging!
          .register(); // onRegistered supplies the opaque device token.
    } catch (_) {
      AppErrorReporter.report(
        StateError('Phone notification registration unavailable'),
        StackTrace.current,
        context: 'AppNotificationSession.registration',
        feature: 'notifications',
      );
    }
  }

  Future<void> _tryRegister(String token) async {
    try {
      await _register(token);
    } catch (_) {
      AppErrorReporter.report(
        StateError('Phone notification token refresh unavailable'),
        StackTrace.current,
        context: 'AppNotificationSession.tokenRefresh',
        feature: 'notifications',
      );
    }
  }

  Future<void> _register(String token) {
    final generation = _generation, user = _userId, client = _client;
    final operation = (_registrationTail ?? Future<void>.value()).then((
      _,
    ) async {
      if (user == null ||
          client == null ||
          generation != _generation ||
          client.auth.currentUser?.id != user) {
        return;
      }
      await client
          .rpc(
            'register_notification_device',
            params: {
              'p_token': token,
              'p_platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (generation == _generation) {
        _token = token;
        availability.value = true;
      }
    });
    final settled = operation.catchError((Object _) {});
    _registrationTail = settled;
    settled.then((_) {
      if (identical(_registrationTail, settled)) _registrationTail = null;
    });
    return operation;
  }

  Future<void> beforeSignOut() async {
    final client = _client, token = _token;
    _generation++;
    activeConversation = null;
    ActivityInboxController.instance.bind(null, null);
    try {
      await _registrationTail;
      if (client != null && token != null) {
        await client
            .rpc('unregister_notification_device', params: {'p_token': token})
            .timeout(const Duration(seconds: 5));
      }
      await _messaging?.unregister();
    } catch (_) {
      AppErrorReporter.report(
        StateError('Push device cleanup will rely on session revocation'),
        StackTrace.current,
        context: 'AppNotificationSession.signOut',
        feature: 'notifications',
      );
    } finally {
      _token = null;
    }
  }

  bool _belongs(Map<String, dynamic> data) =>
      _userId != null &&
      data['userId'] == _userId &&
      _client?.auth.currentUser?.id == _userId;
  void handleTapData(Map<String, dynamic> data) {
    if (!_belongs(data)) return;
    final target = NotificationTarget.tryParse(data);
    if (target == null) return;
    NotificationService.instance.enqueueTap(jsonEncode(target.toJson()));
  }

  Future<void> handleForegroundData(Map<String, dynamic> data) async {
    if (!_belongs(data)) return;
    final event = data['eventId'];
    if (event is! String || _seen.contains(event)) return;
    final generation = _generation;
    await ActivityInboxController.instance.refresh();
    if (generation != _generation || !_belongs(data)) return;
    final verified = ActivityInboxController.instance.entries
        .where((e) => e.id == event)
        .firstOrNull;
    if (verified == null || verified.read) return;
    final prefs = NotificationDeliveryPreferences.instance;
    final zone = await DeviceTimezone.currentId();
    if (generation != _generation ||
        zone == null ||
        !prefs.allows(
          tz.TZDateTime.from(DateTime.now(), tz.getLocation(zone)),
        )) {
      return;
    }
    if (verified.kind == 'privateMessage' &&
        (!prefs.messages ||
            (activeConversation == verified.target.targetId &&
                (conversationIsVisible?.call() ?? true)))) {
      return;
    }
    if (verified.kind == 'communityComment' && !prefs.comments) return;
    if (verified.kind == 'communityLike' && !prefs.likes) return;
    if (_seen.contains(event)) return;
    _seen.add(event);
    if (_seen.length > 500) _seen.remove(_seen.first);
    final ar = AppLocaleController.instance.isArabic;
    await NotificationService.instance.showNow(
      id: alertIdFor(verified.kind, verified.target.targetId!),
      title: ar ? 'نِسواه' : 'Niswah',
      body: ActivityNotification.alertBody(verified.kind, ar),
      payload: jsonEncode(verified.target.toJson()),
      activity: true,
    );
  }

  /// One alert slot per conversation or post (like the worker's Android tag),
  /// so a burst of messages replaces the previous alert instead of stacking.
  /// Stable across launches; kept within 800–889, clear of reminder ids.
  static int alertIdFor(String kind, String targetId) {
    var hash = 0x811c9dc5;
    for (final unit in '$kind:$targetId'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return 800 + hash % 90;
  }
}

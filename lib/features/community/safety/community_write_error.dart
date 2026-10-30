import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../../../core/localization/app_locale_controller.dart';
import '../../private_messaging/data/repositories/private_messaging_repository.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Errors the database raises for community safety rules
/// (supabase/migrations/20261030090000_community_ugc_safety.sql).
enum CommunityWriteError {
  /// NSW01: the text contains a blocked word.
  objectionableContent,

  /// NSW02: the member has not accepted the current community terms.
  termsNotAccepted,

  /// NSW03: the member is suspended from Community.
  suspended,

  /// NSW04: the two members have blocked each other.
  blocked,

  /// NSW05: daily report limit reached.
  reportLimit;

  static const _codes = {
    'NSW01': CommunityWriteError.objectionableContent,
    'NSW02': CommunityWriteError.termsNotAccepted,
    'NSW03': CommunityWriteError.suspended,
    'NSW04': CommunityWriteError.blocked,
    'NSW05': CommunityWriteError.reportLimit,
  };

  /// Finds a safety error in [error] — a [PostgrestException], or a
  /// [Failure] / [PrivateMessagingException] wrapping one in `cause` — by
  /// its SQLSTATE `code`.
  static CommunityWriteError? from(Object? error) {
    final cause = switch (error) {
      Failure(:final cause) => cause,
      PrivateMessagingException(:final cause) => cause,
      _ => error,
    };
    if (cause is PostgrestException) return _codes[cause.code];
    return null;
  }

  String message() => switch (this) {
    CommunityWriteError.objectionableContent => _t(
      'This includes language that isn\'t allowed in Niswah Community. '
          'Please edit it and try again.',
      'يحتوي هذا على كلمات غير مسموح بها في مجتمع نِسوة. يُرجى تعديله '
          'والمحاولة مجدداً.',
    ),
    CommunityWriteError.termsNotAccepted => _t(
      'Please accept the community guidelines before posting or messaging.',
      'يُرجى قبول إرشادات المجتمع قبل النشر أو المراسلة.',
    ),
    CommunityWriteError.suspended => _t(
      'Your account is suspended from Community for breaking the '
          'guidelines.',
      'تم إيقاف حسابكِ عن المجتمع بسبب مخالفة الإرشادات.',
    ),
    CommunityWriteError.blocked => _t(
      'You can\'t interact with this member.',
      'لا يمكنكِ التفاعل مع هذه العضوة.',
    ),
    CommunityWriteError.reportLimit => _t(
      'You\'ve sent a lot of reports today. Please try again tomorrow.',
      'أرسلتِ بلاغات كثيرة اليوم. يُرجى المحاولة غداً.',
    ),
  };
}

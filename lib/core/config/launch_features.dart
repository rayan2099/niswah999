import 'package:flutter/foundation.dart';

/// Features whose launch scope is decided outside the code.
///
/// Community (posts, comments, private messages) has no way to block or
/// report another user yet, which App Store guideline 1.2 requires for
/// user-generated content (journeys NJ-183, NJ-184). Until that exists it
/// stays out of release builds. Build with
/// `--dart-define=NISWAH_COMMUNITY=true` to include it. Its data and
/// server tables are untouched: hiding it never deletes anything, and
/// existing posts and messages are still in her data export.
abstract final class LaunchFeatures {
  static const bool _communityDefine = bool.fromEnvironment('NISWAH_COMMUNITY');

  /// Lets tests turn community on or off regardless of the build define.
  @visibleForTesting
  static bool? debugCommunityOverride;

  static bool get community => debugCommunityOverride ?? _communityDefine;
}

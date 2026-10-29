import 'package:flutter/material.dart';

import '../../../../core/config/launch_features.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../ai_assistant/presentation/screens/dr_niswah_chat_screen.dart';
import '../../../auth/presentation/screens/profile_screen.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/presentation/screens/post_detail_screen.dart';
import '../../../community/presentation/viewmodels/community_feed_view_model.dart';
import '../../../education/presentation/screens/guided_journeys_screen.dart';
import '../../../prayer_tracking/presentation/screens/prayer_tracking_screen.dart';
import '../../../private_messaging/domain/entities/private_conversation.dart';
import '../../../private_messaging/presentation/screens/chat_detail_screen.dart';
import '../../domain/entities/notification_target.dart';

class NotificationNavigator {
  static int _openingGeneration = 0;
  static Future<void> open(
    BuildContext context,
    NotificationTarget target, {
    required VoidCallback calendar,
    required VoidCallback wellbeing,
  }) async {
    final generation = ++_openingGeneration;
    final client = NiswahSupabase.clientOrNull;
    bool cancelled = false, dismissing = false;
    DialogRoute<void>? loading;
    final navigator = Navigator.of(context);
    void dismissLoading() {
      dismissing = true;
      final route = loading;
      if (route != null && route.isActive) navigator.removeRoute(route);
    }

    bool current() =>
        !cancelled &&
        generation == _openingGeneration &&
        context.mounted &&
        client?.auth.currentUser?.id == target.userId;
    if (client == null || !current()) return;
    try {
      // A community notification can still be in her feed while community
      // is hidden for launch; it opens nothing and says it is unavailable.
      if (!LaunchFeatures.community &&
          (target.destination == NotificationDestination.conversation ||
              target.destination == NotificationDestination.post)) {
        throw StateError('Unavailable');
      }
      if ({
        NotificationDestination.conversation,
        NotificationDestination.post,
        NotificationDestination.aiChat,
      }.contains(target.destination)) {
        loading = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
        navigator.push(loading).then((_) {
          if (!dismissing) cancelled = true;
        });
      }
      Widget? screen;
      switch (target.destination) {
        case NotificationDestination.calendar:
          Navigator.of(context).popUntil((route) => route.isFirst);
          calendar();
          return;
        case NotificationDestination.wellbeing:
          Navigator.of(context).popUntil((route) => route.isFirst);
          wellbeing();
          return;
        case NotificationDestination.prayer:
          screen = const PrayerTrackingScreen();
        case NotificationDestination.pregnancy:
          screen = const ProfileScreen();
        case NotificationDestination.learning:
          screen = const GuidedJourneysScreen();
        case NotificationDestination.conversation:
          final row = await client
              .from('private_conversations')
              .select()
              .eq('id', target.targetId!)
              .maybeSingle()
              .timeout(const Duration(seconds: 10));
          if (!current()) return;
          if (row == null) throw StateError('Unavailable');
          final conversation = PrivateConversation.fromJson(row);
          if (!conversation.involves(target.userId)) {
            throw StateError('Unavailable');
          }
          screen = ChatDetailScreen(
            conversation: conversation,
            currentUserId: target.userId,
          );
        case NotificationDestination.post:
          final row = await client
              .from('community_posts')
              .select()
              .eq('id', target.targetId!)
              .maybeSingle()
              .timeout(const Duration(seconds: 10));
          if (!current()) return;
          if (row == null || row['is_hidden'] == true) {
            throw StateError('Unavailable');
          }
          final post = CommunityPost.fromJson(row);
          final name = AppLocaleController.instance.text(
            'Community member',
            'عضوة المجتمع',
          );
          final feed = CommunityFeedViewModel(
            currentUserId: target.userId,
            currentUserName: name,
            language: post.language,
          );
          screen = PostDetailScreen(
            post: post,
            currentUserId: target.userId,
            currentUserName: name,
            feedViewModel: feed,
          );
        case NotificationDestination.aiChat:
          final row = await client
              .from('chat_threads')
              .select('id,user_id')
              .eq('id', target.targetId!)
              .eq('user_id', target.userId)
              .maybeSingle()
              .timeout(const Duration(seconds: 10));
          if (!current()) return;
          if (row == null) throw StateError('Unavailable');
          screen = DrNiswahChatScreen(
            mode: NiswahAssistantMode.health,
            initialThreadId: target.targetId,
          );
      }
      if (!current()) return;
      dismissLoading();
      await navigator.push(MaterialPageRoute<void>(builder: (_) => screen!));
    } catch (_) {
      dismissLoading();
      if (context.mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocaleController.instance.text(
                'This update is no longer available. Please refresh and try again.',
                'هذا التحديث غير متاح الآن. حدّثي الصفحة وحاولي مجددًا.',
              ),
            ),
          ),
        );
      }
    } finally {
      dismissLoading();
    }
  }
}

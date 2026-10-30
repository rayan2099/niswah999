import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/core/preferences/community_language_controller.dart';
import 'package:niswah/features/community/domain/entities/community_post.dart';
import 'package:niswah/features/community/presentation/screens/community_board_screen.dart';
import 'package:niswah/features/community/presentation/viewmodels/community_error_message.dart';
import 'package:niswah/features/community/presentation/widgets/community_comment_tile.dart';
import 'package:niswah/features/community/presentation/widgets/community_post_card.dart';
import 'package:niswah/features/community/domain/entities/community_comment.dart';
import 'package:niswah/features/community/safety/blocked_members_screen.dart';
import 'package:niswah/features/community/safety/community_guidelines_screen.dart';
import 'package:niswah/features/community/safety/community_safety_actions.dart';
import 'package:niswah/features/community/safety/community_safety_controller.dart';
import 'package:niswah/features/community/safety/community_safety_models.dart';
import 'package:niswah/features/community/safety/community_safety_repository.dart';
import 'package:niswah/features/community/safety/community_terms_gate.dart';
import 'package:niswah/features/community/safety/moderation_queue_screen.dart';
import 'package:niswah/features/private_messaging/data/repositories/private_messaging_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App Store Review Guideline 1.2 journeys (NJ-183 block, NJ-184 report):
/// report, block, terms acceptance, moderation, and the messages a member
/// sees when the server refuses objectionable content.
void main() {
  late InMemoryCommunitySafetyRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocaleController.instance.setArabic(false);
    repository = InMemoryCommunitySafetyRepository();
    communitySafetyRepositoryOverride = repository;
    CommunitySafetyController.instance = CommunitySafetyController(
      repository: repository,
    );
  });

  tearDown(() => communitySafetyRepositoryOverride = null);

  CommunityPost post({String userId = 'user-9', bool anonymous = false}) =>
      CommunityPost(
        id: 'post-9',
        userId: userId,
        authorName: 'Layla',
        title: 'Title',
        content: 'Content',
        category: CommunityCategory.general,
        tags: const [],
        isAnonymous: anonymous,
        createdAt: DateTime(2026, 10, 1),
        language: CommunityLanguage.en,
      );

  /// Tall phone-sized surface so sheets and dialogs fit without scrolling.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets("another member's post offers Report and Block, not Delete", (
    tester,
  ) async {
    tall(tester);
    var reported = false;
    var blocked = false;
    await tester.pumpWidget(
      host(
        CommunityPostCard(
          post: post(),
          isOwnPost: false,
          onTap: () {},
          onLike: () {},
          onReport: () => reported = true,
          onBlock: () => blocked = true,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('community-post-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Delete post'), findsNothing);
    await tester.tap(find.text('Report post'));
    await tester.pumpAndSettle();
    expect(reported, isTrue);

    await tester.tap(find.byKey(const ValueKey('community-post-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block member'));
    await tester.pumpAndSettle();
    expect(blocked, isTrue);
  });

  testWidgets('own post offers Delete only', (tester) async {
    tall(tester);
    await tester.pumpWidget(
      host(
        CommunityPostCard(
          post: post(),
          isOwnPost: true,
          onTap: () {},
          onLike: () {},
          onDelete: () {},
          onReport: () {},
          onBlock: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('community-post-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Delete post'), findsOneWidget);
    expect(find.text('Report post'), findsNothing);
    expect(find.text('Block member'), findsNothing);
  });

  testWidgets("another member's comment offers Report and Block", (
    tester,
  ) async {
    tall(tester);
    var reported = false;
    await tester.pumpWidget(
      host(
        CommunityCommentTile(
          comment: CommunityComment(
            id: 'c1',
            postId: 'post-9',
            userId: 'user-8',
            authorName: 'Huda',
            content: 'hi',
            createdAt: DateTime(2026, 10, 1),
          ),
          isOwnComment: false,
          onDelete: () {},
          onReport: () => reported = true,
          onBlock: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('community-comment-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Block member'), findsOneWidget);
    await tester.tap(find.text('Report comment'));
    await tester.pumpAndSettle();
    expect(reported, isTrue);
  });

  testWidgets('NJ-184: report sheet needs a reason, then files the report', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommunityReportSheet(
                context,
                targetType: ReportTargetType.comment,
                targetId: 'comment-1',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final submit = find.byKey(const ValueKey('report-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
    await tester.enterText(find.byType(TextField), 'keeps insulting me');
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.reports, hasLength(1));
    expect(repository.reports.single.targetType, ReportTargetType.comment);
    expect(repository.reports.single.targetId, 'comment-1');
    expect(repository.reports.single.reason, ReportReason.harassment);
    expect(repository.reports.single.details, 'keeps insulting me');
    expect(find.textContaining('within 24 hours'), findsOneWidget);
  });

  testWidgets(
    "NJ-183: blocking a member removes her posts from the feed at once",
    (tester) async {
      tall(tester);
      await tester.pumpWidget(const MaterialApp(home: CommunityBoardScreen()));
      await tester.pumpAndSettle();
      // Offline preview data: user-1 authored this Arabic-community post.
      final title = find.textContaining('I have been trying to keep');
      expect(title, findsOneWidget);

      final menu = find.descendant(
        of: find.ancestor(of: title, matching: find.byType(CommunityPostCard)),
        matching: find.byKey(const ValueKey('community-post-menu')),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block member'));
      await tester.pumpAndSettle();
      expect(find.textContaining('won\'t see her posts'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Block'));
      await tester.pumpAndSettle();

      expect(CommunitySafetyController.instance.isBlocked('user-1'), isTrue);
      expect(repository.blocked.single.userId, 'user-1');
      expect(find.textContaining('I have been trying to keep'), findsNothing);
    },
  );

  testWidgets('blocked members can be unblocked from Profile', (tester) async {
    tall(tester);
    await repository.blockMember(userId: 'user-1', displayName: 'Alya');
    await tester.pumpWidget(const MaterialApp(home: BlockedMembersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Alya'), findsOneWidget);

    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(repository.blocked, isEmpty);
    expect(find.text('You haven\'t blocked anyone.'), findsOneWidget);
  });

  testWidgets('terms gate: must agree before entering; acceptance is saved', (
    tester,
  ) async {
    tall(tester);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await ensureCommunityTermsAccepted(context),
              child: const Text('enter'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('enter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('zero tolerance'), findsOneWidget);

    final accept = find.byKey(const ValueKey('community-terms-accept'));
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    // The agreement sits after the rules, so she scrolls past them first.
    await tester.ensureVisible(
      find.byKey(const ValueKey('community-terms-agree')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-terms-agree')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(find.textContaining('zero tolerance'), findsNothing);

    expect(result, isTrue);
    expect(repository.termsAccepted, isTrue);

    // Second entry: no dialog.
    result = null;
    await tester.tap(find.text('enter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('zero tolerance'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('terms gate: Not now keeps her out', (tester) async {
    tall(tester);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await ensureCommunityTermsAccepted(context),
              child: const Text('enter'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('enter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(repository.termsAccepted, isFalse);
  });

  testWidgets('guidelines screen states zero tolerance and how to report', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(
      const MaterialApp(home: CommunityGuidelinesScreen()),
    );
    expect(find.textContaining('zero tolerance'), findsOneWidget);
    expect(find.textContaining('within 24 hours'), findsOneWidget);
    expect(find.text('Contact us'), findsOneWidget);
  });

  testWidgets('moderation queue lists reports and applies an action', (
    tester,
  ) async {
    tall(tester);
    repository.queue.add(
      ModerationReport(
        reportId: 'r1',
        createdAt: DateTime.now().toUtc(),
        targetType: ReportTargetType.post,
        targetId: 'post-9',
        targetUserId: 'user-9',
        reason: ReportReason.hate,
        details: null,
        contentSnapshot: 'Offending text',
        openReportCount: 2,
        targetHidden: false,
        targetUserSuspended: false,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: ModerationQueueScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Offending text'), findsOneWidget);
    expect(find.textContaining('2 reports'), findsOneWidget);

    await tester.tap(find.text('Remove and suspend'));
    await tester.pumpAndSettle();
    expect(repository.resolutions.single.action, ModerationAction.suspendUser);
    expect(find.text('No open reports.'), findsOneWidget);
  });

  test('server refusals become plain-language messages', () {
    String message(String code) => communityErrorMessage(
      PostgrestException(message: 'x', code: code),
      StackTrace.current,
      context: 'test',
    );
    expect(message('NSW01'), contains('isn\'t allowed'));
    expect(message('NSW02'), contains('accept the community guidelines'));
    expect(message('NSW03'), contains('suspended'));
    expect(message('NSW04'), contains('can\'t interact'));
    // A wrapped messaging failure is recognised too.
    expect(
      communityErrorMessage(
        const PrivateMessagingException(
          'Failed to send message',
          cause: PostgrestException(message: 'x', code: 'NSW04'),
        ),
        StackTrace.current,
        context: 'test',
      ),
      contains('can\'t interact'),
    );
  });

  test('sign-out clears blocks and moderator flag', () async {
    repository.moderator = true;
    await repository.blockMember(userId: 'user-1');
    final controller = CommunitySafetyController.instance;
    await controller.load();
    expect(controller.isBlocked('user-1'), isTrue);
    expect(controller.isModerator, isTrue);
    controller.resetInMemory();
    expect(controller.isBlocked('user-1'), isFalse);
    expect(controller.isModerator, isFalse);
    expect(controller.termsAccepted, isNull);
  });
}

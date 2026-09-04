import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/community_feed_page.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';

class CommunityRepositoryImpl implements CommunityRepository {
  CommunityRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  static const String _postsTable = 'community_posts';
  static const String _commentsTable = 'community_comments';
  static const String _likesTable = 'community_likes';
  static const String _uniqueViolationCode = '23505';

  static String _t(String en, String ar) =>
      AppLocaleController.instance.text(en, ar);

  @override
  Future<CommunityFeedPage> getPosts({
    CommunityCategory? category,
    String? currentUserId,
    DateTime? beforeCreatedAt,
    int pageSize = 15,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackPage(category: category);
    }

    try {
      var query = client.from(_postsTable).select();
      if (category != null) {
        query = query.eq('category', category.name);
      }
      if (beforeCreatedAt != null) {
        query = query.lt('created_at', beforeCreatedAt.toIso8601String());
      }

      // Fetch one extra row to know whether another page remains, without a
      // separate count query.
      final response = await query
          .order('created_at', ascending: false)
          .limit(pageSize + 1);

      final rows = (response as List<dynamic>)
          .map(
            (item) => CommunityPost.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

      final hasMore = rows.length > pageSize;
      final pagePosts = hasMore ? rows.sublist(0, pageSize) : rows;
      if (pagePosts.isEmpty) {
        return const CommunityFeedPage(posts: [], hasMore: false);
      }

      final ids = pagePosts.map((post) => post.id).toList();

      // Batched counts — one query each for comments/likes across the whole
      // page, instead of a round-trip per post.
      final commentRows = await client
          .from(_commentsTable)
          .select('post_id')
          .inFilter('post_id', ids);
      final commentCounts = <String, int>{};
      for (final row in commentRows as List<dynamic>) {
        final postId = row['post_id'] as String;
        commentCounts[postId] = (commentCounts[postId] ?? 0) + 1;
      }

      final likeRows = await client
          .from(_likesTable)
          .select('post_id, user_id')
          .inFilter('post_id', ids);
      final likeCounts = <String, int>{};
      final likedByMe = <String>{};
      for (final row in likeRows as List<dynamic>) {
        final postId = row['post_id'] as String;
        likeCounts[postId] = (likeCounts[postId] ?? 0) + 1;
        if (currentUserId != null && row['user_id'] == currentUserId) {
          likedByMe.add(postId);
        }
      }

      final hydrated = pagePosts
          .map(
            (post) => post.copyWith(
              commentCount: commentCounts[post.id] ?? 0,
              likeCount: likeCounts[post.id] ?? 0,
              isLikedByCurrentUser: likedByMe.contains(post.id),
            ),
          )
          .toList();

      return CommunityFeedPage(posts: hydrated, hasMore: hasMore);
    } on PostgrestException catch (error, stack) {
      // A real backend error must never be masked as fabricated demo
      // content in the production path (AB-010) — the fallback above
      // (client == null) remains for the genuine "not configured / offline
      // preview" case only. Reported and propagated so the UI's existing
      // error state (already wired in community_feed_view_model.dart) shows
      // instead of fake posts. Uses the shared classifier (not an ad hoc
      // NetworkFailure(error.message)) so retryability/context/cause are
      // consistent with every other repository (AB-010/OB-007).
      final failure = mapRepositoryError(
        error,
        stack,
        context: 'CommunityRepositoryImpl.getPosts',
        userMessage: 'Could not load the community feed.',
      );
      AppErrorReporter.report(
        error,
        stack,
        context: failure.context,
        feature: 'community',
      );
      throw failure;
    }
  }

  @override
  Future<CommunityPost> createPost({
    required String userId,
    required String authorName,
    required CommunityPost post,
  }) async {
    final client = _client;
    if (client == null) {
      return post.copyWith(
        id: post.id.isEmpty
            ? 'community-post-${DateTime.now().millisecondsSinceEpoch}'
            : post.id,
        commentCount: 0,
        likeCount: 0,
        isLikedByCurrentUser: false,
      );
    }

    final payload = {
      'user_id': userId,
      'author_name': authorName,
      'title': post.title,
      'content': post.content,
      'category': post.category.name,
      'tags': post.tags,
      'is_anonymous': post.isAnonymous,
      'created_at': post.createdAt.toIso8601String(),
      'updated_at': post.createdAt.toIso8601String(),
    };

    final response = await client
        .from(_postsTable)
        .insert(payload)
        .select()
        .single();
    return CommunityPost.fromJson(Map<String, dynamic>.from(response)).copyWith(
      comments: const [],
      commentCount: 0,
      likeCount: 0,
      isLikedByCurrentUser: false,
    );
  }

  @override
  Future<List<CommunityComment>> getComments({required String postId}) async {
    final client = _client;
    if (client == null) {
      return _fallbackComments(postId: postId);
    }

    try {
      final response = await client
          .from(_commentsTable)
          .select()
          .eq('post_id', postId)
          .order('created_at', ascending: true);

      return (response as List<dynamic>)
          .map(
            (item) =>
                CommunityComment.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on PostgrestException catch (error, stack) {
      // Same principle as getPosts() above — see that comment.
      final failure = mapRepositoryError(
        error,
        stack,
        context: 'CommunityRepositoryImpl.getComments',
        userMessage: 'Could not load comments.',
      );
      AppErrorReporter.report(
        error,
        stack,
        context: failure.context,
        feature: 'community',
      );
      throw failure;
    }
  }

  @override
  Future<CommunityComment> addComment({
    required String postId,
    required String userId,
    required String authorName,
    required String content,
  }) async {
    final client = _client;
    if (client == null) {
      final createdAt = DateTime.now();
      return CommunityComment(
        id: 'comment-${createdAt.millisecondsSinceEpoch}',
        postId: postId,
        userId: userId,
        authorName: authorName,
        content: content,
        createdAt: createdAt,
      );
    }

    final payload = {
      'post_id': postId,
      'user_id': userId,
      'author_name': authorName,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    };

    final response = await client
        .from(_commentsTable)
        .insert(payload)
        .select()
        .single();
    return CommunityComment.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> deletePost({
    required String postId,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }

    await client
        .from(_postsTable)
        .delete()
        .eq('id', postId)
        .eq('user_id', userId);
  }

  @override
  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }

    await client
        .from(_commentsTable)
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId);
  }

  @override
  Future<void> likePost({
    required String postId,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.from(_likesTable).insert({
        'post_id': postId,
        'user_id': userId,
      });
    } on PostgrestException catch (error) {
      // Double-tap race: the like already exists — treat as success.
      if (error.code != _uniqueViolationCode) rethrow;
    }
  }

  @override
  Future<void> unlikePost({
    required String postId,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }

    await client
        .from(_likesTable)
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);
  }

  CommunityFeedPage _fallbackPage({CommunityCategory? category}) {
    final posts = _fallbackPosts(category: category);
    return CommunityFeedPage(posts: posts, hasMore: false);
  }

  List<CommunityPost> _fallbackPosts({CommunityCategory? category}) {
    final posts = [
      CommunityPost(
        id: 'community-post-1',
        userId: 'user-1',
        authorName: _t('Alya', 'ألاء'),
        title: _t(
          'Need gentle encouragement for my prayer routine',
          'أحتاج تشجيعاً لطيفاً للحفاظ على صلاتي',
        ),
        content: _t(
          'I have been trying to keep a steady rhythm, but some days feel heavier than others. I would love support and simple routines that are realistic for busy weeks.',
          'أحاول الحفاظ على انتظام صلاتي، لكن بعض الأيام تكون أثقل من غيرها. أتمنى الدعم وبعض الروتينات البسيطة الواقعية للأسابيع المزدحمة.',
        ),
        category: CommunityCategory.prayer,
        tags: [_t('routine', 'روتين'), _t('support', 'دعم')],
        isAnonymous: false,
        createdAt: DateTime(2026, 8, 18, 8, 15),
        commentCount: 1,
        likeCount: 6,
        comments: [
          CommunityComment(
            id: 'community-comment-1',
            postId: 'community-post-1',
            userId: 'user-2',
            authorName: _t('Huda', 'هدى'),
            content: _t(
              'A realistic routine is enough. Start with the next prayer, not the whole day.',
              'روتين واقعي يكفي. ابدئي بالصلاة القادمة فقط، لا باليوم كاملاً.',
            ),
            createdAt: DateTime(2026, 8, 18, 8, 30),
          ),
        ],
      ),
      CommunityPost(
        id: 'community-post-2',
        userId: 'user-3',
        authorName: _t('Sara', 'سارة'),
        title: _t(
          'Sharing a calm wellness reset for the week',
          'أشارككنّ روتين صحياً هادئاً لهذا الأسبوع',
        ),
        content: _t(
          'This week I am focusing on hydration, walking, and a more gentle sleep routine. I would love reminders and accountability from others.',
          'هذا الأسبوع أركّز على شرب الماء والمشي ونوم أكثر انتظاماً. أحب لو ذكّرتنّني وتابعتنّ معي.',
        ),
        category: CommunityCategory.wellness,
        tags: [_t('energy', 'طاقة'), _t('sleep', 'نوم')],
        isAnonymous: false,
        createdAt: DateTime(2026, 8, 17, 21, 0),
        commentCount: 1,
        likeCount: 9,
        comments: [
          CommunityComment(
            id: 'community-comment-2',
            postId: 'community-post-2',
            userId: 'user-4',
            authorName: _t('Nour', 'نور'),
            content: _t(
              'Small consistent actions can create a lot of steadiness.',
              'الخطوات الصغيرة المستمرة تصنع استقراراً كبيراً.',
            ),
            createdAt: DateTime(2026, 8, 17, 21, 15),
          ),
        ],
      ),
      CommunityPost(
        id: 'community-post-3',
        userId: 'user-5',
        authorName: _t('Community member', 'عضو في المجتمع'),
        title: _t(
          'Feeling anxious most evenings lately',
          'أشعر بالقلق في معظم الأمسيات مؤخراً',
        ),
        content: _t(
          'Nothing serious happened, I just feel a knot in my chest after sunset. Would love to hear how others wind down.',
          'لا يوجد سبب واضح، فقط أشعر بضيق في صدري بعد المغرب. أحب أن أسمع كيف تهدّئن أنفسكنّ في المساء.',
        ),
        category: CommunityCategory.support,
        tags: [_t('anxiety', 'قلق')],
        isAnonymous: true,
        createdAt: DateTime(2026, 8, 19, 19, 40),
        commentCount: 0,
        likeCount: 4,
      ),
      CommunityPost(
        id: 'community-post-4',
        userId: 'user-6',
        authorName: _t('Mona', 'منى'),
        title: _t(
          'Toddler bedtime battles — any gentle tips?',
          'صعوبات وقت نوم الطفلة — أي نصائح لطيفة؟',
        ),
        content: _t(
          'My daughter has started resisting bedtime hard this month. Looking for calm, non-punitive ideas that actually worked for you.',
          'ابنتي بدأت ترفض النوم بشدة هذا الشهر. أبحث عن أفكار هادئة وغير عقابية نجحت معكنّ فعلاً.',
        ),
        category: CommunityCategory.parenting,
        tags: [_t('toddlers', 'الأطفال الصغار'), _t('bedtime', 'وقت النوم')],
        isAnonymous: false,
        createdAt: DateTime(2026, 8, 16, 20, 5),
        commentCount: 0,
        likeCount: 7,
      ),
      CommunityPost(
        id: 'community-post-5',
        userId: 'user-7',
        authorName: _t('Community member', 'عضو في المجتمع'),
        title: _t(
          'Two years trying to conceive — feeling isolated',
          'سنتان من المحاولة للحمل — أشعر بالعزلة',
        ),
        content: _t(
          'Most of my friends have kids already and I do not know how to talk about this without it becoming heavy. Just wanted to say it somewhere safe.',
          'معظم صديقاتي أصبح لديهنّ أطفال، ولا أعرف كيف أتحدث عن هذا دون أن يصبح الأمر ثقيلاً. أردت فقط أن أقولها في مكان آمن.',
        ),
        category: CommunityCategory.fertility,
        tags: [_t('ttc', 'محاولة الحمل')],
        isAnonymous: true,
        createdAt: DateTime(2026, 8, 15, 22, 30),
        commentCount: 0,
        likeCount: 11,
      ),
      CommunityPost(
        id: 'community-post-6',
        userId: 'user-8',
        authorName: _t('Reem', 'ريم'),
        title: _t(
          'What is one small thing that made your week better?',
          'ما هو الشيء الصغير الذي جعل أسبوعك أفضل؟',
        ),
        content: _t(
          'Trying to collect small wins from this community — mine was finally organizing my kitchen drawer. What is yours?',
          'أحاول جمع انتصارات صغيرة من هذا المجتمع — انتصاري كان ترتيب درج مطبخي أخيراً. ما هو انتصارك؟',
        ),
        category: CommunityCategory.general,
        tags: const [],
        isAnonymous: false,
        createdAt: DateTime(2026, 8, 14, 12, 0),
        commentCount: 0,
        likeCount: 3,
      ),
    ];

    return category == null
        ? posts
        : posts.where((post) => post.category == category).toList();
  }

  List<CommunityComment> _fallbackComments({required String postId}) {
    if (postId == 'community-post-1') {
      return [
        CommunityComment(
          id: 'community-comment-1',
          postId: 'community-post-1',
          userId: 'user-2',
          authorName: _t('Huda', 'هدى'),
          content: _t(
            'A realistic routine is enough. Start with the next prayer, not the whole day.',
            'روتين واقعي يكفي. ابدئي بالصلاة القادمة فقط، لا باليوم كاملاً.',
          ),
          createdAt: DateTime(2026, 8, 18, 8, 30),
        ),
      ];
    }
    if (postId == 'community-post-2') {
      return [
        CommunityComment(
          id: 'community-comment-2',
          postId: 'community-post-2',
          userId: 'user-4',
          authorName: _t('Nour', 'نور'),
          content: _t(
            'Small consistent actions can create a lot of steadiness.',
            'الخطوات الصغيرة المستمرة تصنع استقراراً كبيراً.',
          ),
          createdAt: DateTime(2026, 8, 17, 21, 15),
        ),
      ];
    }
    return const <CommunityComment>[];
  }
}

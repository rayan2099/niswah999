import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/community/domain/entities/community_comment.dart';
import 'package:niswah/features/community/domain/entities/community_feed_page.dart';
import 'package:niswah/features/community/domain/entities/community_post.dart';
import 'package:niswah/features/community/domain/repositories/community_repository.dart';
import 'package:niswah/features/community/presentation/viewmodels/community_feed_view_model.dart';
import 'package:niswah/features/community/presentation/viewmodels/post_detail_view_model.dart';

/// Fails the first call, then succeeds — simulating a client-side timeout
/// where the caller doesn't know whether the first attempt actually
/// reached the server. Captures every id it was called with so a test can
/// assert whether a retry reused the same id or generated a new one
/// (RR-001 idempotency audit: `createPost`/`addComment` previously used a
/// bare `.insert()` with no client-supplied id, so a manual retry after a
/// timeout could create a duplicate row).
class _FailOnceThenSucceedRepository implements CommunityRepository {
  int _createPostCalls = 0;
  int _addCommentCalls = 0;
  final List<String> postIdsSeen = [];
  final List<String?> commentIdsSeen = [];

  @override
  Future<CommunityPost> createPost({
    required String userId,
    required String authorName,
    required CommunityPost post,
  }) async {
    postIdsSeen.add(post.id);
    _createPostCalls++;
    if (_createPostCalls == 1) {
      throw Exception('simulated timeout');
    }
    return post;
  }

  @override
  Future<CommunityComment> addComment({
    required String postId,
    required String userId,
    required String authorName,
    required String content,
    String? commentId,
  }) async {
    commentIdsSeen.add(commentId);
    _addCommentCalls++;
    if (_addCommentCalls == 1) {
      throw Exception('simulated timeout');
    }
    return CommunityComment(
      id: commentId ?? 'fallback-id',
      postId: postId,
      userId: userId,
      authorName: authorName,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<CommunityFeedPage> getPosts({
    CommunityCategory? category,
    String? currentUserId,
    DateTime? beforeCreatedAt,
    int pageSize = 15,
  }) async => const CommunityFeedPage(posts: [], hasMore: false);

  @override
  Future<List<CommunityComment>> getComments({required String postId}) async =>
      [];

  @override
  Future<void> deletePost({
    required String postId,
    required String userId,
  }) async {}

  @override
  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {}

  @override
  Future<void> likePost({
    required String postId,
    required String userId,
  }) async {}

  @override
  Future<void> unlikePost({
    required String postId,
    required String userId,
  }) async {}
}

void main() {
  group('CommunityFeedViewModel.createPost idempotency (RR-001)', () {
    test(
      'a manual retry after a failed submit reuses the same post id, '
      'not a fresh one — so retrying does not risk a duplicate row',
      () async {
        final repository = _FailOnceThenSucceedRepository();
        final viewModel = CommunityFeedViewModel(
          repository: repository,
          currentUserId: 'user-1',
          currentUserName: 'Test User',
        );

        final firstAttempt = await viewModel.createPost(
          content: 'hello world',
          category: CommunityCategory.general,
        );
        expect(firstAttempt, isFalse, reason: 'first attempt simulates a timeout');

        final secondAttempt = await viewModel.createPost(
          content: 'hello world',
          category: CommunityCategory.general,
        );
        expect(secondAttempt, isTrue, reason: 'retry succeeds');

        expect(repository.postIdsSeen, hasLength(2));
        expect(
          repository.postIdsSeen[0],
          repository.postIdsSeen[1],
          reason: 'a retry of the same logical post must reuse the same id',
        );
      },
    );

    test(
      'a new post after a successful submit gets a fresh id, not the '
      'previous post\'s id',
      () async {
        final repository = _FailOnceThenSucceedRepository();
        // Prime past the simulated first-call failure so both real posts
        // below succeed on their first try.
        repository._createPostCalls = 1;

        final viewModel = CommunityFeedViewModel(
          repository: repository,
          currentUserId: 'user-1',
          currentUserName: 'Test User',
        );

        await viewModel.createPost(
          content: 'first post',
          category: CommunityCategory.general,
        );
        await viewModel.createPost(
          content: 'second post',
          category: CommunityCategory.general,
        );

        expect(repository.postIdsSeen, hasLength(2));
        expect(
          repository.postIdsSeen[0],
          isNot(repository.postIdsSeen[1]),
          reason: 'two genuinely different posts must not share an id',
        );
      },
    );
  });

  group('PostDetailViewModel.addComment idempotency (RR-001)', () {
    CommunityPost samplePost() => CommunityPost(
      id: 'post-1',
      userId: 'author-1',
      authorName: 'Author',
      title: 'Title',
      content: 'Content',
      category: CommunityCategory.general,
      tags: const [],
      isAnonymous: false,
      createdAt: DateTime.now(),
    );

    test(
      'a manual retry after a failed comment submit reuses the same '
      'comment id',
      () async {
        final repository = _FailOnceThenSucceedRepository();
        final viewModel = PostDetailViewModel(
          repository: repository,
          initialPost: samplePost(),
          currentUserId: 'user-1',
          currentUserName: 'Test User',
        );

        final firstAttempt = await viewModel.addComment('hello');
        expect(firstAttempt, isFalse);
        final secondAttempt = await viewModel.addComment('hello');
        expect(secondAttempt, isTrue);

        expect(repository.commentIdsSeen, hasLength(2));
        expect(repository.commentIdsSeen[0], isNotNull);
        expect(
          repository.commentIdsSeen[0],
          repository.commentIdsSeen[1],
          reason: 'a retry of the same logical comment must reuse the same id',
        );
      },
    );

    test(
      'a new comment after a successful submit gets a fresh id',
      () async {
        final repository = _FailOnceThenSucceedRepository();
        repository._addCommentCalls = 1;

        final viewModel = PostDetailViewModel(
          repository: repository,
          initialPost: samplePost(),
          currentUserId: 'user-1',
          currentUserName: 'Test User',
        );

        await viewModel.addComment('first comment');
        await viewModel.addComment('second comment');

        expect(repository.commentIdsSeen, hasLength(2));
        expect(
          repository.commentIdsSeen[0],
          isNot(repository.commentIdsSeen[1]),
        );
      },
    );
  });
}

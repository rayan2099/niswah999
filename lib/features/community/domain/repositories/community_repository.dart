import '../entities/community_comment.dart';
import '../entities/community_feed_page.dart';
import '../entities/community_post.dart';

abstract class CommunityRepository {
  Future<CommunityFeedPage> getPosts({
    CommunityCategory? category,
    String? currentUserId,
    DateTime? beforeCreatedAt,
    int pageSize = 15,
  });

  Future<CommunityPost> createPost({
    required String userId,
    required String authorName,
    required CommunityPost post,
  });

  Future<List<CommunityComment>> getComments({required String postId});

  /// [commentId], when supplied, must be a stable id generated once by the
  /// caller and reused across manual retries of the same submit — see
  /// [CommunityFeedViewModel]'s `_pendingPostId` for the identical pattern
  /// on `createPost`. Falls back to a fresh id if omitted.
  Future<CommunityComment> addComment({
    required String postId,
    required String userId,
    required String authorName,
    required String content,
    String? commentId,
  });

  Future<void> deletePost({required String postId, required String userId});

  Future<void> deleteComment({
    required String commentId,
    required String userId,
  });

  Future<void> likePost({required String postId, required String userId});

  Future<void> unlikePost({required String postId, required String userId});
}

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

  Future<CommunityComment> addComment({
    required String postId,
    required String userId,
    required String authorName,
    required String content,
  });

  Future<void> deletePost({required String postId, required String userId});

  Future<void> deleteComment({
    required String commentId,
    required String userId,
  });

  Future<void> likePost({required String postId, required String userId});

  Future<void> unlikePost({required String postId, required String userId});
}

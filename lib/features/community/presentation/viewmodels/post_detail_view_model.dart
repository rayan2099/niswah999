import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/community_repository_impl.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';
import 'community_error_message.dart';

class PostDetailViewModel extends ChangeNotifier {
  PostDetailViewModel({
    CommunityRepository? repository,
    required CommunityPost initialPost,
    required this.currentUserId,
    required this.currentUserName,
  }) : _repository = repository ?? CommunityRepositoryImpl(),
       post = initialPost;

  final CommunityRepository _repository;
  final String? currentUserId;
  final String currentUserName;

  CommunityPost post;
  List<CommunityComment> comments = const <CommunityComment>[];
  bool isLoadingComments = false;
  bool isSubmittingComment = false;
  String? errorMessage;

  Future<void> loadComments() async {
    isLoadingComments = true;
    notifyListeners();
    try {
      comments = await _repository.getComments(postId: post.id);
    } catch (error, stack) {
      errorMessage = communityErrorMessage(
        error,
        stack,
        context: 'PostDetailViewModel.loadComments',
      );
    } finally {
      isLoadingComments = false;
      notifyListeners();
    }
  }

  /// Stable id for the comment currently being submitted, reused across
  /// manual retries of the same submit so a retry after a timeout upserts
  /// the same row instead of creating a duplicate comment — same pattern
  /// as `CommunityFeedViewModel._pendingPostId`.
  String? _pendingCommentId;

  Future<bool> addComment(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > 500) {
      errorMessage = 'Comments can be up to 500 characters.';
      notifyListeners();
      return false;
    }
    final userId = currentUserId ?? 'demo-user';
    final commentId = _pendingCommentId ??= const Uuid().v4();

    isSubmittingComment = true;
    errorMessage = null;
    notifyListeners();

    try {
      final comment = await _repository.addComment(
        postId: post.id,
        userId: userId,
        authorName: currentUserName,
        content: trimmed,
        commentId: commentId,
      );
      comments = [...comments, comment];
      post = post.copyWith(commentCount: post.commentCount + 1);
      _pendingCommentId = null;
      return true;
    } catch (error, stack) {
      errorMessage = communityErrorMessage(
        error,
        stack,
        context: 'PostDetailViewModel.addComment',
      );
      return false;
    } finally {
      isSubmittingComment = false;
      notifyListeners();
    }
  }

  Future<void> deleteComment(String commentId) async {
    final userId = currentUserId;
    if (userId == null) return;

    final previous = comments;
    comments = comments.where((comment) => comment.id != commentId).toList();
    post = post.copyWith(commentCount: post.commentCount - 1);
    notifyListeners();

    try {
      await _repository.deleteComment(commentId: commentId, userId: userId);
    } catch (_) {
      comments = previous;
      post = post.copyWith(commentCount: post.commentCount + 1);
      notifyListeners();
    }
  }

  Future<void> toggleLike() async {
    final userId = currentUserId;
    if (userId == null) return;

    final original = post;
    post = post.copyWith(
      isLikedByCurrentUser: !post.isLikedByCurrentUser,
      likeCount: post.isLikedByCurrentUser
          ? post.likeCount - 1
          : post.likeCount + 1,
    );
    notifyListeners();

    try {
      if (post.isLikedByCurrentUser) {
        await _repository.likePost(postId: post.id, userId: userId);
      } else {
        await _repository.unlikePost(postId: post.id, userId: userId);
      }
    } catch (_) {
      post = original;
      notifyListeners();
    }
  }

  Future<bool> deletePost() async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      await _repository.deletePost(postId: post.id, userId: userId);
      return true;
    } catch (error, stack) {
      errorMessage = communityErrorMessage(
        error,
        stack,
        context: 'PostDetailViewModel.deletePost',
      );
      notifyListeners();
      return false;
    }
  }
}

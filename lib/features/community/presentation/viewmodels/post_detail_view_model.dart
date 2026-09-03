import 'package:flutter/foundation.dart';

import '../../data/repositories/community_repository_impl.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';

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
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoadingComments = false;
      notifyListeners();
    }
  }

  Future<bool> addComment(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > 500) {
      errorMessage = 'Comments can be up to 500 characters.';
      notifyListeners();
      return false;
    }
    final userId = currentUserId ?? 'demo-user';

    isSubmittingComment = true;
    errorMessage = null;
    notifyListeners();

    try {
      final comment = await _repository.addComment(
        postId: post.id,
        userId: userId,
        authorName: currentUserName,
        content: trimmed,
      );
      comments = [...comments, comment];
      post = post.copyWith(commentCount: post.commentCount + 1);
      return true;
    } catch (error) {
      errorMessage = error.toString();
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
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
      return false;
    }
  }
}

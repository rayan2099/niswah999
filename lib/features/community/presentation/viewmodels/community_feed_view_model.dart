import 'package:flutter/foundation.dart';

import '../../data/repositories/community_repository_impl.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_repository.dart';

class CommunityFeedViewModel extends ChangeNotifier {
  CommunityFeedViewModel({
    CommunityRepository? repository,
    required this.currentUserId,
    required this.currentUserName,
  }) : _repository = repository ?? CommunityRepositoryImpl();

  final CommunityRepository _repository;

  /// The signed-in user's id, or null in offline/demo mode.
  String? currentUserId;

  /// A display name to use when creating posts/comments — resolved by the
  /// screen (falls back to the localized "Community member" string).
  String currentUserName;

  static const int _pageSize = 15;

  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = true;
  bool isSubmitting = false;
  String? errorMessage;
  CommunityCategory? selectedCategory;
  List<CommunityPost> posts = const <CommunityPost>[];

  DateTime? _cursor;

  Future<void> loadPosts() async {
    isLoading = true;
    errorMessage = null;
    _cursor = null;
    hasMore = true;
    notifyListeners();

    try {
      final page = await _repository.getPosts(
        category: selectedCategory,
        currentUserId: currentUserId,
        pageSize: _pageSize,
      );
      posts = page.posts;
      hasMore = page.hasMore;
      _cursor = posts.isEmpty ? null : posts.last.createdAt;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore || _cursor == null) return;

    isLoadingMore = true;
    notifyListeners();

    try {
      final page = await _repository.getPosts(
        category: selectedCategory,
        currentUserId: currentUserId,
        pageSize: _pageSize,
        beforeCreatedAt: _cursor,
      );
      posts = [...posts, ...page.posts];
      hasMore = page.hasMore;
      if (page.posts.isNotEmpty) {
        _cursor = page.posts.last.createdAt;
      } else {
        hasMore = false;
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  void selectCategory(CommunityCategory? category) {
    selectedCategory = category;
    loadPosts();
  }

  Future<bool> createPost({
    String? title,
    required String content,
    required CommunityCategory category,
    List<String>? tags,
    bool isAnonymous = false,
  }) async {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      errorMessage = 'Please write a short message before posting.';
      notifyListeners();
      return false;
    }
    if (trimmedContent.length > 1000) {
      errorMessage = 'Posts can be up to 1000 characters.';
      notifyListeners();
      return false;
    }
    // Title is optional: fall back to the first line of the content.
    var trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isEmpty) {
      final newline = String.fromCharCode(10);
      final firstLine = trimmedContent.split(newline).first.trim();
      trimmedTitle = firstLine.length > 60
          ? '${firstLine.substring(0, 60)}…'
          : firstLine;
    }
    if (trimmedTitle.length > 80) {
      errorMessage = 'Titles can be up to 80 characters.';
      notifyListeners();
      return false;
    }

    final userId = currentUserId ?? 'demo-user';

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final created = await _repository.createPost(
        userId: userId,
        authorName: currentUserName,
        post: CommunityPost(
          id: '',
          userId: userId,
          authorName: currentUserName,
          title: trimmedTitle,
          content: trimmedContent,
          category: category,
          tags: tags ?? const <String>[],
          isAnonymous: isAnonymous,
          createdAt: DateTime.now(),
        ),
      );

      posts = [created, ...posts];
      return true;
    } catch (error) {
      errorMessage = error.toString();
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> toggleLike(String postId) async {
    final index = posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;
    final userId = currentUserId;
    if (userId == null) return;

    final original = posts[index];
    final optimistic = original.copyWith(
      isLikedByCurrentUser: !original.isLikedByCurrentUser,
      likeCount: original.isLikedByCurrentUser
          ? original.likeCount - 1
          : original.likeCount + 1,
    );
    posts = [...posts]..[index] = optimistic;
    notifyListeners();

    try {
      if (optimistic.isLikedByCurrentUser) {
        await _repository.likePost(postId: postId, userId: userId);
      } else {
        await _repository.unlikePost(postId: postId, userId: userId);
      }
    } catch (_) {
      // Revert on failure.
      final revertIndex = posts.indexWhere((post) => post.id == postId);
      if (revertIndex != -1) {
        posts = [...posts]..[revertIndex] = original;
        notifyListeners();
      }
    }
  }

  Future<void> deletePost(String postId) async {
    final userId = currentUserId;
    if (userId == null) return;

    final previous = posts;
    posts = posts.where((post) => post.id != postId).toList();
    notifyListeners();

    try {
      await _repository.deletePost(postId: postId, userId: userId);
    } catch (_) {
      posts = previous;
      notifyListeners();
    }
  }

  /// Keeps the list's comment count in sync after adding/removing a comment
  /// from the detail screen, without a full reload.
  void bumpCommentCount(String postId, {int delta = 1}) {
    final index = posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;
    posts = [...posts]
      ..[index] = posts[index].copyWith(
        commentCount: posts[index].commentCount + delta,
      );
    notifyListeners();
  }
}

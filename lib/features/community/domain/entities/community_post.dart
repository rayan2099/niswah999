import 'package:equatable/equatable.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/community_language_controller.dart';
import 'community_comment.dart';
import '../../../../core/utils/db_timestamp.dart';

enum CommunityCategory {
  support,
  prayer,
  wellness,
  parenting,
  fertility,
  general,
}

class CommunityPost extends Equatable {
  const CommunityPost({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.title,
    required this.content,
    required this.category,
    required this.tags,
    required this.isAnonymous,
    required this.createdAt,
    required this.language,
    this.comments = const <CommunityComment>[],
    this.commentCount = 0,
    this.likeCount = 0,
    this.isLikedByCurrentUser = false,
  });

  final String id;
  final String userId;
  final String authorName;
  final String title;
  final String content;
  final CommunityCategory category;
  final List<String> tags;
  final bool isAnonymous;
  final DateTime createdAt;

  /// Which community (Requirement 4) this post belongs to — Arabic or
  /// English. Never auto-translated/mixed across the two: a post always
  /// belongs to exactly the community it was created in.
  final CommunityLanguage language;

  /// Full comment thread — only populated when a post is loaded standalone
  /// by the detail screen. List/feed pages leave this empty and rely on
  /// [commentCount] instead, to avoid an N+1 fetch per post.
  final List<CommunityComment> comments;

  /// Total comment count, populated via a batched query on the feed.
  final int commentCount;

  /// Total like count, populated via a batched query on the feed.
  final int likeCount;

  /// Whether the current user has liked this post.
  final bool isLikedByCurrentUser;

  CommunityPost copyWith({
    String? id,
    String? userId,
    String? authorName,
    String? title,
    String? content,
    CommunityCategory? category,
    List<String>? tags,
    bool? isAnonymous,
    DateTime? createdAt,
    CommunityLanguage? language,
    List<CommunityComment>? comments,
    int? commentCount,
    int? likeCount,
    bool? isLikedByCurrentUser,
  }) {
    return CommunityPost(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt ?? this.createdAt,
      language: language ?? this.language,
      comments: comments ?? this.comments,
      commentCount: commentCount ?? this.commentCount,
      likeCount: likeCount ?? this.likeCount,
      isLikedByCurrentUser: isLikedByCurrentUser ?? this.isLikedByCurrentUser,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'author_name': authorName,
    'title': title,
    'content': content,
    'category': category.name,
    'tags': tags,
    'is_anonymous': isAnonymous,
    'created_at': dbTimestamp(createdAt),
    'language': language.name,
    'comments': comments.map((comment) => comment.toJson()).toList(),
  };

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'];

    return CommunityPost(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      authorName:
          json['author_name'] as String? ??
          AppLocaleController.instance.text(
            'Community member',
            'عضو في المجتمع',
          ),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      category: CommunityCategory.values.firstWhere(
        (category) =>
            category.name == (json['category'] as String? ?? 'general'),
        orElse: () => CommunityCategory.general,
      ),
      tags: List<String>.from(json['tags'] as List? ?? const <String>[]),
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      // Defensive fallback only — the DB column is NOT NULL, so this is
      // never relied on for a real row; it only guards against a
      // malformed/partial map in a test fixture.
      language: CommunityLanguage.values.firstWhere(
        (lang) => lang.name == (json['language'] as String? ?? 'ar'),
        orElse: () => CommunityLanguage.ar,
      ),
      comments: rawComments is List
          ? rawComments
                .map(
                  (item) => CommunityComment.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const <CommunityComment>[],
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    authorName,
    title,
    content,
    category,
    tags,
    isAnonymous,
    createdAt,
    language,
    comments,
    commentCount,
    likeCount,
    isLikedByCurrentUser,
  ];
}

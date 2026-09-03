import 'package:equatable/equatable.dart';

import '../../../../core/localization/app_locale_controller.dart';

class CommunityComment extends Equatable {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String userId;
  final String authorName;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'user_id': userId,
    'author_name': authorName,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: json['id'] as String? ?? '',
      postId: json['post_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      authorName:
          json['author_name'] as String? ??
          AppLocaleController.instance.text(
            'Community member',
            'عضو في المجتمع',
          ),
      content: json['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    postId,
    userId,
    authorName,
    content,
    createdAt,
  ];
}

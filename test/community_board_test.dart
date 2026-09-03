import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/community/domain/entities/community_comment.dart';
import 'package:niswah/features/community/domain/entities/community_post.dart';

void main() {
  group('Community board models', () {
    test('serializes and deserializes a community post', () {
      final now = DateTime(2026, 8, 18, 9, 30);
      final post = CommunityPost(
        id: 'post-1',
        userId: 'user-1',
        authorName: 'Noura',
        title: 'Seeking support for low energy',
        content: 'I am feeling overwhelmed and would love encouragement.',
        category: CommunityCategory.support,
        tags: const ['energy', 'support'],
        isAnonymous: false,
        createdAt: now,
      );

      final json = post.toJson();
      final restored = CommunityPost.fromJson(json);

      expect(restored.id, 'post-1');
      expect(restored.authorName, 'Noura');
      expect(restored.category, CommunityCategory.support);
      expect(restored.tags, ['energy', 'support']);
      expect(restored.content, 'I am feeling overwhelmed and would love encouragement.');
    });

    test('serializes and deserializes a comment', () {
      final now = DateTime(2026, 8, 18, 9, 35);
      final comment = CommunityComment(
        id: 'comment-1',
        postId: 'post-1',
        userId: 'user-2',
        authorName: 'Huda',
        content: 'You are not alone. Take it one moment at a time.',
        createdAt: now,
      );

      final json = comment.toJson();
      final restored = CommunityComment.fromJson(json);

      expect(restored.postId, 'post-1');
      expect(restored.authorName, 'Huda');
      expect(restored.content, 'You are not alone. Take it one moment at a time.');
    });
  });
}

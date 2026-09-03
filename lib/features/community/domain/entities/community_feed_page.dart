import 'community_post.dart';

/// One page of the community feed, plus whether older posts remain.
class CommunityFeedPage {
  const CommunityFeedPage({required this.posts, required this.hasMore});

  final List<CommunityPost> posts;
  final bool hasMore;
}

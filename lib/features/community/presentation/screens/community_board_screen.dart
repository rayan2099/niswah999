import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/load_error_banner.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../private_messaging/domain/repositories/private_messaging_repository_base.dart';
import '../../../private_messaging/presentation/screens/chat_detail_screen.dart';
import '../../../private_messaging/presentation/screens/conversations_screen.dart';
import '../../../private_messaging/presentation/viewmodels/conversations_view_model.dart';
import '../../../private_messaging/presentation/widgets/unread_messages_badge.dart';
import '../../../private_messaging/private_messaging_locator.dart';
import '../../domain/entities/community_post.dart';
import '../community_palette.dart';
import '../viewmodels/community_feed_view_model.dart';
import '../widgets/community_category_chip_bar.dart';
import '../widgets/community_composer_sheet.dart';
import '../widgets/community_post_card.dart';
import 'post_detail_screen.dart';

String _co(String en, String ar) => AppLocaleController.instance.text(en, ar);

class CommunityBoardScreen extends StatefulWidget {
  const CommunityBoardScreen({super.key});
  @override
  State<CommunityBoardScreen> createState() => _CommunityBoardScreenState();
}

class _CommunityBoardScreenState extends State<CommunityBoardScreen> {
  late final CommunityFeedViewModel _viewModel;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _badgeRefresh = 0;
  Timer? _searchDebounce;

  // Rebuilding the whole feed on every keystroke (via setState) made typing
  // in the search field feel laggy. Debouncing means the TextField's own
  // display still updates instantly (Flutter handles that internally), but
  // the expensive feed re-filter only runs once typing pauses.
  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() {}),
    );
  }

  String? get _currentUserId =>
      NiswahSupabase.clientOrNull?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _viewModel = CommunityFeedViewModel(
      currentUserId: _currentUserId,
      currentUserName: _co('Community member', 'عضو في المجتمع'),
    )..loadPosts();
    _resolveDisplayName();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveDisplayName() async {
    try {
      final user = await AuthRepositoryImpl().currentUser;
      final name = user?.displayName?.trim();
      if (mounted && name != null && name.isNotEmpty) {
        setState(() => _viewModel.currentUserName = name);
      }
    } catch (_) {
      // Keep the localized fallback name already set.
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 400;
    if (_scrollController.position.pixels >= threshold) {
      _viewModel.loadMore();
    }
  }

  /// Resolves the messaging repository — always the real, Supabase-backed
  /// one. **No demo-mode/mock fallback here** (PJ-005/CQ-007): this screen
  /// is only reachable from inside `NiswahHomeShell`, which the root
  /// router (`main.dart`) already gates behind `AuthController.isAuthenticated`
  /// — a genuinely unauthenticated user is shown `SignInScreen` before
  /// ever reaching this screen at all. `_currentUserId == null` here can
  /// therefore only mean a session that was valid a moment ago has since
  /// died (token expiry, a dropped refresh, an auth bug) — not a
  /// deliberate "browse without an account" state. Silently substituting
  /// fabricated named-contact conversations in that case previously gave
  /// no indication anything was wrong; callers now check for this
  /// explicitly (see `_requireSignedIn`) and show an honest prompt instead
  /// of ever calling this getter with no session.
  PrivateMessagingRepositoryBase get _messagingRepository =>
      privateMessagingRepository;

  /// Returns the signed-in user id, or shows an honest "please sign in"
  /// message and returns `null` if the session has died — never silently
  /// substitutes fabricated content (PJ-005/CQ-007).
  String? _requireSignedIn() {
    final userId = _currentUserId;
    if (userId != null) return userId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _co(
            'Your session has ended. Please sign in again to use messaging.',
            'انتهت جلستكِ. يُرجى تسجيل الدخول مرة أخرى لاستخدام الرسائل.',
          ),
        ),
      ),
    );
    return null;
  }

  void _openPrivateMessages() {
    final userId = _requireSignedIn();
    if (userId == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationsScreen(
              viewModel: ConversationsViewModel(
                repository: _messagingRepository,
                currentUserId: userId,
              ),
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _badgeRefresh++);
        });
    // Rebuild on return so the unread badge refreshes.
  }

  Future<void> _messagePostAuthor(CommunityPost post) async {
    final userId = _requireSignedIn();
    if (userId == null) return;
    if (userId == post.userId) return;
    try {
      final conversation = await _messagingRepository.getOrCreateConversation(
        userId,
        post.userId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatDetailScreen(
            conversation: conversation,
            currentUserId: userId,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _co(
              'Could not open a conversation with this author.',
              'تعذر فتح محادثة مع هذا العضو.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openPost(CommunityPost post) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PostDetailScreen(
          post: post,
          currentUserId: _currentUserId,
          currentUserName: _viewModel.currentUserName,
          feedViewModel: _viewModel,
          onMessageAuthor:
              !post.isAnonymous && post.userId != (_currentUserId ?? 'You')
              ? () => _messagePostAuthor(post)
              : null,
          onAuthorTap: post.isAnonymous ? null : () => _openMemberPreview(post),
        ),
      ),
    );
    if (result == true) {
      _viewModel.loadPosts();
    }
  }

  void _openMemberPreview(CommunityPost post) {
    final isOwnPost = post.userId == _currentUserId;
    final visiblePostCount = _viewModel.posts
        .where((item) => !item.isAnonymous && item.userId == post.userId)
        .length;
    final palette = CommunityPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBlush = isDark ? const Color(0xFF32171D) : Colors.white;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.background,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(displayName: post.authorName, size: 64, dark: isDark),
              const SizedBox(height: 12),
              Text(
                post.authorName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: palette.blushStrong,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _co(
                  '$visiblePostCount public posts in your current feed',
                  '$visiblePostCount منشورات عامة في صفحتك الحالية',
                ),
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.blush.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: palette.blush),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _co(
                          'Keep conversations respectful and protect personal information.',
                          'حافظي على الاحترام وخصوصية المعلومات الشخصية.',
                        ),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOwnPost) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _messagePostAuthor(post);
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text(_co('Send a message', 'إرسال رسالة')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: palette.blush,
                    foregroundColor: onBlush,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _viewModel,
    builder: (context, _) {
      final palette = CommunityPalette.of(context);
      final query = _searchController.text.trim().toLowerCase();
      final posts = _viewModel.posts
          .where(
            (post) =>
                query.isEmpty ||
                post.title.toLowerCase().contains(query) ||
                post.content.toLowerCase().contains(query),
          )
          .toList();
      return Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _viewModel.loadPosts,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _co('Community', 'المجتمع'),
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: palette.blushStrong,
                                fontFamily: AppTypography.serifFamily,
                                fontSize: 40,
                                height: 1.2,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Text(
                            _co(
                              'Share a question or experience without revealing your identity. Content here is for support, not a replacement for a doctor or scholar.',
                              'شاركي سؤالاً أو تجربة دون كشف هويتكِ. المحتوى هنا للدعم وليس بديلاً عن الطبيبة أو العالِمة.',
                            ),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: _CommunityActionBar(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: _co('Messages', 'رسائلي'),
                                  onTap: _openPrivateMessages,
                                  badge: UnreadMessagesBadge(
                                    key: ValueKey(_badgeRefresh),
                                    repository: _messagingRepository,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 5,
                                child: _CommunityActionBar(
                                  icon: Icons.add_rounded,
                                  label: _co('Create post', 'اكتبي منشورًا'),
                                  onTap: () => showCommunityComposerSheet(
                                    context,
                                    viewModel: _viewModel,
                                  ),
                                  filled: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: palette.text),
                      cursorColor: palette.blush,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _co(
                          'Search conversations',
                          'ابحثي في المحادثات',
                        ),
                        hintStyle: TextStyle(
                          color: palette.textFaint,
                          fontSize: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: palette.blush,
                          size: 19,
                        ),
                        filled: true,
                        fillColor: palette.surface,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: _co('Clear search', 'مسح البحث'),
                                onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: palette.textFaint,
                                  size: 18,
                                ),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.border),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: CommunityCategoryChipBar(
                      selected: _viewModel.selectedCategory,
                      onSelect: _viewModel.selectCategory,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 132),
                  sliver: _viewModel.isLoading
                      ? SliverList.list(
                          children: const [
                            _SkeletonCard(),
                            SizedBox(height: 14),
                            _SkeletonCard(),
                            SizedBox(height: 14),
                            _SkeletonCard(),
                          ],
                        )
                      : _viewModel.errorMessage != null && posts.isEmpty
                      ? SliverToBoxAdapter(
                          child: LoadErrorBanner(
                            message: _co(
                              'Community could not be loaded.',
                              'تعذر تحميل المجتمع.',
                            ),
                            onRetry: _viewModel.loadPosts,
                          ),
                        )
                      : posts.isEmpty
                      ? SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.forum_outlined,
                            title: query.isNotEmpty
                                ? _co(
                                    'No matching posts',
                                    'لا توجد نتائج مطابقة',
                                  )
                                : _co(
                                    'No posts here yet',
                                    'لا توجد منشورات بعد',
                                  ),
                            message: query.isNotEmpty
                                ? _co(
                                    'Try a different word or clear your search.',
                                    'جرّبي كلمة أخرى أو امسحي البحث.',
                                  )
                                : _co(
                                    'Start a supportive conversation with the community.',
                                    'ابدئي محادثة داعمة مع المجتمع.',
                                  ),
                            actionLabel: query.isNotEmpty
                                ? _co('Clear search', 'مسح البحث')
                                : _co('Create post', 'إنشاء منشور'),
                            onAction: query.isNotEmpty
                                ? () {
                                    _searchController.clear();
                                    setState(() {});
                                  }
                                : () => showCommunityComposerSheet(
                                    context,
                                    viewModel: _viewModel,
                                  ),
                          ),
                        )
                      : SliverList.separated(
                          itemCount:
                              posts.length + (_viewModel.isLoadingMore ? 1 : 0),
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            if (index >= posts.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: palette.blush,
                                  ),
                                ),
                              );
                            }
                            final post = posts[index];
                            final isOwnPost =
                                _currentUserId != null &&
                                post.userId == _currentUserId;
                            return CommunityPostCard(
                              post: post,
                              isOwnPost: isOwnPost,
                              onTap: () => _openPost(post),
                              onLike: () => _viewModel.toggleLike(post.id),
                              onDelete: isOwnPost
                                  ? () => _viewModel.deletePost(post.id)
                                  : null,
                              onMessageAuthor: !post.isAnonymous && !isOwnPost
                                  ? () => _messagePostAuthor(post)
                                  : null,
                              onAuthorTap: post.isAnonymous
                                  ? null
                                  : () => _openMemberPreview(post),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Unified action button used in the Community header bar.
class _CommunityActionBar extends StatelessWidget {
  const _CommunityActionBar({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBlush = isDark ? const Color(0xFF32171D) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? palette.blush : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.blush),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? onBlush : palette.blush, size: 19),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: filled ? onBlush : palette.blush,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 6), badge!],
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) {
    final palette = CommunityPalette.of(context);
    return Container(
      height: 178,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: palette.divider),
      ),
    );
  }
}

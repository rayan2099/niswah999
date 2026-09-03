import 'package:flutter/material.dart';

import '../../domain/repositories/private_messaging_repository_base.dart';

/// Red notification badge showing the number of unread private messages.
///
/// Loads the count from [repository] on init and refreshes whenever the
/// widget is re-inserted (e.g. returning from the conversations screen).
/// Renders nothing when there are no unread messages.
class UnreadMessagesBadge extends StatefulWidget {
  const UnreadMessagesBadge({super.key, required this.repository});

  final PrivateMessagingRepositoryBase repository;

  @override
  State<UnreadMessagesBadge> createState() => _UnreadMessagesBadgeState();
}

class _UnreadMessagesBadgeState extends State<UnreadMessagesBadge> {
  int? _unreadCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final count = await widget.repository.fetchUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {
      // Badge is a nice-to-have; silently ignore load failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _unreadCount ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/localization/app_locale_controller.dart';
import 'community_safety_controller.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Profile → Blocked members: see and undo blocks.
class BlockedMembersScreen extends StatefulWidget {
  const BlockedMembersScreen({super.key, this.controller});

  final CommunitySafetyController? controller;

  @override
  State<BlockedMembersScreen> createState() => _BlockedMembersScreenState();
}

class _BlockedMembersScreenState extends State<BlockedMembersScreen> {
  CommunitySafetyController get _safety =>
      widget.controller ?? CommunitySafetyController.instance;

  @override
  void initState() {
    super.initState();
    _safety.load();
  }

  Future<void> _unblock(String userId) async {
    try {
      await _safety.unblock(userId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Could not unblock. Please try again.',
              'تعذر إلغاء الحظر. يُرجى المحاولة مجدداً.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('Blocked members', 'العضوات المحظورات'))),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _safety,
          builder: (context, _) {
            final blocked = _safety.blockedMembers;
            if (blocked.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _t('You haven\'t blocked anyone.', 'لم تحظري أحداً.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: blocked.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = blocked[index];
                final name = member.displayName?.trim();
                return ListTile(
                  leading: const Icon(Icons.block_rounded),
                  title: Text(
                    name == null || name.isEmpty
                        ? _t('Community member', 'عضوة في المجتمع')
                        : name,
                  ),
                  trailing: TextButton(
                    onPressed: () => _unblock(member.userId),
                    child: Text(_t('Unblock', 'إلغاء الحظر')),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

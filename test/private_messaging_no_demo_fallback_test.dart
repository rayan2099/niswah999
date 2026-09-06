import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/community/presentation/screens/community_board_screen.dart';
import 'package:niswah/features/private_messaging/presentation/screens/conversations_screen.dart';

/// PJ-005/CQ-007: previously, opening private messaging with no signed-in
/// session (which, in the live app, can only mean a session that was
/// valid a moment ago has since died — `NiswahHomeShell`'s children are
/// only reachable once `AuthController.isAuthenticated` is true) silently
/// substituted fabricated, named-contact demo conversations, with no
/// indication anything was wrong. This test environment has no Supabase
/// configured, so `_currentUserId` is null here exactly as it would be
/// for a dead session in production — proving the fix without needing to
/// simulate an actual session expiry (Final Application Code Blockers
/// wave, 2026-09-06).
void main() {
  testWidgets(
    'tapping "Messages" with no session shows an honest sign-in prompt, '
    'never the fabricated demo conversation list',
    (tester) async {
      AppLocaleController.instance.setArabic(false);
      await tester.pumpWidget(const MaterialApp(home: CommunityBoardScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Messages'));
      await tester.pump();

      expect(
        find.textContaining('Your session has ended'),
        findsOneWidget,
        reason: 'an honest, actionable message must be shown',
      );
      expect(
        find.byType(ConversationsScreen),
        findsNothing,
        reason: 'must never navigate to a conversations list — fabricated '
            'or otherwise — without a real session',
      );
      // No named fake contact ever appears anywhere in the tree.
      expect(find.textContaining('Umm Sara'), findsNothing);
      expect(find.textContaining('Huda'), findsNothing);
      expect(find.textContaining('Maryam'), findsNothing);
    },
  );
}

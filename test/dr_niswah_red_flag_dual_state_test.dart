import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/features/ai_assistant/domain/services/dr_niswah_red_flags.dart';
import 'package:niswah/features/ai_assistant/presentation/viewmodels/chat_view_model.dart';

/// PJ-003: previously, a correctly-firing safety banner could render
/// simultaneously with a generic/alarming `errorMessage` on the same chat
/// screen, for the same failed request — because the local red-flag
/// fallback appended a reassuring banner message *and* rethrew, and the
/// outer `sendMessage` catch turned that rethrow into a second, unrelated
/// error signal. Exercises `sendViaDrNiswahBackendForTesting` directly
/// (the real production method, made `@visibleForTesting`) rather than
/// through the public `sendMessage()` API, since `DrNiswahBackendService`
/// is a hardcoded singleton with no DI seam — but it throws
/// deterministically when Supabase isn't configured (this test
/// environment's default), which is exactly the failure this fix needs to
/// be driven through (Final Application Code Blockers wave, 2026-09-06).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'a red-flag message that fails to reach the backend shows only the '
    'reassuring banner — errorMessage is never also set for the same '
    'failed request',
    () async {
      final viewModel = ChatViewModel();
      const redFlagContent = 'عندي نزيف الآن'; // matches _bleeding

      expect(
        DrNiswahRedFlags.matches(redFlagContent),
        isTrue,
        reason: 'sanity check: this content must actually be a red flag '
            'for the test to mean anything',
      );

      await viewModel.sendViaDrNiswahBackendForTesting(
        threadId: 'thread-1',
        userId: 'user-1',
        content: redFlagContent,
      );

      expect(
        viewModel.messages,
        hasLength(1),
        reason: 'the reassuring banner must have been appended',
      );
      expect(
        viewModel.messages.single.content,
        DrNiswahRedFlags.bannerTextAr,
      );
      expect(
        viewModel.messages.single.metadata['urgent'],
        isTrue,
      );
      expect(
        viewModel.errorMessage,
        isNull,
        reason: 'PJ-003: the banner is already a complete, coherent '
            'response to this failure — a second, contradictory generic '
            'error must never also appear for the same failed request',
      );
    },
  );

  test(
    'a non-red-flag message that fails to reach the backend still throws '
    '(unchanged behavior) — this fix must not swallow ordinary failures',
    () async {
      final viewModel = ChatViewModel();
      const ordinaryContent = 'How are you today?';

      expect(DrNiswahRedFlags.matches(ordinaryContent), isFalse);

      await expectLater(
        () => viewModel.sendViaDrNiswahBackendForTesting(
          threadId: 'thread-1',
          userId: 'user-1',
          content: ordinaryContent,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        viewModel.messages,
        isEmpty,
        reason: 'no local fallback banner applies to a non-red-flag '
            'message — the caller (sendMessage) is responsible for '
            'surfacing this failure normally, via its own outer catch',
      );
    },
  );

  test(
    'the ChatMessage produced for the banner is a genuinely new, '
    'independent record — not the same instance reused across calls',
    () async {
      final viewModel = ChatViewModel();
      const redFlagContent = 'ألم شديد في البطن';

      await viewModel.sendViaDrNiswahBackendForTesting(
        threadId: 'thread-1',
        userId: 'user-1',
        content: redFlagContent,
      );
      final firstBanner = viewModel.messages.single;

      await viewModel.sendViaDrNiswahBackendForTesting(
        threadId: 'thread-1',
        userId: 'user-1',
        content: redFlagContent,
      );
      final secondBanner = viewModel.messages.last;

      expect(viewModel.messages, hasLength(2));
      expect(
        firstBanner.id,
        isNot(secondBanner.id),
        reason: 'two separate urgent exchanges must not collide on id',
      );
    },
  );
}

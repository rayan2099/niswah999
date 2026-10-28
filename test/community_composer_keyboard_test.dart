import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/community_language_controller.dart';
import 'package:niswah/features/community/domain/repositories/community_repository.dart';
import 'package:niswah/features/community/presentation/viewmodels/community_feed_view_model.dart';
import 'package:niswah/features/community/presentation/widgets/community_composer_sheet.dart';

/// Never called: the test only lays the composer out.
class _UnusedRepository implements CommunityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Device run 2026-10-28: with the keyboard open, "Publish post" was
  // pushed below the keyboard. It must stay fully above it.
  testWidgets('publish button stays above the keyboard', (tester) async {
    const screen = Size(390, 844);
    const keyboard = 336.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);

    final viewModel = CommunityFeedViewModel(
      repository: _UnusedRepository(),
      currentUserId: 'user-1',
      currentUserName: 'Test User',
      language: CommunityLanguage.en,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showCommunityComposerSheet(context, viewModel: viewModel),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      List.filled(12, 'A long line of text for the post.').join('\n'),
    );
    await tester.pumpAndSettle();

    final button = find.ancestor(
      of: find.byIcon(Icons.send_rounded),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.bottom, lessThanOrEqualTo(screen.height - keyboard));
    expect(rect.top, greaterThanOrEqualTo(0));
  });
}

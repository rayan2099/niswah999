import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/features/community/presentation/screens/community_board_screen.dart';

void main() {
  testWidgets('community composer accepts text and exposes no media actions', (
    tester,
  ) async {
    AppLocaleController.instance.setArabic(false);
    await tester.pumpWidget(const MaterialApp(home: CommunityBoardScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create post'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Text only'), findsOneWidget);
    expect(find.text('Your post'), findsOneWidget);
    expect(find.text('Title'), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    expect(find.byIcon(Icons.attach_file_rounded), findsNothing);

    await tester.tap(find.text('Publish post'));
    await tester.pump();

    expect(find.text('Write a message before posting.'), findsOneWidget);
  });
}

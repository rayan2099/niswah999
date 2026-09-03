import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/localization/app_locale_controller.dart';
import 'package:niswah/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Arabic locale applies RTL navigation and Dashboard copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'niswah_arabic': true});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(const NiswahApp());
    await tester.pumpAndSettle();

    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('المجتمع'), findsOneWidget);
    expect(find.textContaining('حيض'), findsWidgets);

    AppLocaleController.instance.setArabic(false);
  });
}

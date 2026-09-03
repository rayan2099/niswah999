import 'package:flutter/material.dart'; import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niswah/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:niswah/core/preferences/pregnancy_status_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('dashboard renders while pregnant', (tester) async {
    await PregnancyStatusController.instance.activate(startWeek: 1);
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('pregnancy-overview')), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niswah/main.dart' as app;

import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P0 build identity: real app launches and reports SHA/backend', (
    tester,
  ) async {
    app.main();
    final h = Harness(binding, tester);
    await tester.pump(const Duration(seconds: 5));
    await h.settle();

    // ignore: avoid_print
    print('BANNER => ${h.bannerText()}');
    expect(h.bannerText(), contains('SHA:'));
    await h.shot('P0', 'first_screen');
  });
}

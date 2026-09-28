import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:niswah/core/preferences/ttc_mode_controller.dart';

void main() {
  final controller = TtcModeController.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    controller.resetInMemory();
  });

  tearDown(controller.resetInMemory);

  test('missing stored preference remains UNKNOWN for AI trust boundary', () async {
    await controller.load();

    expect(controller.enabled, isFalse);
    expect(controller.explicitSelectionOrNull, isNull);
  });

  test('explicit enabled selection is distinguishable from presentation default', () async {
    await controller.setEnabled(true);

    expect(controller.enabled, isTrue);
    expect(controller.explicitSelectionOrNull, isTrue);
  });

  test('explicit disabled selection remains an explicit false, not UNKNOWN', () async {
    await controller.setEnabled(false);

    expect(controller.enabled, isFalse);
    expect(controller.explicitSelectionOrNull, isFalse);
  });

  test('persisted explicit preference is recovered on load', () async {
    await controller.setEnabled(true);
    controller.resetInMemory();

    await controller.load();

    expect(controller.explicitSelectionOrNull, isTrue);
  });

  test('sign-out reset clears in-memory authority until next user load', () async {
    await controller.setEnabled(true);
    expect(controller.explicitSelectionOrNull, isTrue);

    controller.resetInMemory();

    expect(controller.enabled, isFalse);
    expect(controller.explicitSelectionOrNull, isNull);
  });
}

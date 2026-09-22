import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final shotDir = Platform.environment['SHOT_DIR'] ?? 'acceptance/screenshots';
  await integrationDriver(
    onScreenshot:
        (
          String name,
          List<int> image, [
          Map<String, Object?>? args,
        ]) async {
          final dir = Directory(shotDir);
          await dir.create(recursive: true);
          await File('${dir.path}/$name.png').writeAsBytes(image);
          return true;
        },
  );
}

import 'dart:async';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// Runs once per test file, before that file's `main()` executes — gives
/// every test file a fresh in-memory `flutter_secure_storage` backing
/// store by default, the same way most files already call
/// `SharedPreferences.setMockInitialValues({})` once at the top of
/// `main()`. Without this, any test that touches `SecureLocalStore`
/// (cycle/prayer/pregnancy local data, directly or via a repository/
/// viewmodel/screen) hits a real platform channel that doesn't exist
/// under `flutter_test` and throws.
///
/// Individual tests/files that need per-test isolation or seeded values
/// can still call `resetSecureLocalStoreForTest(...)`
/// (test/support/secure_storage_test_support.dart) in their own `setUp()`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  await testMain();
}

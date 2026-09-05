import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// Resets the `flutter_secure_storage` backing store to an in-memory fake —
/// call from `setUp()` in any test that (directly or indirectly, via
/// `SecureLocalStore`) touches cycle/prayer/pregnancy local storage.
/// Mirrors `SharedPreferences.setMockInitialValues({})` for the
/// secure-storage-backed path; without it, calls hit a real platform
/// channel that doesn't exist under `flutter_test` and throw.
void resetSecureLocalStoreForTest([
  Map<String, String> initialValues = const {},
]) {
  FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({
    ...initialValues,
  });
}

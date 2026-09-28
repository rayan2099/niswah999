import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'test_backend_gate.dart';

/// Runtime bridge between the loaded `.env` and [TestBackendGate].
class AcceptanceGate {
  AcceptanceGate._();

  /// Verdict for the backend the running app is actually configured for.
  /// A `.env` that was never loaded (or cannot be read) is REFUSED, not
  /// assumed safe.
  static BackendGateVerdict currentVerdict() {
    try {
      return TestBackendGate.evaluateEnvironment(dotenv.env);
    } catch (_) {
      return const BackendGateVerdict.refused(
        host: '<env-not-loaded>',
        reason: 'the environment could not be read',
      );
    }
  }
}

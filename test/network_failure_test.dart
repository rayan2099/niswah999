import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/errors/network_failure.dart';

void main() {
  group('isNetworkFailure — acceptance finding: sign-up on a dead connection '
      'showed a raw exception with the server URL', () {
    test('the exact string the simulator showed is a network failure', () {
      expect(
        isNetworkFailure(
          Exception(
            'ClientException with SocketConnection refused (OS Error: '
            'Connection refused, errno = 61), address = 127.0.0.1, '
            'port = 55281, uri=http://127.0.0.1:54321/auth/v1/signup',
          ),
        ),
        isTrue,
      );
    });

    test('typed connectivity exceptions are network failures', () {
      expect(isNetworkFailure(const SocketException('x')), isTrue);
      expect(isNetworkFailure(TimeoutException('x')), isTrue);
    });

    test('a real server/validation answer is NOT a network failure', () {
      expect(isNetworkFailure(Exception('Invalid login credentials')), isFalse);
      expect(isNetworkFailure(Exception('User already registered')), isFalse);
      expect(isNetworkFailure(Exception('Password too short')), isFalse);
    });
  });
}

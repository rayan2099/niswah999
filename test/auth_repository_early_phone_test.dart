import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/features/auth/data/repositories/auth_repository_impl.dart';

import 'logging_sync_hardening/support/fake_supabase.dart';

void main() {
  test(
    'phone signup establishes a real session without OTP or email confirmation',
    () async {
      final calls = <String>[];
      final session = jsonDecode(
        fakeSessionJson('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
      ) as Map<String, dynamic>;
      session['user']['email'] = 'internal@early.niswah.invalid';
      final client = SupabaseClient(
        'http://fake.supabase.local',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path == '/functions/v1/early-phone-access') {
            final body = jsonDecode(request.body) as Map;
            expect(body['action'], 'signup');
            expect(body['phone'], '+966500000001');
            expect(body['password'], 'synthetic-password');
            return jsonResponse(session);
          }
          if (request.url.path == '/auth/v1/token')
            return jsonResponse(session);
          return jsonResponse([]);
        }),
      );
      addTearDown(client.dispose);
      final repo = AuthRepositoryImpl(client: client);
      await repo.signUpWithPhone(
        phone: '+966500000001',
        password: 'synthetic-password',
      );
      expect(
        client.auth.currentUser?.id,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
      expect((await repo.currentUser)?.email, '');
      expect(
        calls.where(
          (p) =>
              p.contains('otp') || p.contains('signup') || p.contains('verify'),
        ),
        isEmpty,
      );
      await expectLater(
        repo.resetPasswordForEmail(email: 'internal@early.niswah.invalid'),
        throwsA(anything),
      );
    },
    skip: !earlyPhoneAccessBuild,
  );

  test('full cohort response keeps the client signed out', () async {
    final client = SupabaseClient(
      'http://fake.supabase.local',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          '{"error":"cohort_full"}',
          409,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      AuthRepositoryImpl(
        client: client,
      ).signUpWithPhone(phone: '+966500000001', password: 'synthetic-password'),
      throwsA(anything),
    );
    expect(client.auth.currentSession, isNull);
  }, skip: !earlyPhoneAccessBuild);
}

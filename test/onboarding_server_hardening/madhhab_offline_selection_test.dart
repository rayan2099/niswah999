// Onboarding/server hardening regression, finding #6: a madhhab chosen while
// the server write fails (offline onboarding, or an offline change) must not
// be reverted by the stale server row on the next launch, and the write must
// be retried until the server confirms it.
//
// Runs MadhhabController against the real Supabase client over a scripted
// HTTP transport with a synthetic signed-in user — no network, no project.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging_sync_hardening/support/fake_supabase.dart'
    show fakeSessionJson, jsonResponse;

const _userId = 'aaaaaaaa-0000-4000-8000-0000000000a6';

/// What the server row currently holds.
Map<String, dynamic> serverRow = {
  'madhhab': null,
  'madhhab_selection_state': 'unset',
};
bool serverReachable = true;
final List<Map<String, dynamic>> usersPatches = [];

Future<http.Response> _route(http.Request request) async {
  if (request.url.path == '/rest/v1/users') {
    if (!serverReachable) throw http.ClientException('Failed host lookup');
    if (request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      usersPatches.add(body);
      serverRow = {...serverRow, ...body};
      return jsonResponse([
        {'id': _userId},
      ]);
    }
    // GET (maybeSingle asks for a single object).
    return jsonResponse(serverRow);
  }
  return jsonResponse([]); // madhhab_history inserts etc.
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fake.supabase.local',
      publishableKey: 'anon-key',
      httpClient: MockClient((request) async {
        final r = await _route(request);
        return http.Response(
          r.body,
          r.statusCode,
          headers: r.headers,
          request: request,
        );
      }),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(
      fakeSessionJson(_userId),
    );
  });

  test('R2-MADH-1: an offline madhhab choice survives the next launch and is '
      'written to the server once it is reachable', () async {
    SharedPreferences.setMockInitialValues({});
    serverRow = {'madhhab': null, 'madhhab_selection_state': 'unset'};
    usersPatches.clear();
    serverReachable = true;
    await MadhhabController.instance.load();
    expect(MadhhabController.instance.state, MadhhabSelectionState.unset);

    // Onboarding while offline: the server write fails.
    serverReachable = false;
    await MadhhabController.instance.selectMadhhab(
      Madhhab.shafii,
      source: 'onboarding',
    );

    // Next launch, back online: the server row still says "unset".
    serverReachable = true;
    MadhhabController.instance.resetInMemory();
    await MadhhabController.instance.load();

    expect(
      MadhhabController.instance.selectedOrNull,
      Madhhab.shafii,
      reason: 'the stale server row reverted her offline choice',
    );
    expect(
      serverRow['madhhab'],
      'shafii',
      reason: 'the failed write was never retried',
    );
    expect(await MadhhabController.instance.hasPendingServerWrite(), isFalse);

    // A later launch now reads the (correct) server row.
    MadhhabController.instance.resetInMemory();
    await MadhhabController.instance.load();
    expect(MadhhabController.instance.selectedOrNull, Madhhab.shafii);
  });

  test('R2-MADH-2: an offline CHANGE (Hanafi -> Shafii) is not reverted to the '
      'older server madhhab', () async {
    SharedPreferences.setMockInitialValues({});
    serverRow = {'madhhab': 'hanafi', 'madhhab_selection_state': 'selected'};
    serverReachable = true;
    await MadhhabController.instance.load();
    expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);

    serverReachable = false;
    await MadhhabController.instance.selectMadhhab(Madhhab.shafii);

    serverReachable = true;
    MadhhabController.instance.resetInMemory();
    await MadhhabController.instance.load();
    expect(
      MadhhabController.instance.selectedOrNull,
      Madhhab.shafii,
      reason: 'rulings would silently follow the older Hanafi selection',
    );
    expect(serverRow['madhhab'], 'shafii');
  });
}

// Fiqh Remediation Wave 1 (AUTH-005/AUTH-010) — unit-level proof that
// MadhhabController's silent `orElse: () => Madhhab.hanbali` fallback is
// gone, and that UNSET/UNKNOWN/SELECTED are genuinely distinct, never
// collapsed states.
//
// Evidence-level disclosure (Section U): this file cannot exercise real
// Supabase server persistence — no backend is initialized in a plain
// `flutter test` run, so `NiswahSupabase.clientOrNull` is null throughout,
// and every server read/write inside MadhhabController silently no-ops
// (by design — see its own doc comments). This is E2 (automated verified)
// for the LOCAL half of the contract: the state model, the local-cache
// fallback, and — most importantly — the absence of any hardcoded madhhab
// fallback anywhere in this class. It does NOT by itself prove real
// server-side persistence across a genuine reinstall; that requires E3
// (server persistence + RLS + calculation/context integration, proven via
// the live schema/migration work and the edge-function changes in this
// same wave) and ultimately E4 (owner real-device evidence — still
// outstanding, see the wave's own Return report).
import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/preferences/madhhab_controller.dart';
import 'package:niswah/features/cycle_tracking/domain/services/madhhab_rule_evaluator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MadhhabController — canonical state model (Section A)', () {
    test('a fresh install (empty local cache, no server) is UNSET — never a specific madhhab', () async {
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unset);
      expect(MadhhabController.instance.selectedOrNull, isNull);
      expect(MadhhabController.instance.isSelected, isFalse);
      expect(
        MadhhabController.instance.selectedOrNull,
        isNot(Madhhab.hanbali),
        reason:
            'the exact defect this wave removes: an unset controller must '
            'never silently report Hanbali',
      );
    });

    test(
      'selectMadhhab moves to SELECTED and persists the real value locally',
      () async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();

        await MadhhabController.instance.selectMadhhab(Madhhab.shafii);

        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.shafii);
        expect(MadhhabController.instance.isSelected, isTrue);

        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString('niswah_madhhab_selection_state'),
          'selected',
        );
        expect(preferences.getString('niswah_selected_madhhab'), 'shafii');
      },
    );

    test('selectUnknown moves to UNKNOWN — a first-class state, never a specific madhhab', () async {
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();

      await MadhhabController.instance.selectUnknown();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
      expect(
        MadhhabController.instance.selectedOrNull,
        isNull,
        reason: 'UNKNOWN must never carry a madhhab value, including Hanbali',
      );
      expect(MadhhabController.instance.isSelected, isFalse);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('niswah_madhhab_selection_state'),
        'unknown',
      );
      expect(
        preferences.getString('niswah_selected_madhhab'),
        isNull,
        reason: 'no stale madhhab value should survive a transition to UNKNOWN',
      );
    });

    test('selecting a real madhhab after UNKNOWN correctly overwrites it to SELECTED', () async {
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();
      await MadhhabController.instance.selectUnknown();

      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);

      expect(MadhhabController.instance.state, MadhhabSelectionState.selected);
      expect(MadhhabController.instance.selectedOrNull, Madhhab.hanafi);
    });

    test('changing from one real madhhab to another (Settings — Section K) replaces the prior selection cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();
      await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);

      await MadhhabController.instance.selectMadhhab(Madhhab.maliki);

      expect(MadhhabController.instance.selectedOrNull, Madhhab.maliki);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('niswah_selected_madhhab'), 'maliki');
    });
  });

  group('MadhhabController — local-cache fallback (no server available)', () {
    test(
      'load() restores a real SELECTED value from this device\'s own cache',
      () async {
        SharedPreferences.setMockInitialValues({
          'niswah_madhhab_selection_state': 'selected',
          'niswah_selected_madhhab': 'hanbali',
        });
        await MadhhabController.instance.load();

        // Here Hanbali is legitimate — it is the value this test explicitly,
        // deliberately seeded as an already-recorded local selection, not a
        // fallback the controller invented on its own.
        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );
        expect(MadhhabController.instance.selectedOrNull, Madhhab.hanbali);
      },
    );

    test(
      'load() restores UNKNOWN from cache — never silently re-asks or defaults',
      () async {
        SharedPreferences.setMockInitialValues({
          'niswah_madhhab_selection_state': 'unknown',
        });
        await MadhhabController.instance.load();

        expect(MadhhabController.instance.state, MadhhabSelectionState.unknown);
        expect(MadhhabController.instance.selectedOrNull, isNull);
      },
    );

    test('a corrupted/unrecognized cached value never becomes a guessed madhhab — falls back to UNSET', () async {
      SharedPreferences.setMockInitialValues({
        'niswah_madhhab_selection_state': 'selected',
        'niswah_selected_madhhab': 'not-a-real-madhhab',
      });
      await MadhhabController.instance.load();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unset);
      expect(MadhhabController.instance.selectedOrNull, isNull);
    });

    test('reinstall simulation: cleared local storage + no server available never resolves to Hanbali or any other madhhab', () async {
      // Simulates exactly the scenario AUTH-005 tracked: an already-
      // onboarded user reinstalls (SharedPreferences wiped) and, in this
      // unit test, no Supabase backend exists either — the worst case
      // for "does this silently become Hanbali."
      SharedPreferences.setMockInitialValues({});
      await MadhhabController.instance.load();

      expect(MadhhabController.instance.state, MadhhabSelectionState.unset);
      expect(MadhhabController.instance.selectedOrNull, isNull);
      for (final madhhab in Madhhab.values) {
        expect(MadhhabController.instance.selectedOrNull, isNot(madhhab));
      }
    });
  });

  group(
    'MadhhabController — account switching (Section M, in-memory half)',
    () {
      test('resetInMemory clears in-memory state without needing the cache to change', () async {
        SharedPreferences.setMockInitialValues({});
        await MadhhabController.instance.load();
        await MadhhabController.instance.selectMadhhab(Madhhab.hanafi);
        expect(
          MadhhabController.instance.state,
          MadhhabSelectionState.selected,
        );

        MadhhabController.instance.resetInMemory();

        expect(MadhhabController.instance.state, MadhhabSelectionState.unset);
        expect(MadhhabController.instance.selectedOrNull, isNull);
      });
    },
  );
}

// Unit tests for the pure (non-DB) parts of ai_user_context.ts.
//
// NOTE (honest disclosure, AI User-State Context Layer wave, 2026-09-09):
// this Deno test file follows the same style and location convention as
// the pre-existing pregnancy_status.test.ts, but no Deno runtime was
// available in the environment this wave was authored in (`which deno` ->
// not found), so it could not actually be executed here. It was written
// carefully and cross-checked by hand against the module's own logic
// (mirroring the exact encoding contract already used by
// lib/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart's
// real, passing Dart tests), but this is disclosed rather than silently
// presented as "passing" — see FIQH_AICTX_findings.md's Phase L section for
// how this wave's live synthetic verification compensated for that gap.
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import {
  decodeLegacyNote,
  decodeSymptomSeverities,
  formatContextBlock,
  mergeNotesSources,
  type UserAiContext,
} from './ai_user_context.ts';

Deno.test('decodeSymptomSeverities — ignores reserved keys, keeps named symptoms', () => {
  const raw = ['mood:4', 'energy:3', 'sleep:2', 'color:red', 'notes:felt tired', 'Cramps:2', 'Headache:1'];
  assertEquals(decodeSymptomSeverities(raw), { Cramps: 2, Headache: 1 });
});

Deno.test('decodeSymptomSeverities — excludes zero/negative severities', () => {
  assertEquals(decodeSymptomSeverities(['Cramps:0', 'Nausea:-1', 'Fatigue:3']), { Fatigue: 3 });
});

Deno.test('decodeSymptomSeverities — handles null/empty input', () => {
  assertEquals(decodeSymptomSeverities(null), {});
  assertEquals(decodeSymptomSeverities([]), {});
});

Deno.test('decodeSymptomSeverities — ignores entries with no separator', () => {
  assertEquals(decodeSymptomSeverities(['garbage', 'Cramps:2']), { Cramps: 2 });
});

Deno.test('decodeLegacyNote — finds a notes: entry', () => {
  assertEquals(decodeLegacyNote(['mood:4', 'notes:felt better today']), 'felt better today');
});

Deno.test('decodeLegacyNote — returns null when absent', () => {
  assertEquals(decodeLegacyNote(['mood:4', 'Cramps:2']), null);
  assertEquals(decodeLegacyNote(null), null);
});

Deno.test('mergeNotesSources — AICTX-13: combines cycle and wellbeing notes, newest first', () => {
  const cycleNotes = [
    { date: '2026-09-05', text: 'cramps started', source: 'cycle_entries' as const },
  ];
  const wellbeingNotes = [
    { date: '2026-09-08', text: 'felt anxious, prayed anyway', source: 'wellbeing_logs' as const },
  ];
  const merged = mergeNotesSources(cycleNotes, wellbeingNotes, 5);
  assertEquals(merged, [
    { date: '2026-09-08', text: 'felt anxious, prayed anyway', source: 'wellbeing_logs' },
    { date: '2026-09-05', text: 'cramps started', source: 'cycle_entries' },
  ]);
});

Deno.test('mergeNotesSources — respects the limit across both sources combined', () => {
  const cycleNotes = [
    { date: '2026-09-01', text: 'a', source: 'cycle_entries' as const },
    { date: '2026-09-02', text: 'b', source: 'cycle_entries' as const },
  ];
  const wellbeingNotes = [
    { date: '2026-09-03', text: 'c', source: 'wellbeing_logs' as const },
  ];
  const merged = mergeNotesSources(cycleNotes, wellbeingNotes, 2);
  assertEquals(merged.length, 2);
  assertEquals(merged[0].date, '2026-09-03');
  assertEquals(merged[1].date, '2026-09-02');
});

Deno.test('mergeNotesSources — handles empty wellbeing notes (cycle-only, matches old behavior)', () => {
  const cycleNotes = [{ date: '2026-09-01', text: 'a', source: 'cycle_entries' as const }];
  assertEquals(mergeNotesSources(cycleNotes, [], 5), cycleNotes);
});

function baseContext(overrides: Partial<UserAiContext> = {}): UserAiContext {
  return {
    contextVersion: '1',
    generatedAt: '2026-09-09T00:00:00.000Z',
    pregnancy: {
      mode: 'unknown',
      highRiskFlags: [],
      source: 'pregnancy_profile_table',
    },
    menstrualCycle: {
      hasHistory: false,
      isCurrentlyBleeding: null,
      daysIntoCurrentEpisode: null,
      lastEntryDate: null,
      totalLoggedEntries: 0,
      source: 'cycle_entries_table',
      note: 'test',
    },
    fiqh: {
      madhhab: null,
      madhhabSource: 'not_provided',
      classification: null,
      classificationSource: 'not_provided',
      uncertainty: 'none',
    },
    wellbeing: { recentEntries: [], source: 'wellbeing_logs_table' },
    symptoms: { recent: [], source: 'cycle_entries_symptoms_field' },
    notes: { recent: [] },
    safetyFlags: [],
    dataFreshness: { fetchedAt: '2026-09-09T00:00:00.000Z' },
    ...overrides,
  };
}

Deno.test('formatContextBlock — general_assistant includes pregnancy, cycle, fiqh, wellbeing, notes', () => {
  const context = baseContext({
    pregnancy: {
      mode: 'pregnant',
      week: 20,
      trimester: 2,
      highRiskFlags: [],
      source: 'pregnancy_profile_table',
    },
    fiqh: {
      madhhab: 'hanafi',
      madhhabSource: 'client_supplied',
      classification: null,
      classificationSource: 'not_provided',
      uncertainty: 'not provided this call',
    },
  });
  const block = formatContextBlock(context, 'general_assistant');
  assertEquals(block.includes('mode: pregnant'), true);
  assertEquals(block.includes('pregnancy_week: 20'), true);
  assertEquals(block.includes('selected_madhhab: hanafi'), true);
  assertEquals(block.includes('[END CONTEXT]'), true);
});

Deno.test('formatContextBlock — never emits a bare pregnancy_week/trimester when mode is not pregnant', () => {
  const context = baseContext();
  const block = formatContextBlock(context, 'dr_niswah');
  assertEquals(block.includes('pregnancy_week'), false);
  assertEquals(block.includes('mode: unknown'), true);
});

Deno.test('formatContextBlock — dream_interpreter scope excludes fiqh/symptoms sections entirely', () => {
  const context = baseContext({
    fiqh: {
      madhhab: 'hanafi',
      madhhabSource: 'client_supplied',
      classification: 'haid',
      classificationSource: 'client_computed',
      uncertainty: 'none',
    },
    symptoms: {
      recent: [{ date: '2026-09-08', severities: { Cramps: 2 } }],
      source: 'cycle_entries_symptoms_field',
    },
  });
  const block = formatContextBlock(context, 'dream_interpreter');
  assertEquals(block.includes('selected_madhhab'), false);
  assertEquals(block.includes('recent_symptoms'), false);
});

Deno.test('formatContextBlock — fiqh_advisor scope surfaces deterministic classification with its source label', () => {
  const context = baseContext({
    fiqh: {
      madhhab: 'shafii',
      madhhabSource: 'client_supplied',
      classification: 'haid',
      classificationSource: 'client_computed',
      uncertainty: 'none',
    },
  });
  const block = formatContextBlock(context, 'fiqh_advisor');
  assertEquals(
    block.includes('deterministic_fiqh_classification: haid (source: client_computed)'),
    true,
  );
});

Deno.test('formatContextBlock — fiqh_advisor scope states uncertainty explicitly when classification absent', () => {
  const context = baseContext({
    fiqh: {
      madhhab: 'shafii',
      madhhabSource: 'client_supplied',
      classification: null,
      classificationSource: 'not_provided',
      uncertainty: 'Deterministic fiqh classification was not supplied by the client this call — do not assume a classification.',
    },
  });
  const block = formatContextBlock(context, 'fiqh_advisor');
  assertEquals(block.includes('deterministic_fiqh_classification: not_provided (source: not_provided)'), true);
  assertEquals(block.includes('fiqh_uncertainty:'), true);
});

Deno.test('formatContextBlock — notes are labeled as user-authored, not verified facts', () => {
  const context = baseContext({
    notes: {
      recent: [{ date: '2026-09-08', text: 'feeling anxious today', source: 'wellbeing_logs' }],
    },
  });
  const block = formatContextBlock(context, 'dr_niswah');
  assertEquals(block.includes('NOT verified facts'), true);
  assertEquals(block.includes('feeling anxious today'), true);
});

Deno.test('formatContextBlock — always wraps in the internal-only marker', () => {
  const block = formatContextBlock(baseContext(), 'general_assistant');
  assertEquals(block.startsWith('[CONTEXT'), true);
  assertEquals(block.trim().endsWith('[END CONTEXT]'), true);
});

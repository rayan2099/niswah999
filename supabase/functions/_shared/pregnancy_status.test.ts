import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { getPregnancyStatus, PregnancyProfileRow } from './pregnancy_status.ts';

function profile(overrides: Partial<PregnancyProfileRow> = {}): PregnancyProfileRow {
  return {
    tracking_basis: null,
    reference_date: null,
    manual_week_value: null,
    manual_week_set_at: null,
    is_postpartum: false,
    postpartum_start_date: null,
    high_risk_flags: [],
    fasting_status: 'not_applicable',
    locale: 'ar',
    ...overrides,
  };
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86_400_000);
}

Deno.test('unknown — no profile at all', () => {
  const status = getPregnancyStatus(null, new Date('2026-01-01'));
  assertEquals(status.mode, 'unknown');
});

Deno.test('unknown — tracking basis set but no reference date', () => {
  const status = getPregnancyStatus(
    profile({ tracking_basis: 'lmp' }),
    new Date('2026-01-01'),
  );
  assertEquals(status.mode, 'unknown');
});

Deno.test('unknown — manual_week without manual_week_set_at', () => {
  const status = getPregnancyStatus(
    profile({ tracking_basis: 'manual_week', manual_week_value: 10 }),
    new Date('2026-01-01'),
  );
  assertEquals(status.mode, 'unknown');
});

Deno.test('unknown — postpartum flagged but no start date', () => {
  const status = getPregnancyStatus(
    profile({ is_postpartum: true }),
    new Date('2026-01-01'),
  );
  assertEquals(status.mode, 'unknown');
});

Deno.test('lmp basis — computes week/trimester/month/weeksToDue', () => {
  const lmp = new Date('2025-08-01');
  const today = addDays(lmp, 23 * 7 + 3);
  const status = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    today,
  );

  assertEquals(status.mode, 'pregnant');
  assertEquals(status.week, 23);
  assertEquals(status.trimester, 2);
  assertEquals(status.weeksToDue, 17);
  assertEquals(status.month, 6);
});

Deno.test('due_date basis — resolves to LMP 280 days earlier', () => {
  const lmp = new Date('2025-08-01');
  const dueDate = addDays(lmp, 280);
  const today = addDays(lmp, 10 * 7);
  const status = getPregnancyStatus(
    profile({ tracking_basis: 'due_date', reference_date: dueDate.toISOString() }),
    today,
  );

  assertEquals(status.mode, 'pregnant');
  assertEquals(status.week, 10);
  assertEquals(status.trimester, 1);
});

Deno.test('conception_date basis — resolves to LMP 14 days earlier', () => {
  const lmp = new Date('2025-08-01');
  const conceptionDate = addDays(lmp, 14);
  const today = addDays(lmp, 15 * 7);
  const status = getPregnancyStatus(
    profile({
      tracking_basis: 'conception_date',
      reference_date: conceptionDate.toISOString(),
    }),
    today,
  );

  assertEquals(status.mode, 'pregnant');
  assertEquals(status.week, 15);
  assertEquals(status.trimester, 2);
});

Deno.test('manual_week basis — recomputes from elapsed days', () => {
  const setAt = new Date('2026-01-01');
  const today = addDays(setAt, 21);
  const status = getPregnancyStatus(
    profile({
      tracking_basis: 'manual_week',
      manual_week_value: 10,
      manual_week_set_at: setAt.toISOString(),
    }),
    today,
  );

  assertEquals(status.mode, 'pregnant');
  assertEquals(status.week, 13);
});

Deno.test('manual_week basis — same-day read is unchanged', () => {
  const setAt = new Date('2026-01-01');
  const status = getPregnancyStatus(
    profile({
      tracking_basis: 'manual_week',
      manual_week_value: 10,
      manual_week_set_at: setAt.toISOString(),
    }),
    setAt,
  );

  assertEquals(status.week, 10);
});

Deno.test('clamps below week 1 up to 1', () => {
  const lmp = new Date('2026-01-01');
  const today = addDays(lmp, 2);
  const status = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    today,
  );

  assertEquals(status.week, 1);
});

Deno.test('clamps above week 42 down to 42', () => {
  const lmp = new Date('2025-01-01');
  const today = addDays(lmp, 60 * 7);
  const status = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    today,
  );

  assertEquals(status.week, 42);
  assertEquals(status.weeksToDue, 0);
});

Deno.test('trimester boundary — week 13 vs 14', () => {
  const lmp = new Date('2026-01-01');
  const week13 = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    addDays(lmp, 13 * 7),
  );
  const week14 = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    addDays(lmp, 14 * 7),
  );

  assertEquals(week13.trimester, 1);
  assertEquals(week14.trimester, 2);
});

Deno.test('trimester boundary — week 27 vs 28', () => {
  const lmp = new Date('2026-01-01');
  const week27 = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    addDays(lmp, 27 * 7),
  );
  const week28 = getPregnancyStatus(
    profile({ tracking_basis: 'lmp', reference_date: lmp.toISOString() }),
    addDays(lmp, 28 * 7),
  );

  assertEquals(week27.trimester, 2);
  assertEquals(week28.trimester, 3);
});

Deno.test('postpartum — within 40 days is نفاس', () => {
  const birth = new Date('2026-01-01');
  const status = getPregnancyStatus(
    profile({ is_postpartum: true, postpartum_start_date: birth.toISOString() }),
    addDays(birth, 39),
  );

  assertEquals(status.mode, 'postpartum');
  assertEquals(status.daysPostpartum, 39);
  assertEquals(status.phase, 'نفاس');
});

Deno.test('postpartum — past 40 days is ما بعد النفاس', () => {
  const birth = new Date('2026-01-01');
  const status = getPregnancyStatus(
    profile({ is_postpartum: true, postpartum_start_date: birth.toISOString() }),
    addDays(birth, 41),
  );

  assertEquals(status.mode, 'postpartum');
  assertEquals(status.phase, 'ما بعد النفاس');
});

Deno.test('postpartum takes priority over any pregnancy tracking basis', () => {
  const birth = new Date('2026-01-01');
  const status = getPregnancyStatus(
    profile({
      tracking_basis: 'lmp',
      reference_date: new Date('2025-06-01').toISOString(),
      is_postpartum: true,
      postpartum_start_date: birth.toISOString(),
    }),
    addDays(birth, 5),
  );

  assertEquals(status.mode, 'postpartum');
});

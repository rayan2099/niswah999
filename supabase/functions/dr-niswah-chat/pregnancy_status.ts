// Pure pregnancy-week/postpartum engine backing the "طبيبة" chat's
// personalization. TS mirror of
// lib/features/pregnancy_profile/domain/services/pregnancy_status_engine.dart
// — kept in sync manually, same tradeoff already accepted for the red-flag
// keyword lists duplicated between this function and DrNiswahRedFlags.
//
// Never derives a week from vague phrasing — only from the explicit
// dates/values stored on a pregnancy_profile row. Returns mode: 'unknown'
// whenever required data is missing rather than guessing, so the chat
// backend knows to ask instead of assume.

export type TrackingBasis =
  | 'lmp'
  | 'due_date'
  | 'conception_date'
  | 'manual_week';

export type FastingStatus =
  | 'not_applicable'
  | 'fasting'
  | 'not_fasting'
  | 'unsure';

export interface PregnancyProfileRow {
  tracking_basis: TrackingBasis | null;
  reference_date: string | null;
  manual_week_value: number | null;
  manual_week_set_at: string | null;
  is_postpartum: boolean;
  postpartum_start_date: string | null;
  high_risk_flags: string[];
  fasting_status: FastingStatus;
  locale: string;
}

export type Mode = 'pregnant' | 'postpartum' | 'unknown';

export interface PregnancyStatus {
  mode: Mode;
  week?: number;
  trimester?: number;
  month?: number;
  weeksToDue?: number;
  daysPostpartum?: number;
  phase?: string;
}

const POSTPARTUM_WINDOW_DAYS = 40;
const FULL_TERM_WEEKS = 40;
const MIN_WEEK = 1;
const MAX_WEEK = 42;
const WEEKS_PER_MONTH = 4.345;
const MS_PER_DAY = 86_400_000;

function daysBetween(from: Date, to: Date): number {
  return Math.floor((to.getTime() - from.getTime()) / MS_PER_DAY);
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function trimesterForWeek(week: number): number {
  if (week <= 13) return 1;
  if (week <= 27) return 2;
  return 3;
}

function monthForWeek(week: number): number {
  return clamp(Math.ceil(week / WEEKS_PER_MONTH), 1, 10);
}

// Converts whichever date the user actually gave us into an effective LMP
// date, so the rest of the engine only has one date-math path.
function resolveToLmp(profile: PregnancyProfileRow): Date | null {
  if (!profile.reference_date) return null;
  const referenceDate = new Date(profile.reference_date);

  switch (profile.tracking_basis) {
    case 'lmp':
      return referenceDate;
    case 'due_date':
      return new Date(referenceDate.getTime() - 280 * MS_PER_DAY);
    case 'conception_date':
      return new Date(referenceDate.getTime() - 14 * MS_PER_DAY);
    default:
      return null;
  }
}

function resolveWeek(profile: PregnancyProfileRow, today: Date): number | null {
  if (profile.tracking_basis === 'manual_week') {
    if (profile.manual_week_value == null || !profile.manual_week_set_at) {
      return null;
    }
    const elapsedDays = daysBetween(new Date(profile.manual_week_set_at), today);
    return profile.manual_week_value + Math.floor(elapsedDays / 7);
  }

  const lmpDate = resolveToLmp(profile);
  if (!lmpDate) return null;

  return Math.floor(daysBetween(lmpDate, today) / 7);
}

export function getPregnancyStatus(
  profile: PregnancyProfileRow | null,
  today: Date,
): PregnancyStatus {
  if (!profile) return { mode: 'unknown' };

  if (profile.is_postpartum) {
    if (!profile.postpartum_start_date) return { mode: 'unknown' };

    const days = daysBetween(new Date(profile.postpartum_start_date), today);
    return {
      mode: 'postpartum',
      daysPostpartum: days,
      phase: days <= POSTPARTUM_WINDOW_DAYS ? 'نفاس' : 'ما بعد النفاس',
    };
  }

  const week = resolveWeek(profile, today);
  if (week == null) return { mode: 'unknown' };

  const clampedWeek = clamp(week, MIN_WEEK, MAX_WEEK);
  return {
    mode: 'pregnant',
    week: clampedWeek,
    trimester: trimesterForWeek(clampedWeek),
    month: monthForWeek(clampedWeek),
    weeksToDue: Math.max(0, FULL_TERM_WEEKS - clampedWeek),
  };
}

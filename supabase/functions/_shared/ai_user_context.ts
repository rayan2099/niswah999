// Canonical AI User-State Context Layer.
//
// AICTX remediation wave (2026-09-09) — closes the root-cause finding
// (AICTX-5: no shared context-assembly layer existed) behind AICTX-1,
// AICTX-2, AICTX-4, AICTX-6, AICTX-7. See
// production-readiness-results/fiqh-engine/FIQH_AICTX_findings.md.
//
// ONE canonical assembly path, shared by all four AI Edge Functions
// (dr-niswah-chat, ai-assistant-chat, fiqh-advisor-chat,
// dream-interpreter-chat) — replaces four independent, mostly-empty,
// ad hoc context queries with one structured, provenance-labeled object.
//
// Identity/isolation contract (Phase C, non-negotiable):
//   - Every query in this module MUST go through the caller-supplied
//     `userClient` (a Supabase client scoped to the authenticated
//     request's own JWT, RLS-enforced) — never a service-role client,
//     never a client-supplied user_id. auth.uid() (derived from the
//     JWT by Postgres itself) is the only source of identity. This
//     module never accepts a userId parameter for *querying* — only for
//     labeling the object it already fetched under that identity.
//
// Deterministic-state authority contract (Phase A/I):
//   - Raw facts (pregnancy_profile, cycle_entries, wellbeing_logs) are
//     server-persisted and this module is authoritative for them —
//     fetched fresh on every call, never cached.
//   - The deterministic fiqh classification (haid/tahara/needsAdvisory/
//     insufficientHistory) is NOT recomputed here. It exists today only
//     as a client-side algorithm (MadhhabRuleEvaluator, Dart) — there is
//     no second, server-side reimplementation, deliberately: duplicating
//     fiqh logic in two languages is exactly the drift risk FIQH-5
//     already flagged for two *Dart* copies, and doing it a third time
//     in TypeScript would make that worse, not better. Per the charter's
//     own Phase C instruction ("where relevant state genuinely exists
//     only in current client/runtime state: handle it explicitly and
//     mark its provenance rather than pretending it came from the
//     database"), this module accepts an OPTIONAL client-supplied
//     `clientFiqhState` field, labels it `classificationSource:
//     'client_computed'`, and never treats it as independently
//     server-verified. If absent, `classificationSource: 'not_provided'`
//     and `uncertainty` says so explicitly — the AI is told to ask
//     rather than guess. This is a real, disclosed limitation, tracked
//     as AICTX-10 (see findings doc) rather than silently accepted.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  getPregnancyStatus,
  type PregnancyProfileRow as SharedPregnancyProfileRow,
} from './pregnancy_status.ts';

export type ContextScope =
  | 'dr_niswah'
  | 'general_assistant'
  | 'fiqh_advisor'
  | 'dream_interpreter';

export interface UserAiContext {
  contextVersion: '1';
  generatedAt: string;
  /**
   * Mirrors pregnancy_status.ts's own `PregnancyStatus` exactly — deliberately
   * NOT reimplemented here. 'unknown' covers both "confirmed not pregnant"
   * and "no data yet" because the app's own pregnancy_profile model does not
   * currently distinguish the two (a pre-existing app design fact, not
   * something introduced by this module — see AICTX-11 in the findings doc).
   */
  pregnancy: {
    mode: 'pregnant' | 'postpartum' | 'unknown';
    week?: number;
    trimester?: number;
    approxMonth?: number;
    weeksToDue?: number;
    daysPostpartum?: number;
    fastingStatus?: string;
    highRiskFlags: string[];
    locale?: string;
    source: 'pregnancy_profile_table';
  };
  menstrualCycle: {
    hasHistory: boolean;
    isCurrentlyBleeding: boolean | null;
    daysIntoCurrentEpisode: number | null;
    lastEntryDate: string | null;
    totalLoggedEntries: number;
    source: 'cycle_entries_table';
    /** Informational scan for AI context only — NOT a fiqh ruling. See fiqh block for the deterministic classification. */
    note: string;
  };
  fiqh: {
    madhhab: string | null;
    madhhabSource: 'client_supplied' | 'not_provided';
    /**
     * Fiqh Remediation Wave 1 (AUTH-005/AUTH-010, Section F): distinguishes
     * UNKNOWN ("I don't know my Madhhab" — explicit) from UNSET (never
     * answered) from SELECTED (a real madhhab) — never collapsed into one
     * another. 'not_provided' covers an older client build that predates
     * this field; treated identically to 'unset' by every prompt (never a
     * reason to assume a madhhab).
     */
    madhhabState: 'unset' | 'unknown' | 'selected' | 'not_provided';
    classification: string | null;
    classificationSource: 'client_computed' | 'not_provided';
    uncertainty: string;
  };
  wellbeing: {
    recentEntries: Array<{
      date: string;
      mood: number;
      energy: number;
      sleep: number;
      notes: string | null;
    }>;
    source: 'wellbeing_logs_table';
  };
  symptoms: {
    recent: Array<{ date: string; severities: Record<string, number> }>;
    source: 'cycle_entries_symptoms_field';
  };
  notes: {
    recent: Array<{ date: string; text: string; source: 'cycle_entries' | 'wellbeing_logs' }>;
  };
  safetyFlags: string[];
  dataFreshness: {
    fetchedAt: string;
  };
}

interface CycleEntryRow {
  date: string;
  flow: string;
  symptoms: string[] | null;
  notes: string | null;
}

// AICTX-13, resolved 2026-09-09: production `wellbeing_logs` was missing
// its `notes` column (a migration for it was authored 2026-08-27 but
// never applied — see supabase/migrations/20260909100000_wellbeing_logs_notes.sql
// for the full history), discovered live during this wave's Phase L
// synthetic verification, at the time worked around by not selecting
// `notes` from this table at all. Now that the column exists in
// production (and in the canonical baseline), this module selects and
// surfaces it like any other real field.
interface WellbeingLogRow {
  log_date: string;
  mood: number;
  energy: number;
  sleep: number;
  notes: string | null;
}

const MS_PER_DAY = 86_400_000;

// Thin adapter over the real, shared, already-tested pregnancy_status.ts —
// deliberately not reimplemented here (see the file-header note on why a
// third copy of any deterministic domain logic is exactly the drift risk
// this whole remediation wave exists to reduce, not add to).
function derivePregnancyContext(
  profile: SharedPregnancyProfileRow | null,
  now: Date,
): UserAiContext['pregnancy'] {
  const status = getPregnancyStatus(profile, now);
  return {
    mode: status.mode,
    week: status.week,
    trimester: status.trimester,
    approxMonth: status.month,
    weeksToDue: status.weeksToDue,
    daysPostpartum: status.daysPostpartum,
    fastingStatus: profile?.fasting_status ?? undefined,
    highRiskFlags: profile?.high_risk_flags ?? [],
    locale: profile?.locale ?? undefined,
    source: 'pregnancy_profile_table',
  };
}

// Exported (not just internal) so the encoding/decoding contract shared with
// lib/features/cycle_tracking/domain/services/cycle_symptom_decoder.dart
// (the Dart original) can be unit-tested directly — see ai_user_context.test.ts.
export function decodeSymptomSeverities(raw: string[] | null): Record<string, number> {
  const reserved = new Set(['energy', 'sleep', 'color', 'mood', 'notes']);
  const severities: Record<string, number> = {};
  for (const entry of raw ?? []) {
    const separatorIndex = entry.indexOf(':');
    if (separatorIndex < 0) continue;
    const key = entry.slice(0, separatorIndex);
    const value = entry.slice(separatorIndex + 1);
    if (reserved.has(key)) continue;
    const severity = Number.parseInt(value, 10);
    if (!Number.isNaN(severity) && severity > 0) severities[key] = severity;
  }
  return severities;
}

export function decodeLegacyNote(raw: string[] | null): string | null {
  for (const entry of raw ?? []) {
    if (entry.startsWith('notes:')) return entry.slice('notes:'.length);
  }
  return null;
}

type DatedNote = { date: string; text: string; source: 'cycle_entries' | 'wellbeing_logs' };

// AICTX-13: merges notes from both real sources (cycle_entries, now
// wellbeing_logs too — see WellbeingLogRow's comment) into one
// date-descending, limit-bounded list. Extracted as its own pure function
// so this merge behavior is directly unit-testable, not just exercised
// indirectly through buildUserAiContext's DB calls.
export function mergeNotesSources(
  cycleNotes: DatedNote[],
  wellbeingNotes: DatedNote[],
  limit: number,
): DatedNote[] {
  return [...cycleNotes, ...wellbeingNotes]
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, limit);
}

/**
 * Fetches and assembles the full canonical context for the authenticated
 * user (identity taken from `userClient`'s own JWT via RLS — never from a
 * parameter). Callers then narrow it to their AI's relevance scope via
 * `formatContextBlock`. Every field carries its own source/provenance —
 * nothing here is presented as more certain than it actually is.
 */
export async function buildUserAiContext(
  userClient: SupabaseClient,
  options: {
    clientMadhhab?: string | null;
    /** Fiqh Remediation Wave 1, Section F — 'unset' | 'unknown' | 'selected'. */
    clientMadhhabState?: string | null;
    clientFiqhState?: string | null;
    notesLimit?: number;
    wellbeingLimit?: number;
    cycleHistoryDays?: number;
    now?: Date;
    /** Safety flags the caller already detected for the CURRENT message (e.g. dr-niswah-chat's own real-time red-flag keyword scan) — passed through, not derived here. */
    currentMessageSafetyFlags?: string[];
  } = {},
): Promise<UserAiContext> {
  const now = options.now ?? new Date();
  const notesLimit = options.notesLimit ?? 5;
  const wellbeingLimit = options.wellbeingLimit ?? 5;
  const cycleHistoryDays = options.cycleHistoryDays ?? 60;
  const cycleHistorySince = new Date(now.getTime() - cycleHistoryDays * MS_PER_DAY)
    .toISOString()
    .slice(0, 10);

  const [pregnancyResult, cycleResult, wellbeingResult] = await Promise.all([
    userClient
      .from('pregnancy_profile')
      .select(
        'tracking_basis, reference_date, manual_week_value, manual_week_set_at, is_postpartum, postpartum_start_date, high_risk_flags, fasting_status, locale',
      )
      .maybeSingle(),
    userClient
      .from('cycle_entries')
      .select('date, flow, symptoms, notes')
      .gte('date', cycleHistorySince)
      .order('date', { ascending: false })
      .limit(200),
    userClient
      .from('wellbeing_logs')
      .select('log_date, mood, energy, sleep, notes')
      .order('log_date', { ascending: false })
      .limit(wellbeingLimit),
  ]);

  const pregnancyProfile = (pregnancyResult.data as SharedPregnancyProfileRow | null) ?? null;
  const cycleEntries = (cycleResult.data as CycleEntryRow[] | null) ?? [];
  const wellbeingLogs = (wellbeingResult.data as WellbeingLogRow[] | null) ?? [];

  // Sort ascending by date for the episode scan (mirrors CycleStatusEngine's
  // own sort direction), then read backward from the latest entry.
  const sortedAscending = [...cycleEntries].sort((a, b) => a.date.localeCompare(b.date));
  const latest = sortedAscending[sortedAscending.length - 1] ?? null;
  const hasHistory = cycleEntries.length > 0;
  let isCurrentlyBleeding: boolean | null = null;
  let daysIntoCurrentEpisode: number | null = null;

  if (latest) {
    isCurrentlyBleeding = latest.flow !== 'none';
    if (isCurrentlyBleeding) {
      let activeStartIndex = sortedAscending.length - 1;
      for (let i = sortedAscending.length - 1; i >= 0; i--) {
        if (sortedAscending[i].flow === 'none') break;
        activeStartIndex = i;
      }
      const activeStart = new Date(sortedAscending[activeStartIndex].date);
      daysIntoCurrentEpisode =
        Math.max(0, Math.floor((now.getTime() - activeStart.getTime()) / MS_PER_DAY)) + 1;
    }
  }

  const fiqhUncertainty = options.clientFiqhState
    ? 'none'
    : 'Deterministic fiqh classification was not supplied by the client this call — do not assume a classification.';

  const symptomsRecent = sortedAscending
    .slice(-10)
    .reverse()
    .map((entry) => ({
      date: entry.date,
      severities: decodeSymptomSeverities(entry.symptoms),
    }))
    .filter((entry) => Object.keys(entry.severities).length > 0);

  const cycleNotes = sortedAscending
    .filter((entry) => (entry.notes && entry.notes.trim()) || decodeLegacyNote(entry.symptoms))
    .reverse()
    .slice(0, notesLimit)
    .map((entry) => ({
      date: entry.date,
      text: (entry.notes && entry.notes.trim()) || decodeLegacyNote(entry.symptoms) || '',
      source: 'cycle_entries' as const,
    }));

  const wellbeingNotes = wellbeingLogs
    .filter((log) => log.notes && log.notes.trim())
    .map((log) => ({
      date: log.log_date,
      text: log.notes!.trim(),
      source: 'wellbeing_logs' as const,
    }));

  const combinedNotes = mergeNotesSources(cycleNotes, wellbeingNotes, notesLimit);

  return {
    contextVersion: '1',
    generatedAt: now.toISOString(),
    pregnancy: derivePregnancyContext(pregnancyProfile, now),
    menstrualCycle: {
      hasHistory,
      isCurrentlyBleeding,
      daysIntoCurrentEpisode,
      lastEntryDate: latest?.date ?? null,
      totalLoggedEntries: cycleEntries.length,
      source: 'cycle_entries_table',
      note:
        'isCurrentlyBleeding/daysIntoCurrentEpisode are an informational scan of recent flow entries for AI context only — NOT the deterministic fiqh ruling. See the fiqh block for that.',
    },
    fiqh: {
      madhhab: options.clientMadhhab ?? null,
      madhhabSource: options.clientMadhhab ? 'client_supplied' : 'not_provided',
      madhhabState:
        options.clientMadhhabState === 'unset' ||
        options.clientMadhhabState === 'unknown' ||
        options.clientMadhhabState === 'selected'
          ? options.clientMadhhabState
          : 'not_provided',
      classification: options.clientFiqhState ?? null,
      classificationSource: options.clientFiqhState ? 'client_computed' : 'not_provided',
      uncertainty: fiqhUncertainty,
    },
    wellbeing: {
      recentEntries: wellbeingLogs.slice(0, wellbeingLimit).map((log) => ({
        date: log.log_date,
        mood: log.mood,
        energy: log.energy,
        sleep: log.sleep,
        notes: log.notes && log.notes.trim() ? log.notes.trim() : null,
      })),
      source: 'wellbeing_logs_table',
    },
    symptoms: {
      recent: symptomsRecent,
      source: 'cycle_entries_symptoms_field',
    },
    notes: {
      recent: combinedNotes,
    },
    safetyFlags: options.currentMessageSafetyFlags ?? [],
    dataFreshness: {
      fetchedAt: now.toISOString(),
    },
  };
}

/**
 * Renders a `[CONTEXT]`-style text block for a given AI's relevance scope
 * (Phase D). Each scope includes only what that AI needs — never the full
 * object — per the charter's "minimum relevant context necessary" rule.
 * Every rendered line states whether it is a raw fact, a deterministic
 * classification, or an informational scan, so the model is never handed
 * an unlabeled number it might mistake for certainty.
 */
export function formatContextBlock(context: UserAiContext, scope: ContextScope): string {
  const lines: string[] = [];

  const addPregnancy = () => {
    // Field name deliberately `mode` (not `pregnancy_mode`) — matches
    // dr-niswah-chat's existing, already-shipped system-prompt wording
    // ("إن كان mode=pregnant...") exactly, so this remediation doesn't
    // silently break that prompt's own field references.
    lines.push(`mode: ${context.pregnancy.mode}`);
    if (context.pregnancy.mode === 'pregnant') {
      lines.push(`pregnancy_week: ${context.pregnancy.week ?? 'unknown'}`);
      lines.push(`trimester: ${context.pregnancy.trimester ?? 'unknown'}`);
      lines.push(`approx_month: ${context.pregnancy.approxMonth ?? 'unknown'}`);
      lines.push(`weeks_to_due: ${context.pregnancy.weeksToDue ?? 'unknown'}`);
    } else if (context.pregnancy.mode === 'postpartum') {
      lines.push(`days_postpartum: ${context.pregnancy.daysPostpartum ?? 'unknown'}`);
    }
    lines.push(`fasting_status: ${context.pregnancy.fastingStatus ?? 'not_applicable'}`);
    lines.push(
      `high_risk_flags: ${context.pregnancy.highRiskFlags.length ? context.pregnancy.highRiskFlags.join(', ') : '[]'}`,
    );
    if (context.pregnancy.locale) {
      lines.push(`locale: ${context.pregnancy.locale}`);
    }
  };

  const addCycle = () => {
    lines.push(`menstrual_history_exists: ${context.menstrualCycle.hasHistory}`);
    if (context.menstrualCycle.hasHistory) {
      lines.push(
        `menstrual_current_bleeding_observed (raw flow log, NOT a fiqh ruling): ${context.menstrualCycle.isCurrentlyBleeding}`,
      );
      if (context.menstrualCycle.daysIntoCurrentEpisode != null) {
        lines.push(`days_into_current_bleeding_episode: ${context.menstrualCycle.daysIntoCurrentEpisode}`);
      }
      lines.push(`last_cycle_entry_date: ${context.menstrualCycle.lastEntryDate}`);
    }
  };

  const addFiqh = () => {
    // Fiqh Remediation Wave 1, Section F: madhhab_state is always present
    // and always read before selected_madhhab — a model reading top-down
    // sees "unknown"/"unset" before it ever sees a null madhhab value, so
    // it cannot mistake "no value" for "not yet fetched."
    lines.push(`madhhab_state: ${context.fiqh.madhhabState}`);
    lines.push(`selected_madhhab: ${context.fiqh.madhhab ?? 'not_provided'}`);
    if (context.fiqh.madhhabState === 'unknown') {
      lines.push(
        'madhhab_unknown_note: the user explicitly said she does not know her madhhab — do not assume one, and do not treat this as a missing value to fill in.',
      );
    } else if (context.fiqh.madhhabState === 'unset' || context.fiqh.madhhabState === 'not_provided') {
      lines.push(
        'madhhab_unset_note: the user has not yet answered which madhhab she follows — do not assume one.',
      );
    }
    lines.push(
      `deterministic_fiqh_classification: ${context.fiqh.classification ?? 'not_provided'} (source: ${context.fiqh.classificationSource})`,
    );
    if (context.fiqh.uncertainty !== 'none') {
      lines.push(`fiqh_uncertainty: ${context.fiqh.uncertainty}`);
    }
  };

  const addWellbeing = () => {
    if (context.wellbeing.recentEntries.length) {
      const latest = context.wellbeing.recentEntries[0];
      lines.push(
        `wellbeing_most_recent (${latest.date}): mood=${latest.mood}/5, energy=${latest.energy}/5, sleep=${latest.sleep}/5`,
      );
      if (context.wellbeing.recentEntries.length > 1) {
        lines.push(`wellbeing_recent_entry_count: ${context.wellbeing.recentEntries.length}`);
      }
    } else {
      lines.push('wellbeing_recent_entries: none logged');
    }
  };

  const addSymptoms = () => {
    if (context.symptoms.recent.length) {
      const summary = context.symptoms.recent
        .slice(0, 3)
        .map((entry) => `${entry.date}: ${Object.entries(entry.severities).map(([k, v]) => `${k}=${v}`).join(', ')}`)
        .join(' | ');
      lines.push(`recent_symptoms (user-logged, not a diagnosis): ${summary}`);
    }
  };

  const addSafetyFlags = () => {
    if (context.safetyFlags.length) {
      lines.push(`current_message_safety_flags: ${context.safetyFlags.join(', ')}`);
    }
  };

  const addNotes = () => {
    if (context.notes.recent.length) {
      lines.push('recent_user_notes (user-authored statements, NOT verified facts):');
      for (const note of context.notes.recent) {
        lines.push(`  - [${note.date}] ${note.text}`);
      }
    }
  };

  switch (scope) {
    case 'dr_niswah':
      addPregnancy();
      addCycle();
      addWellbeing();
      addSymptoms();
      addSafetyFlags();
      addNotes();
      break;
    case 'general_assistant':
      addPregnancy();
      addCycle();
      addFiqh();
      addWellbeing();
      addNotes();
      break;
    case 'fiqh_advisor':
      addFiqh();
      addCycle();
      addPregnancy();
      break;
    case 'dream_interpreter':
      lines.push(`pregnancy_mode: ${context.pregnancy.mode}`);
      lines.push(`menstrual_history_exists: ${context.menstrualCycle.hasHistory}`);
      addWellbeing();
      addNotes();
      break;
  }

  return `[CONTEXT — internal, do not repeat verbatim to the user; raw facts and derived classifications are labeled, never invent or override them]\n${lines.join('\n')}\n[END CONTEXT]`;
}

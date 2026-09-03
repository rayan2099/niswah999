/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { Madhhab, State } from '../logic/types.ts';

export interface DBUser {
  id: string;
  email_hash: string;
  madhhab: Madhhab;
  language: string;
  birth_year: number;
  display_name: string;
  anonymous_mode: boolean;
  biometric_lock: boolean;
  premium_status: boolean;
  premium_expires_at: string | null;
  avg_cycle_length: number | null;
  avg_haid_duration: number;
  known_adah_days: number | null;
  adah_confidence: number;
  goal_flags: string[];
  conditions: string[];
  notification_prefs: Record<string, any>;
  prayerCity?: string;
  prayerCountry?: string;
  prayerCityAr?: string;
  prayerCountryAr?: string;
  prayerLat?: number;
  prayerLon?: number;
  location_name?: string;
  manual_prayer_offsets?: Record<string, number>;
  created_at: string;
  updated_at: string;
}

export interface DBCycleEntry {
  id: string;
  user_id: string;
  date: string;
  time_logged: string;
  fiqh_state: State;
  flow_intensity: 'none' | 'spotting' | 'light' | 'medium' | 'heavy';
  blood_color: 'red' | 'dark' | 'brown' | 'pink' | 'other';
  blood_thickness: 'thick' | 'thin' | 'normal';
  kursuf_used: boolean;
  discharge_internal: boolean;
  is_predicted: boolean;
  prediction_confidence: number;
  ramadan_day: number | null;
  fasting_status: 'obligatory' | 'lifted' | 'qadha' | null;
  notes: string | null;
  created_at: string;
}

export interface DBSymptomLog {
  id: string;
  user_id: string;
  cycle_entry_id: string | null;
  date: string;
  symptom_type: string;
  severity: number;
  body_location: string | null;
  notes: string | null;
  created_at: string;
}

export interface DBPrayerLog {
  id: string;
  user_id: string;
  date: string;
  prayer_name: 'fajr' | 'dhuhr' | 'asr' | 'maghrib' | 'isha';
  scheduled_time: string | null;
  status: 'prayed' | 'qadha_required' | 'lifted' | 'missed';
  fiqh_state_at_time: string | null;
  period_started_after_prayer_entered: boolean | null;
  notes: string | null;
}

export interface DBAdahLedger {
  id: string;
  user_id: string;
  cycle_number: number;
  haid_start: string;
  haid_end: string | null;
  haid_duration_hours: number | null;
  tuhr_duration_days: number | null;
  blood_color_pattern: string[];
  blood_thickness_pattern: string[];
  istihadah_episode: boolean;
  scholar_consulted: boolean;
  notes: string | null;
}

export interface DBIstihadahEpisode {
  id: string;
  user_id: string;
  start_date: string | null;
  end_date: string | null;
  madhhab_at_time: string | null;
  tamyiz_applied: boolean;
  blood_distinguishable: boolean | null;
  reverted_to_adah: boolean;
  adah_days_used: number | null;
  notes: string | null;
}

export interface DBNifasRecord {
  id: string;
  user_id: string;
  birth_date: string;
  madhhab_max_days: 40 | 60;
  expected_end: string | null;
  actual_end: string | null;
  breastfeeding_started: boolean;
  notes: string | null;
}

export interface DBRamadanRecord {
  id: string;
  user_id: string;
  hijri_year: number;
  total_missed_fasting: number;
  qadha_completed: number;
  qadha_schedule: string[];
}

export interface DBPregnancyRecord {
  id: string;
  user_id: string;
  lmp_date: string | null;
  due_date: string | null;
  current_week: number | null;
  birth_date: string | null;
  nifas_id: string | null;
  weekly_notes: Record<string, any>;
}

export interface DBSecretVaultEntry {
  id: string;
  user_id: string;
  encrypted_content: string;
  entry_type: string;
  created_at: string;
}

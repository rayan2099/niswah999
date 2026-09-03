/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export type Madhhab = 'HANAFI' | 'MALIKI' | 'SHAFII' | 'HANBALI';
export type State = 'TAHARA' | 'HAID' | 'NIFAS' | 'ISTIHADAH';

export const STATE_COLORS: Record<State, string> = {
  HAID: '#BE123C',
  TAHARA: '#0D9488',
  ISTIHADAH: '#4F46E5',
  NIFAS: '#D97706'
};

export interface AdahRecord {
  cycleNumber: number;
  haidStart: number; // timestamp
  haidEnd: number; // timestamp
  haidDurationHours: number;
  tuhrDurationDays: number;
  bloodColorPattern: string[];
  bloodThicknessPattern: string[];
  kursuFNotes?: string;
  istihadahEpisode: boolean;
  scholarConsulted: boolean;
}

export interface User {
  id?: string;
  uid?: string;
  madhhab: Madhhab;
  currentState: State;
  stateStartTime: number; // timestamp
  knownAdahDays: number | null; // Cycle length
  avgHaidDuration?: number | null; // Period length
  adahConfidence: number;
  adahLedger: AdahRecord[];
  prayerCity?: string;
  prayerCountry?: string;
  prayerCityAr?: string;
  prayerCountryAr?: string;
  prayerLat?: number;
  prayerLon?: number;
  locationName?: string;
  manualPrayerOffsets?: Record<string, number>;
  qadhaFastingDays: number;
  qadhaCompleted: number;
  qadhaRemaining: number;
  // Internal tracking
  pendingBloodStart: number | null;
  nifasMaxDays?: number;
  nifasStartTime?: number;
  scholarConsultationRequired?: boolean;
  pregnant?: boolean;
  conditions?: string[];
  display_name?: string;
  reflect_health?: boolean;
  notification_prefs?: Record<string, any>;
  anonymous_mode?: boolean;
  biometric_lock?: boolean;
  premium_status?: boolean;
  language?: string;
  avatar?: string;
}

export interface CycleStats {
  currentDay: number | null;
  avgCycleLength: number | null;
  avgPeriodLength: number | null;
  daysUntilNext: number | null;
  progress: number | null;
  isOverdue: boolean;
  overdueDays: number;
  regularity: number | null;
  lastPeriodDate: string | null;
}

export interface PrayerTime {
  name: string;
  adhanTime: number; // timestamp
  time: string; // ISO string for display/scheduling
}

export interface PredictionResult {
  predictedStartDate: number;
  predictedEndDate: number;
  confidenceScore: number;
  nextPeriodDate: string;
}

export interface OvulationResult {
  predictedOvulationDate: number;
  fertileWindowStart: number;
  fertileWindowEnd: number;
}

export interface CycleEntry {
  date: string;
  time_logged: string;
  fiqh_state: string;
  blood_details?: {
    intensity: string;
    color: string;
    thickness: string;
    kursuf?: {
      used: boolean;
      internal: boolean;
    };
  };
  symptoms?: string[];
  mood?: number;
  feeling?: string;
  notes?: string;
}

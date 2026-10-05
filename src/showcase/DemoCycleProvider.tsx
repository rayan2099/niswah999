import React from 'react';
import { CycleContext } from '../contexts/CycleContext.tsx';
import type { User, CycleStats, PredictionResult, OvulationResult, PrayerTime } from '../logic/types.ts';
import type { DBCycleEntry, DBAdahLedger, DBPrayerLog } from '../api/db-types.ts';

const user: User = {
  id: 'demo-user',
  uid: 'demo-user',
  madhhab: 'HANAFI',
  currentState: 'TAHARA',
  stateStartTime: Date.parse('2026-09-30T00:00:00Z'),
  knownAdahDays: 28,
  avgHaidDuration: 6,
  adahConfidence: 0.92,
  adahLedger: [],
  qadhaFastingDays: 0,
  qadhaCompleted: 0,
  qadhaRemaining: 0,
  pendingBloodStart: null,
  pregnant: false,
  conditions: [],
  display_name: 'سارة',
  language: 'ar',
  anonymous_mode: false,
  premium_status: true,
  prayerCity: 'Riyadh',
  prayerCountry: 'Saudi Arabia'
};

const entries: DBCycleEntry[] = Array.from({ length: 12 }).map((_, i) => ({
  id: 'demo-entry-'+i,
  user_id: 'demo-user',
  date: new Date(Date.UTC(2026, 8, 24 + i)).toISOString().slice(0,10),
  time_logged: '2026-09-24T08:00:00.000Z',
  fiqh_state: i < 6 ? 'HAID' : 'TAHARA',
  flow_intensity: i < 6 ? (i < 2 ? 'heavy' : 'medium') : 'none',
  blood_color: 'red',
  blood_thickness: 'normal',
  kursuf_used: false,
  discharge_internal: false,
  is_predicted: false,
  prediction_confidence: 1,
  ramadan_day: null,
  fasting_status: null,
  notes: null,
  created_at: '2026-09-24T08:00:00.000Z'
}));

const ledger: DBAdahLedger[] = [28,29,27,28,30,28].map((len,i)=>({
  id:'ledger-'+i,
  user_id:'demo-user',
  cycle_number: 6-i,
  haid_start: new Date(Date.UTC(2026, 3+i, 1)).toISOString(),
  haid_end: new Date(Date.UTC(2026, 3+i, 7)).toISOString(),
  haid_duration_hours: 144,
  tuhr_duration_days: len-6,
  blood_color_pattern:['red'],
  blood_thickness_pattern:['normal'],
  istihadah_episode:false,
  scholar_consulted:false,
  notes:null
}));

const cycleStats: CycleStats = {
  currentDay: 12,
  avgCycleLength: 28,
  avgPeriodLength: 6,
  daysUntilNext: 16,
  progress: 12/28,
  isOverdue: false,
  overdueDays: 0,
  regularity: 91,
  lastPeriodDate: '2026-09-24'
};

const prediction: PredictionResult = {
  predictedStartDate: Date.parse('2026-10-22T00:00:00Z'),
  predictedEndDate: Date.parse('2026-10-27T00:00:00Z'),
  confidenceScore: 0.91,
  nextPeriodDate: '2026-10-22'
};

const ovulation: OvulationResult = {
  predictedOvulationDate: Date.parse('2026-10-08T00:00:00Z'),
  fertileWindowStart: Date.parse('2026-10-05T00:00:00Z'),
  fertileWindowEnd: Date.parse('2026-10-10T00:00:00Z')
};

export function DemoCycleProvider({ children, pregnant = false }: { children: React.ReactNode; pregnant?: boolean }) {
  const demoUser = { ...user, pregnant };
  return (
    <CycleContext.Provider value={{
      user: demoUser,
      entries,
      ledger,
      prayers: [] as DBPrayerLog[],
      prayerTimes: [] as PrayerTime[],
      prayerTimesLoading: false,
      prayerTimesError: null,
      fiqhState: 'TAHARA',
      currentDay: 12,
      cycleStats,
      prediction,
      ovulation,
      nextPeriodDate: prediction.nextPeriodDate,
      loading: false,
      refresh: async () => {},
      updatePrayerTimes: async () => {}
    }}>
      {children}
    </CycleContext.Provider>
  );
}

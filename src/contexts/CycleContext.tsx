/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { createContext, useContext, useState, useEffect, ReactNode, useCallback, useMemo } from 'react';
import { onSnapshot, collection, query, where, orderBy, doc } from 'firebase/firestore';
import { auth, db } from '../firebase.ts';
import * as api from '../api/index.ts';
import * as logic from '../logic/index.ts';
import { notificationService } from '../services/NotificationService.ts';
import { State, User, CycleEntry, AdahRecord, Madhhab, PrayerTime, CycleStats, PredictionResult, OvulationResult } from '../logic/types.ts';
import { DBCycleEntry, DBAdahLedger, DBUser, DBPrayerLog } from '../api/db-types.ts';

interface CycleContextType {
  user: User | null;
  entries: DBCycleEntry[];
  ledger: DBAdahLedger[];
  prayers: DBPrayerLog[];
  prayerTimes: PrayerTime[];
  prayerTimesLoading: boolean;
  prayerTimesError: string | null;
  fiqhState: State;
  currentDay: number | null;
  cycleStats: CycleStats;
  prediction: PredictionResult | null;
  ovulation: OvulationResult | null;
  loading: boolean;
  nextPeriodDate: string | null;
  refresh: () => Promise<void>;
  updatePrayerTimes: (force?: boolean) => Promise<void>;
}

const CycleContext = createContext<CycleContextType | undefined>(undefined);

export const CycleProvider = ({ children }: { children: ReactNode }) => {
  const [dbUser, setDbUser] = useState<DBUser | null>(null);
  const [entries, setEntries] = useState<DBCycleEntry[]>([]);
  const [ledger, setLedger] = useState<DBAdahLedger[]>([]);
  const [prayers, setPrayers] = useState<DBPrayerLog[]>([]);
  const [prayerTimes, setPrayerTimes] = useState<PrayerTime[]>([]);
  const [prayerTimesLoading, setPrayerTimesLoading] = useState(false);
  const [prayerTimesError, setPrayerTimesError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Derived states using useMemo to avoid stale data and satisfy Scenario 5
  const user = useMemo(() => {
    if (!dbUser) return null;
    return api.mapDBUserToLogicUser(dbUser, ledger);
  }, [dbUser, ledger]);

  const fiqhState = useMemo(() => {
    if (!dbUser) return 'TAHARA' as State;
    return logic.calculateFiqhState(entries, dbUser.madhhab as Madhhab);
  }, [entries, dbUser?.madhhab]);

  const cycleStats = useMemo(() => {
    if (!user) {
      return {
        currentDay: null,
        daysUntilNext: null,
        isOverdue: false,
        overdueDays: 0,
        progress: null,
        avgCycleLength: null,
        avgPeriodLength: null,
        regularity: null,
        lastPeriodDate: null
      } as CycleStats;
    }
    return logic.calculateCycleStats(entries, user);
  }, [entries, user]);

  const currentDay = cycleStats.currentDay;

  const prediction = useMemo(() => {
    if (!user) return null;
    return logic.predictNextPeriod(user);
  }, [user]);

  const nextPeriodDate = prediction?.nextPeriodDate || null;

  const ovulation = useMemo(() => {
    if (!user) return null;
    return logic.predictOvulation(user);
  }, [user]);

  const loadInitialData = async () => {
    const { data: userData } = await api.getUser();
    const { data: ledgerData } = await api.getAdahLedger();
    const { data: entriesData } = await api.getCycleEntries();
    
    if (userData) {
      setDbUser(userData);
      setLedger(ledgerData || []);
      setEntries(entriesData || []);

      // Fetch prayer times early if city or coordinates are set
      const logicUser = api.mapDBUserToLogicUser(userData, ledgerData || []);
      if (logicUser && (logicUser.prayerCity || (logicUser.prayerLat && logicUser.prayerLon))) {
        logic.getPrayerTimes(logicUser, new Date()).then(({ times }) => {
          if (times.length > 0) {
            setPrayerTimes(times);
          }
        }).catch(err => {
          console.error("Initial prayer fetch failed", err);
          setPrayerTimesError("تعذّر تحميل أوقات الصلاة");
        });
      }
    }
    setLoading(false);
  };

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (firebaseUser) => {
      // Always load initial data (handles guest fallback)
      await loadInitialData();

      if (firebaseUser) {
        // Set up real-time listeners
        const entriesQuery = query(collection(db, `users/${firebaseUser.uid}/cycle_entries`));
        const ledgerQuery = query(collection(db, `users/${firebaseUser.uid}/adah_ledger`));
        const prayersQuery = query(collection(db, `users/${firebaseUser.uid}/prayer_log`));
        const userDoc = doc(db, `users/${firebaseUser.uid}`);

        const unsubEntries = onSnapshot(entriesQuery, (snapshot) => {
          const data = snapshot.docs.map(doc => doc.data() as DBCycleEntry);
          data.sort((a, b) => b.date.localeCompare(a.date) || (b.time_logged || '').localeCompare(a.time_logged || ''));
          setEntries(data);
        });

        const unsubLedger = onSnapshot(ledgerQuery, (snapshot) => {
          const data = snapshot.docs.map(doc => doc.data() as DBAdahLedger);
          data.sort((a, b) => b.cycle_number - a.cycle_number);
          setLedger(data);
        });

        const unsubPrayers = onSnapshot(prayersQuery, (snapshot) => {
          const data = snapshot.docs.map(doc => doc.data() as DBPrayerLog);
          setPrayers(data);
        });

        const unsubUser = onSnapshot(userDoc, (snapshot) => {
          if (snapshot.exists()) {
            const userData = snapshot.data() as DBUser;
            setDbUser(userData);
          }
        });

        return () => {
          unsubEntries();
          unsubLedger();
          unsubPrayers();
          unsubUser();
        };
      } else {
        setLoading(false);
      }
    });

    return () => unsubscribe();
  }, []);

  // Update logic user and state when raw data changes
  // Derived states are now handled by useMemo above

  const updatePrayerTimes = useCallback(async (force: boolean = false) => {
    if (user && (user.prayerCity || (user.prayerLat && user.prayerLon))) {
      setPrayerTimesLoading(true);
      setPrayerTimesError(null);
      try {
        const { times } = await logic.getPrayerTimes(user, new Date(), force);
        if (times.length > 0) {
          setPrayerTimes(times);
          localStorage.setItem('last_prayer_fetch_date', new Date().toISOString().split('T')[0]);
        } else {
          setPrayerTimesError("تعذّر تحميل أوقات الصلاة");
        }
      } catch (err) {
        console.error("Failed to fetch prayer times", err);
        setPrayerTimesError("تعذّر تحميل أوقات الصلاة");
      } finally {
        setPrayerTimesLoading(false);
      }
    }
  }, [user?.prayerCity, user?.prayerCountry, user?.madhhab, user?.manualPrayerOffsets, user?.prayerLat, user?.prayerLon]);

  // Fetch prayer times separately to optimize performance and avoid redundant calls
  useEffect(() => {
    updatePrayerTimes();

    // Check for daily update every hour
    const interval = setInterval(() => {
      const lastFetch = localStorage.getItem('last_prayer_fetch_date');
      const today = new Date().toISOString().split('T')[0];
      if (lastFetch !== today) {
        updatePrayerTimes(true);
        localStorage.setItem('last_prayer_fetch_date', today);
      }
    }, 3600000);

    return () => clearInterval(interval);
  }, [updatePrayerTimes]);

  useEffect(() => {
    if (user && prayerTimes.length > 0) {
      notificationService.schedulePrayerReminders(user, prayerTimes);
    }
  }, [user, prayerTimes]);

  useEffect(() => {
    if (user && prediction) {
      notificationService.scheduleCycleReminders(user, prediction);
    }
  }, [user, prediction]);

  return (
    <CycleContext.Provider value={{ 
      user, 
      entries, 
      ledger, 
      prayers, 
      prayerTimes,
      prayerTimesLoading,
      prayerTimesError,
      fiqhState, 
      currentDay, 
      cycleStats,
      prediction,
      ovulation,
      nextPeriodDate,
      loading,
      updatePrayerTimes,
      refresh: loadInitialData
    }}>
      {children}
    </CycleContext.Provider>
  );
};

export const useCycleData = () => {
  const context = useContext(CycleContext);
  if (context === undefined) {
    throw new Error('useCycleData must be used within a CycleProvider');
  }
  return context;
};

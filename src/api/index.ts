/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { 
  signInAnonymously as firebaseSignInAnonymously,
  onAuthStateChanged,
  User as FirebaseUser,
  getAuth
} from 'firebase/auth';
import { 
  doc, 
  getDoc, 
  setDoc, 
  updateDoc, 
  collection, 
  addDoc, 
  query, 
  where, 
  getDocs,
  onSnapshot,
  Timestamp,
  getDocFromServer,
  deleteDoc
} from 'firebase/firestore';
import { auth, db } from '../firebase.ts';
import CryptoJS from 'crypto-js';
import * as logic from '../logic/index.ts';
import { 
  DBUser, 
  DBCycleEntry, 
  DBSymptomLog, 
  DBPrayerLog, 
  DBAdahLedger, 
  DBIstihadahEpisode, 
  DBNifasRecord, 
  DBRamadanRecord, 
  DBPregnancyRecord, 
  DBSecretVaultEntry 
} from './db-types.ts';

export type { DBCycleEntry } from './db-types.ts';
export type ApiResponse<T> = { data: T | null; error: string | null };

// Helper to hash email
const hashEmail = (email: string) => CryptoJS.SHA256(email).toString();

// Operation types for error handling
enum OperationType {
  CREATE = 'create',
  UPDATE = 'update',
  DELETE = 'delete',
  LIST = 'list',
  GET = 'get',
  WRITE = 'write',
}

interface FirestoreErrorInfo {
  error: string;
  operationType: OperationType;
  path: string | null;
  authInfo: {
    userId: string | undefined;
    email: string | null | undefined;
    emailVerified: boolean | undefined;
    isAnonymous: boolean | undefined;
    tenantId: string | null | undefined;
    providerInfo: {
      providerId: string;
      displayName: string | null;
      email: string | null;
      photoUrl: string | null;
    }[];
  }
}

function handleFirestoreError(error: unknown, operationType: OperationType, path: string | null) {
  const errInfo: FirestoreErrorInfo = {
    error: error instanceof Error ? error.message : String(error),
    authInfo: {
      userId: auth.currentUser?.uid,
      email: auth.currentUser?.email,
      emailVerified: auth.currentUser?.emailVerified,
      isAnonymous: auth.currentUser?.isAnonymous,
      tenantId: auth.currentUser?.tenantId,
      providerInfo: auth.currentUser?.providerData.map(provider => ({
        providerId: provider.providerId,
        displayName: provider.displayName,
        email: provider.email,
        photoUrl: provider.photoURL
      })) || []
    },
    operationType,
    path
  }
  console.error('Firestore Error: ', JSON.stringify(errInfo));
  throw new Error(JSON.stringify(errInfo));
}

// API LAYER

export async function signInAnonymously() {
  try {
    const { user } = await firebaseSignInAnonymously(auth);
    return { data: user, error: null };
  } catch (error) {
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function getUser(): Promise<ApiResponse<DBUser>> {
  const user = auth.currentUser;
  if (!user) {
    const localUser = localStorage.getItem('niswah_local_user');
    if (localUser) {
      return { data: JSON.parse(localUser), error: null };
    }
    return { data: null, error: 'Not authenticated' };
  }

  const path = `users/${user.uid}`;
  try {
    const userDoc = await getDoc(doc(db, path));
    if (userDoc.exists()) {
      const data = userDoc.data() as DBUser;
      data.premium_status = true; // Freemium for now
      return { data, error: null };
    }
    return { data: null, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.GET, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function upsertUser(updates: Partial<DBUser>): Promise<ApiResponse<DBUser>> {
  const user = auth.currentUser;
  
  const defaults: Partial<DBUser> = {
    birth_year: 1995,
    display_name: 'Sister',
    anonymous_mode: false,
    biometric_lock: false,
    premium_status: true,
    adah_confidence: 0,
    prayerCity: '',
    prayerCountry: '',
    prayerCityAr: '',
    prayerCountryAr: '',
    prayerLat: 0,
    prayerLon: 0,
    goal_flags: [],
    conditions: [],
    notification_prefs: {},
    created_at: new Date().toISOString()
  };

  if (!user) {
    console.warn("Not authenticated, using local storage fallback for upsertUser");
    const localUser: DBUser = {
      ...defaults,
      ...updates,
      id: 'demo-user-id',
      email_hash: 'demo-hash',
      updated_at: new Date().toISOString()
    } as DBUser;
    localStorage.setItem('niswah_local_user', JSON.stringify(localUser));
    return { data: localUser, error: null };
  }

  const path = `users/${user.uid}`;
  try {
    const userData: DBUser = {
      ...defaults,
      ...updates,
      id: user.uid,
      email_hash: hashEmail(user.email || ''),
      updated_at: new Date().toISOString()
    } as DBUser;

    await setDoc(doc(db, path), userData, { merge: true });
    userData.premium_status = true; // Freemium for now
    return { data: userData, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.WRITE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function updateUser(updates: Partial<DBUser>): Promise<ApiResponse<DBUser>> {
  const user = auth.currentUser;
  if (!user) {
    const localUserStr = localStorage.getItem('niswah_local_user');
    if (localUserStr) {
      const localUser = JSON.parse(localUserStr);
      const updatedUser = { ...localUser, ...updates, updated_at: new Date().toISOString() };
      localStorage.setItem('niswah_local_user', JSON.stringify(updatedUser));
      return { data: updatedUser, error: null };
    }
    return { data: null, error: 'Not authenticated' };
  }

  const path = `users/${user.uid}`;
  try {
    const updateData = { ...updates, updated_at: new Date().toISOString() };
    await setDoc(doc(db, path), updateData, { merge: true });
    const updatedDoc = await getDoc(doc(db, path));
    const data = updatedDoc.data() as DBUser;
    data.premium_status = true; // Freemium for now
    return { data, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.UPDATE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function updateMadhhab(madhhab: logic.Madhhab): Promise<ApiResponse<DBUser>> {
  return updateUser({ madhhab });
}

export async function logCycleEntry(entry: Partial<DBCycleEntry>): Promise<ApiResponse<DBCycleEntry>> {
  const user = auth.currentUser;
  
  const defaults: Partial<DBCycleEntry> = {
    flow_intensity: 'medium',
    blood_color: 'red',
    blood_thickness: 'normal',
    kursuf_used: false,
    discharge_internal: false,
    is_predicted: false,
    prediction_confidence: 1,
    created_at: new Date().toISOString()
  };

  if (!user) {
    console.warn("Not authenticated, using local storage fallback for logCycleEntry");
    const localEntry: DBCycleEntry = {
      ...defaults,
      ...entry,
      id: Math.random().toString(36).substr(2, 9),
      user_id: 'demo-user-id',
    } as DBCycleEntry;
    const existing = JSON.parse(localStorage.getItem('niswah_local_entries') || '[]');
    localStorage.setItem('niswah_local_entries', JSON.stringify([...existing, localEntry]));
    return { data: localEntry, error: null };
  }

  const path = `users/${user.uid}/cycle_entries`;
  try {
    const entryData: DBCycleEntry = {
      ...defaults,
      ...entry,
      user_id: user.uid
    } as DBCycleEntry;

    const docRef = await addDoc(collection(db, path), entryData);
    entryData.id = docRef.id;
    await updateDoc(docRef, { id: docRef.id });
    return { data: entryData, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.CREATE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

// Firebase initialized
export async function logSymptoms(symptoms: Partial<DBSymptomLog>[]): Promise<ApiResponse<DBSymptomLog[]>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}/symptoms_log`;
  try {
    const results: DBSymptomLog[] = [];
    for (const symptom of symptoms) {
      const symptomData = { ...symptom, user_id: user.uid };
      const docRef = await addDoc(collection(db, path), symptomData);
      results.push({ ...symptomData, id: docRef.id } as DBSymptomLog);
    }
    return { data: results, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.CREATE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function updatePrayerStatus(prayer: string, status: string, date: string): Promise<ApiResponse<DBPrayerLog>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}/prayer_log`;
  const docId = `${date}_${prayer}`;
  try {
    const prayerData = { 
      user_id: user.uid, 
      date, 
      prayer_name: prayer as any, 
      status: status as any 
    };
    await setDoc(doc(db, path, docId), prayerData, { merge: true });
    return { data: { ...prayerData, id: docId } as DBPrayerLog, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.WRITE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function getCalendarData(month: number, year: number): Promise<ApiResponse<DBCycleEntry[]>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const startDate = new Date(year, month - 1, 1).toISOString().split('T')[0];
  const endDate = new Date(year, month, 0).toISOString().split('T')[0];

  const path = `users/${user.uid}/cycle_entries`;
  try {
    const q = query(
      collection(db, path),
      where('date', '>=', startDate),
      where('date', '<=', endDate)
    );
    const querySnapshot = await getDocs(q);
    const data = querySnapshot.docs.map(doc => doc.data() as DBCycleEntry);
    // Sort by date desc, then time_logged desc to ensure latest entry is first
    data.sort((a, b) => {
      const dateCompare = b.date.localeCompare(a.date);
      if (dateCompare !== 0) return dateCompare;
      return (b.time_logged || '').localeCompare(a.time_logged || '');
    });
    return { data, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.LIST, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function getCycleEntries(): Promise<ApiResponse<DBCycleEntry[]>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}/cycle_entries`;
  try {
    const q = query(
      collection(db, path)
      // Note: Firestore doesn't support multiple orderBys without composite indexes
      // We'll sort in memory for now if needed, or just return as is
    );
    const querySnapshot = await getDocs(q);
    const data = querySnapshot.docs.map(doc => doc.data() as DBCycleEntry);
    // Sort by date desc, then time_logged desc
    data.sort((a, b) => {
      const dateCompare = b.date.localeCompare(a.date);
      if (dateCompare !== 0) return dateCompare;
      return (b.time_logged || '').localeCompare(a.time_logged || '');
    });
    return { data, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.LIST, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function getAdahLedger(): Promise<ApiResponse<DBAdahLedger[]>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}/adah_ledger`;
  try {
    const q = query(collection(db, path));
    const querySnapshot = await getDocs(q);
    const data = querySnapshot.docs.map(doc => doc.data() as DBAdahLedger);
    data.sort((a, b) => b.cycle_number - a.cycle_number);
    return { data, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.LIST, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function getInsightsData(): Promise<ApiResponse<any>> {
  // This would be a complex query or an edge function call
  // For now, return basic stats
  const { data: user } = await getUser();
  if (!user) return { data: null, error: 'User not found' };

  return { 
    data: {
      avgCycleLength: user.avg_cycle_length,
      avgHaidDuration: user.avg_haid_duration,
      adahConfidence: user.adah_confidence
    }, 
    error: null 
  };
}

export function mapDBUserToLogicUser(userData: DBUser, ledger: DBAdahLedger[] = []): logic.User {
  const logicLedger: logic.AdahRecord[] = ledger.map(l => ({
    cycleNumber: l.cycle_number,
    haidStart: new Date(l.haid_start).getTime(),
    haidEnd: l.haid_end ? new Date(l.haid_end).getTime() : 0,
    haidDurationHours: l.haid_duration_hours || 0,
    tuhrDurationDays: l.tuhr_duration_days || 0,
    bloodColorPattern: l.blood_color_pattern || [],
    bloodThicknessPattern: l.blood_thickness_pattern || [],
    istihadahEpisode: l.istihadah_episode || false,
    scholarConsulted: l.scholar_consulted || false
  }));

  return {
    id: userData.id,
    madhhab: userData.madhhab as logic.Madhhab,
    currentState: 'TAHARA', // Default
    stateStartTime: Date.now(),
    knownAdahDays: userData.avg_cycle_length,
    avgHaidDuration: userData.avg_haid_duration,
    adahConfidence: userData.adah_confidence,
    adahLedger: logicLedger,
    prayerCity: userData.prayerCity,
    prayerCountry: userData.prayerCountry,
    prayerCityAr: userData.prayerCityAr,
    prayerCountryAr: userData.prayerCountryAr,
    prayerLat: userData.prayerLat,
    prayerLon: userData.prayerLon,
    locationName: userData.location_name,
    manualPrayerOffsets: userData.manual_prayer_offsets,
    qadhaFastingDays: 0,
    qadhaCompleted: 0,
    qadhaRemaining: 0,
    pendingBloodStart: null
  };
}

export async function getPredictions(): Promise<ApiResponse<logic.PredictionResult>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  // Simulate Edge Function: calculate-predictions
  const { data: ledger } = await getAdahLedger();
  const { data: userData } = await getUser();
  
  if (!userData) return { data: null, error: 'User not found' };
  const mockUser = mapDBUserToLogicUser(userData, ledger || []);
  const prediction = logic.predictNextPeriod(mockUser);
  return { data: prediction, error: null };
}

export async function markGhusulComplete(timestamp: number): Promise<ApiResponse<any>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}`;
  try {
    await updateDoc(doc(db, path), { 
      updated_at: new Date().toISOString() 
    });

    // Log the TAHARA state entry
    return logCycleEntry({
      date: new Date(timestamp).toISOString().split('T')[0],
      time_logged: new Date(timestamp).toISOString(),
      fiqh_state: 'TAHARA'
    });
  } catch (error) {
    handleFirestoreError(error, OperationType.UPDATE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function logBirthEvent(timestamp: number): Promise<ApiResponse<DBNifasRecord>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const { data: userData } = await getUser();
  if (!userData) return { data: null, error: 'User not found' };

  const maxDays = userData.madhhab === 'MALIKI' ? 60 : 40;
  const expectedEnd = new Date(timestamp + maxDays * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

  const path = `users/${user.uid}/nifas_records`;
  try {
    const nifasData = {
      user_id: user.uid,
      birth_date: new Date(timestamp).toISOString(),
      madhhab_max_days: maxDays,
      expected_end: expectedEnd
    };
    const docRef = await addDoc(collection(db, path), nifasData);
    return { data: { ...nifasData, id: docRef.id } as DBNifasRecord, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.CREATE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function getRamadanData(hijriYear: number): Promise<ApiResponse<DBRamadanRecord>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}/ramadan_records`;
  try {
    const q = query(collection(db, path), where('hijri_year', '==', hijriYear));
    const querySnapshot = await getDocs(q);
    if (!querySnapshot.empty) {
      return { data: querySnapshot.docs[0].data() as DBRamadanRecord, error: null };
    }
    return { data: null, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.LIST, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

export async function updateQadhaSchedule(dates: string[]): Promise<ApiResponse<DBRamadanRecord>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const path = `users/${user.uid}/ramadan_records`;
  try {
    const q = query(collection(db, path));
    const querySnapshot = await getDocs(q);
    if (!querySnapshot.empty) {
      const docRef = querySnapshot.docs[0].ref;
      await updateDoc(docRef, { qadha_schedule: dates });
      const updatedDoc = await getDoc(docRef);
      return { data: updatedDoc.data() as DBRamadanRecord, error: null };
    }
    return { data: null, error: 'Ramadan record not found' };
  } catch (error) {
    handleFirestoreError(error, OperationType.UPDATE, path);
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

// PDF Generation Placeholders (would be edge functions)
export async function generateFiqhReportPDF(): Promise<ApiResponse<string>> {
  return { data: "PDF_URL_PLACEHOLDER", error: null };
}

export async function generateDoctorReportPDF(): Promise<ApiResponse<string>> {
  return { data: "PDF_URL_PLACEHOLDER", error: null };
}

export async function deleteAccount(): Promise<ApiResponse<boolean>> {
  const user = auth.currentUser;
  if (!user) return { data: null, error: 'Not authenticated' };

  const uid = user.uid;
  const collections = [
    'cycle_entries',
    'adah_ledger',
    'prayer_log',
    'symptoms_log',
    'nifas_records',
    'ramadan_records',
    'pregnancy_records',
    'secret_vault'
  ];

  try {
    // Delete subcollections
    for (const collName of collections) {
      const q = query(collection(db, `users/${uid}/${collName}`));
      const snapshot = await getDocs(q);
      for (const d of snapshot.docs) {
        await deleteDoc(d.ref);
      }
    }

    // Delete user document
    await deleteDoc(doc(db, `users/${uid}`));

    // Delete auth user (might fail if not recently logged in, we catch and sign out anyway)
    try {
      await user.delete();
    } catch (e) {
      console.warn("Auth user deletion failed, signing out instead", e);
      await auth.signOut();
    }

    return { data: true, error: null };
  } catch (error) {
    handleFirestoreError(error, OperationType.DELETE, `users/${uid}`);
    return { data: false, error: error instanceof Error ? error.message : String(error) };
  }
}

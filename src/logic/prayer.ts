/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { 
  Coordinates, 
  CalculationMethod, 
  PrayerTimes, 
  Madhab 
} from 'adhan';
import { User, PrayerTime } from './types.ts';
import { popularCities } from './constants.ts';

export interface CityConfig {
  city: string;
  country: string;
  school: number;
}

export interface PrayerTimesResult {
  fajr: string;
  dhuhr: string;
  asr: string;
  maghrib: string;
  isha: string;
  city: string;
  country: string;
  date: string;
  fetchedAt: number;
}

function isValidTime(t: string): boolean {
  if (!t) return false;
  const parts = t.split(':');
  if (parts.length !== 2) return false;
  const h = parseInt(parts[0]);
  const m = parseInt(parts[1]);
  return !isNaN(h) && !isNaN(m)
         && h >= 0 && h <= 23
         && m >= 0 && m <= 59;
}

export async function fetchByCoords(
  lat: number,
  lon: number,
  date: string,
  school: number
): Promise<PrayerTimesResult | null> {
  const url = `https://api.aladhan.com/v1/timings/${date}` +
    `?latitude=${lat}` +
    `&longitude=${lon}` +
    `&method=4` + // Umm Al-Qura
    `&school=${school}`;

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);

    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timer);

    if (!res.ok) return null;

    const json = await res.json();
    if (json.code !== 200) return null;

    const t = json.data.timings;

    const parsed = {
      fajr:    t.Fajr?.split(' ')[0]?.trim(),
      dhuhr:   t.Dhuhr?.split(' ')[0]?.trim(),
      asr:     t.Asr?.split(' ')[0]?.trim(),
      maghrib: t.Maghrib?.split(' ')[0]?.trim(),
      isha:    t.Isha?.split(' ')[0]?.trim(),
    };

    const allValid = Object.values(parsed).every(isValidTime);
    if (!allValid) return null;

    return {
      ...parsed,
      city: 'Coordinates',
      country: 'Coordinates',
      date,
      fetchedAt: Date.now()
    };
  } catch {
    return null;
  }
}

export async function fetchByCity(
  config: CityConfig,
  date: string
): Promise<PrayerTimesResult | null> {

  const urls = [
    `https://api.aladhan.com/v1/timingsByCity/${date}` +
    `?city=${encodeURIComponent(config.city)}` +
    `&country=${config.country}` +
    `&method=4` + // Default to Umm Al-Qura
    `&school=${config.school}`,

    `https://api.aladhan.com/v1/timingsByAddress/${date}` +
    `?address=${encodeURIComponent(config.city + ', ' + config.country)}` +
    `&method=4` +
    `&school=${config.school}`
  ];

  for (const url of urls) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 12000);

      const res = await fetch(url, { signal: controller.signal });
      clearTimeout(timer);

      if (!res.ok) continue;

      const json = await res.json();
      if (json.code !== 200) continue;

      const t = json.data.timings;

      const parsed = {
        fajr:    t.Fajr?.split(' ')[0]?.trim(),
        dhuhr:   t.Dhuhr?.split(' ')[0]?.trim(),
        asr:     t.Asr?.split(' ')[0]?.trim(),
        maghrib: t.Maghrib?.split(' ')[0]?.trim(),
        isha:    t.Isha?.split(' ')[0]?.trim(),
      };

      const allValid = Object.values(parsed).every(isValidTime);
      if (!allValid) continue;

      return {
        ...parsed,
        city: config.city,
        country: config.country,
        date,
        fetchedAt: Date.now()
      };

    } catch {
      continue;
    }
  }

  return null;
}

function getCacheKey(city: string, country: string, lat?: number, lon?: number): string {
  const d = new Date();
  const dateStr = `${d.getDate()}-${d.getMonth()+1}-${d.getFullYear()}`;
  if (lat !== undefined && lon !== undefined) {
    return `prayer_coords_${lat.toFixed(4)}_${lon.toFixed(4)}_${dateStr}`;
  }
  return `prayer_${city}_${country}_${dateStr}`;
}

export function getCache(city: string, country: string, lat?: number, lon?: number): PrayerTimesResult | null {
  try {
    const key = getCacheKey(city, country, lat, lon);
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const data = JSON.parse(raw);
    // Verify it is for today
    const d = new Date();
    const today = `${d.getDate()}-${d.getMonth()+1}-${d.getFullYear()}`;
    if (data.date !== today) return null;
    return data;
  } catch {
    return null;
  }
}

export function setCache(times: PrayerTimesResult, lat?: number, lon?: number): void {
  try {
    const key = getCacheKey(times.city, times.country, lat, lon);
    localStorage.setItem(key, JSON.stringify(times));
    // Clean up old cache entries
    Object.keys(localStorage)
      .filter(k => k.startsWith('prayer_') && k !== key)
      .forEach(k => localStorage.removeItem(k));
  } catch {}
}

export async function getPrayerTimes(user: User, date: Date = new Date(), forceRefresh: boolean = false): Promise<{ times: PrayerTime[], isDefaultLocation: boolean }> {
  const hasCoords = user.prayerLat !== undefined && user.prayerLon !== undefined;
  const hasCity = !!user.prayerCity && !!user.prayerCountry;

  if (!hasCoords && !hasCity) {
    return { times: [], isDefaultLocation: false };
  }

  // Use adhan for local calculation if coordinates are available
  if (hasCoords) {
    const coords = new Coordinates(user.prayerLat!, user.prayerLon!);
    const params = CalculationMethod.MuslimWorldLeague();
    params.madhab = user.madhhab === 'HANAFI' ? Madhab.Hanafi : Madhab.Shafi;
    
    const prayerTimes = new PrayerTimes(coords, date, params);
    
    const times: PrayerTime[] = [
      { name: 'Fajr', adhanTime: prayerTimes.fajr.getTime(), time: prayerTimes.fajr.toISOString() },
      { name: 'Dhuhr', adhanTime: prayerTimes.dhuhr.getTime(), time: prayerTimes.dhuhr.toISOString() },
      { name: 'Asr', adhanTime: prayerTimes.asr.getTime(), time: prayerTimes.asr.toISOString() },
      { name: 'Maghrib', adhanTime: prayerTimes.maghrib.getTime(), time: prayerTimes.maghrib.toISOString() },
      { name: 'Isha', adhanTime: prayerTimes.isha.getTime(), time: prayerTimes.isha.toISOString() }
    ];
    
    return { times, isDefaultLocation: false };
  }

  const d = date;
  const dateStr = `${d.getDate()}-${d.getMonth()+1}-${d.getFullYear()}`;
  
  if (!forceRefresh) {
    const cached = getCache(user.prayerCity || '', user.prayerCountry || '', user.prayerLat, user.prayerLon);
    if (cached) {
      return { times: mapToPrayerTime(cached, date), isDefaultLocation: false };
    }
  }

  const school = user.madhhab === 'HANAFI' ? 1 : 0;
  let result: PrayerTimesResult | null = null;

  if (hasCoords) {
    result = await fetchByCoords(user.prayerLat!, user.prayerLon!, dateStr, school);
  }

  if (!result && hasCity) {
    const config: CityConfig = {
      city: user.prayerCity!,
      country: user.prayerCountry!,
      school
    };
    result = await fetchByCity(config, dateStr);
  }

  if (result) {
    setCache(result, user.prayerLat, user.prayerLon);
    return { times: mapToPrayerTime(result, date), isDefaultLocation: false };
  }

  throw new Error(`Failed to fetch prayer times for ${user.prayerCity || 'coordinates'}`);
}

function mapToPrayerTime(result: PrayerTimesResult, date: Date): PrayerTime[] {
  const prayers = [
    { name: 'Fajr', time: result.fajr },
    { name: 'Dhuhr', time: result.dhuhr },
    { name: 'Asr', time: result.asr },
    { name: 'Maghrib', time: result.maghrib },
    { name: 'Isha', time: result.isha }
  ];

  return prayers.map(p => {
    const [hours, minutes] = p.time.split(':').map(Number);
    const d = new Date(date);
    d.setHours(hours, minutes, 0, 0);
    return { 
      name: p.name, 
      adhanTime: d.getTime(),
      time: d.toISOString()
    };
  });
}

// Keep compatibility with existing code
export async function fetchPrayerTimes(user: User, date: Date, forceRefresh: boolean = false): Promise<PrayerTime[]> {
  const result = await getPrayerTimes(user, date, forceRefresh);
  return result.times;
}

export async function onHaidStarted(haidStartTimestamp: number, user: User): Promise<{ message: string, prayerStatus: Record<string, string> }> {
  const { times: prayers } = await getPrayerTimes(user, new Date(haidStartTimestamp));
  const status: Record<string, string> = {};
  
  for (const prayer of prayers) {
    if (prayer.adhanTime < haidStartTimestamp) {
      status[prayer.name] = 'QADHA_REQUIRED_IF_NOT_PRAYED';
    } else {
      status[prayer.name] = 'LIFTED';
    }
  }
  
  return { message: "Prayer status updated for today.", prayerStatus: status };
}

export async function onGhusulCompletePrayer(ghusulTimestamp: number, user: User): Promise<{ message: string, obligations: string[] }> {
  const { times: prayers } = await getPrayerTimes(user, new Date(ghusulTimestamp));
  const obligations: string[] = [];
  
  let currentPrayer: PrayerTime | null = null;
  let nextPrayer: PrayerTime | null = null;
  
  for (let i = 0; i < prayers.length; i++) {
    if (ghusulTimestamp >= prayers[i].adhanTime && (i === prayers.length - 1 || ghusulTimestamp < prayers[i+1].adhanTime)) {
      currentPrayer = prayers[i];
      nextPrayer = prayers[i+1] || null;
      break;
    }
  }

  if (!currentPrayer) return { message: "No active prayer window.", obligations: [] };

  const windowEnd = nextPrayer ? nextPrayer.adhanTime : (currentPrayer.adhanTime + 4 * 60 * 60 * 1000);
  const minutesRemaining = (windowEnd - ghusulTimestamp) / (1000 * 60);
  
  if (user.madhhab === 'HANAFI') {
    if (minutesRemaining >= 5) {
      obligations.push(currentPrayer.name);
      if (currentPrayer.name === 'Dhuhr') obligations.push('Asr');
      if (currentPrayer.name === 'Maghrib') obligations.push('Isha');
    }
  } else if (user.madhhab === 'SHAFII' || user.madhhab === 'HANBALI') {
    if (minutesRemaining >= 5) {
      obligations.push(currentPrayer.name);
    }
  } else if (user.madhhab === 'MALIKI') {
    if (minutesRemaining > 0) {
      obligations.push(currentPrayer.name);
    }
  }

  return { 
    message: `Ghusl complete with ${Math.round(minutesRemaining)} minutes remaining.`, 
    obligations 
  };
}

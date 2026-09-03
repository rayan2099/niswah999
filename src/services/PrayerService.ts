/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export interface PrayerTimes {
  Fajr: string;
  Sunrise: string;
  Dhuhr: string;
  Asr: string;
  Sunset: string;
  Maghrib: string;
  Isha: string;
  Imsak: string;
  Midnight: string;
}

export class PrayerService {
  private static API_BASE = 'https://api.aladhan.com/v1/timingsByCity';

  /**
   * Fetches prayer times for a given city and country.
   * This uses the Aladhan API which provides data consistent with major calculation methods.
   */
  static async getPrayerTimes(city: string, country: string): Promise<PrayerTimes | null> {
    try {
      const date = new Date().toISOString().split('T')[0]; // Current date in YYYY-MM-DD
      const url = `${this.API_BASE}/${date}?city=${encodeURIComponent(city)}&country=${encodeURIComponent(country)}&method=4`; // Defaulting to Umm Al-Qura as it's common in the region, but the user wants "Google-like" which usually matches local standards.
      
      const response = await fetch(url);
      if (!response.ok) throw new Error('Failed to fetch prayer times');
      
      const json = await response.json();
      if (json.code === 200 && json.data && json.data.timings) {
        return json.data.timings;
      }
      return null;
    } catch (error) {
      console.error('Error fetching prayer times:', error);
      return null;
    }
  }
}

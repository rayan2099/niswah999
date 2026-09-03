/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import * as api from '../api/index.ts';
import { format, parseISO, addMinutes, isBefore, isAfter } from 'date-fns';
import { User, PrayerTime } from '../logic/types.ts';

class NotificationService {
  private static instance: NotificationService;
  private permission: NotificationPermission = 'default';

  private constructor() {
    if (typeof window !== 'undefined' && 'Notification' in window) {
      this.permission = Notification.permission;
    }
  }

  public static getInstance(): NotificationService {
    if (!NotificationService.instance) {
      NotificationService.instance = new NotificationService();
    }
    return NotificationService.instance;
  }

  public async requestPermission(): Promise<boolean> {
    if (typeof window === 'undefined' || !('Notification' in window)) return false;
    
    const permission = await Notification.requestPermission();
    this.permission = permission;
    return permission === 'granted';
  }

  public async notify(title: string, options?: NotificationOptions) {
    if (this.permission !== 'granted') return;

    try {
      new Notification(title, {
        icon: '/logo192.png',
        badge: '/logo192.png',
        ...options
      });
    } catch (e) {
      console.error("Failed to show notification", e);
    }
  }

  public static async savePreferences(userId: string, prefs: object): Promise<void> {
    await api.updateUser({ notification_prefs: prefs });
  }

  public schedulePrayerReminders(user: User, prayerTimes: PrayerTime[]) {
    if (!user.notification_prefs?.prayer_alerts) return;

    prayerTimes.forEach(prayer => {
      const prayerTime = parseISO(prayer.time);
      const now = new Date();

      // Notify 5 minutes before
      const reminderTime = addMinutes(prayerTime, -5);
      
      if (isAfter(reminderTime, now)) {
        const delay = reminderTime.getTime() - now.getTime();
        setTimeout(() => {
          this.notify(`Upcoming Prayer: ${prayer.name}`, {
            body: `It's almost time for ${prayer.name}. Get ready for Salah!`,
            tag: `prayer-${prayer.name}-${prayer.time}`
          });
        }, delay);
      }
    });
  }

  public scheduleCycleReminders(user: User, prediction: any) {
    if (!user.notification_prefs?.haid_prediction_alerts || !prediction?.predictedStartDate) return;

    const startDate = parseISO(prediction.predictedStartDate);
    const now = new Date();
    
    // Notify 1 day before
    const reminderTime = addMinutes(startDate, -1440); // 24 hours
    
    if (isAfter(reminderTime, now)) {
      const delay = reminderTime.getTime() - now.getTime();
      setTimeout(() => {
        this.notify("Cycle Prediction", {
          body: "Your period is expected to start tomorrow. Be prepared!",
          tag: "cycle-prediction"
        });
      }, delay);
    }
  }

  public scheduleGhuslReminder(user: User) {
    if (!user.notification_prefs?.ghusl_reminders) return;
    
    // Notify in 30 minutes to check for purity/perform Ghusl
    setTimeout(() => {
      this.notify("Ghusl Reminder", {
        body: "It's been 30 minutes since you ended your period. Have you performed Ghusl?",
        tag: "ghusl-reminder"
      });
    }, 30 * 60 * 1000);
  }
}

export { NotificationService };
export const notificationService = NotificationService.getInstance();

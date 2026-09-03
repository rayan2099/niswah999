/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { User, Madhhab, State } from './types.ts';

// Part B — TRANSITION RULES

export function onBloodLogged(timestamp: number, user: User): { message: string, user: User } {
  const newUser = { ...user };
  
  if (newUser.madhhab === 'HANAFI') {
    // Start a 72-hour confirmation window
    if (!newUser.pendingBloodStart) {
      newUser.pendingBloodStart = timestamp;
      return { 
        message: "Blood logged. Awaiting 3-day confirmation per Hanafi school.", 
        user: newUser 
      };
    }
    
    const hoursPassed = (timestamp - newUser.pendingBloodStart) / (1000 * 60 * 60);
    if (hoursPassed >= 72) {
      newUser.currentState = 'HAID';
      newUser.stateStartTime = newUser.pendingBloodStart;
      newUser.pendingBloodStart = null;
      return { message: "HAID confirmed (Hanafi).", user: newUser };
    } else {
      return { 
        message: "Blood logged. Awaiting 3-day confirmation per Hanafi school.", 
        user: newUser 
      };
    }
  } else if (newUser.madhhab === 'SHAFII' || newUser.madhhab === 'HANBALI') {
    // Start a 24-hour confirmation window
    if (!newUser.pendingBloodStart) {
      newUser.pendingBloodStart = timestamp;
      return { message: "Blood logged. Awaiting 24-hour confirmation.", user: newUser };
    }
    
    const hoursPassed = (timestamp - newUser.pendingBloodStart) / (1000 * 60 * 60);
    if (hoursPassed >= 24) {
      newUser.currentState = 'HAID';
      newUser.stateStartTime = newUser.pendingBloodStart;
      newUser.pendingBloodStart = null;
      return { message: "HAID confirmed.", user: newUser };
    } else {
      return { message: "Blood logged. Awaiting 24-hour confirmation.", user: newUser };
    }
  } else if (newUser.madhhab === 'MALIKI') {
    // Immediately transition to HAID
    newUser.currentState = 'HAID';
    newUser.stateStartTime = timestamp;
    newUser.pendingBloodStart = null;
    return { message: "HAID began (Maliki).", user: newUser };
  }

  return { message: "Blood logged.", user: newUser };
}

export function onBloodStopped(timestamp: number, user: User): { message: string, user: User, event?: string } {
  const newUser = { ...user };
  const haidDurationHours = (timestamp - newUser.stateStartTime) / (1000 * 60 * 60);
  
  // Checks minimum purity gap (all Madhhabs: 15 days)
  // This is actually for the NEXT period, but let's check current HAID duration minimums
  // Hanafi: 3 days (72h), Others: 1 day (24h)
  let minHaidHours = 24;
  if (newUser.madhhab === 'HANAFI') minHaidHours = 72;
  
  let maxHaidHours = 360; // 15 days
  if (newUser.madhhab === 'HANAFI') maxHaidHours = 240; // 10 days

  if (haidDurationHours > maxHaidHours) {
    return enterIstihadahMode(newUser);
  }

  if (haidDurationHours >= minHaidHours) {
    return { 
      message: "Blood stopped. Pending TAHARA. Please perform Ghusl.", 
      user: newUser,
      event: 'GHUSL_REMINDER'
    };
  }

  return { message: "Blood stopped before minimum duration.", user: newUser };
}

export function onGhusulComplete(timestamp: number, user: User): { message: string, user: User, events: string[] } {
  const newUser = { ...user };
  newUser.currentState = 'TAHARA';
  newUser.stateStartTime = timestamp;
  
  return { 
    message: "Ghusl complete. You are now in TAHARA.", 
    user: newUser,
    events: ['TAHARA_BEGAN', 'PRAYER_STATUS_RECALCULATE']
  };
}

export function onBirthLogged(timestamp: number, user: User): { message: string, user: User, event?: string } {
  const newUser = { ...user };
  newUser.currentState = 'NIFAS';
  newUser.nifasStartTime = timestamp;
  
  if (newUser.madhhab === 'MALIKI') {
    newUser.nifasMaxDays = 60;
  } else {
    newUser.nifasMaxDays = 40;
  }
  
  newUser.stateStartTime = timestamp;
  
  return { 
    message: `Birth logged. State: NIFAS. Max duration: ${newUser.nifasMaxDays} days.`, 
    user: newUser,
    event: 'GHUSL_REMINDER' // Scheduled at max days
  };
}

export function checkNifasEnd(timestamp: number, user: User): { message: string, user: User, event?: string } {
  const newUser = { ...user };
  if (!newUser.nifasStartTime || !newUser.nifasMaxDays) return { message: "Not in NIFAS.", user: newUser };
  
  const daysPassed = (timestamp - newUser.nifasStartTime) / (1000 * 60 * 60 * 24);
  
  if (daysPassed < newUser.nifasMaxDays) {
    return { 
      message: "Nifas blood stopped early. Please perform Ghusl.", 
      user: newUser,
      event: 'GHUSL_REMINDER'
    };
  } else {
    newUser.currentState = 'TAHARA';
    newUser.stateStartTime = timestamp;
    return { 
      message: "Nifas maximum duration reached. Transitioning to TAHARA. Any further blood is ISTIHADAH.", 
      user: newUser 
    };
  }
}

// Part C — ISTIHADAH WORKFLOW

export function enterIstihadahMode(user: User): { message: string, user: User } {
  const newUser = { ...user };
  newUser.currentState = 'ISTIHADAH';

  if (newUser.madhhab === 'HANAFI') {
    if (newUser.knownAdahDays) {
      const adahHours = newUser.knownAdahDays * 24;
      return { 
        message: `Bleeding exceeded maximum. Per Hanafi: ${newUser.knownAdahDays} days are HAID, remaining are ISTIHADAH.`, 
        user: newUser 
      };
    } else {
      newUser.scholarConsultationRequired = true;
      return { 
        message: "Bleeding exceeded maximum. No established Adah. Using 6 days as working habit. Scholar consultation recommended.", 
        user: newUser 
      };
    }
  } else {
    return { 
      message: "Bleeding exceeded maximum. Entering Tamyiz (blood distinction) workflow. Classify blood daily.", 
      user: newUser 
    };
  }
}

// Part D — KURSUF LOGIC (Hanafi only)

export function kursuFCheck(user: User, hasBarrier: boolean, dischargeLocation: 'INTERNAL' | 'EXTERNAL_ONLY', timestamp: number): { message: string, user: User } {
  if (user.madhhab !== 'HANAFI') return { message: "Kursuf logic only applies to Hanafi madhhab.", user };
  
  // Only runs during Expected Start window (3 days before predicted period)
  // For now, we assume we are in that window if this function is called.
  
  const newUser = { ...user };
  if (hasBarrier) {
    if (dischargeLocation === 'INTERNAL') {
      newUser.currentState = 'HAID';
      newUser.stateStartTime = timestamp;
      return { message: "HAID begins (Internal Kursuf).", user: newUser };
    } else {
      return { message: "Continue your prayers for now", user: newUser };
    }
  } else {
    // Standard rules apply: Blood appearance = HAID begins
    newUser.currentState = 'HAID';
    newUser.stateStartTime = timestamp;
    return { message: "HAID begins (Blood appearance).", user: newUser };
  }
}

export function calculateFiqhState(entries: any[], madhhab: Madhhab): State {
  if (!entries || entries.length === 0) return 'TAHARA';
  
  // Get all logs where is_predicted !== true
  const actualEntries = entries.filter(e => e.is_predicted === false || e.is_predicted === undefined || e.is_predicted === null);

  if (actualEntries.length === 0) {
    // Predictions only apply if there are zero actual logs
    // For now, return TAHARA as default if no actual logs
    return 'TAHARA';
  }

  const getTimestamp = (entry: any) => {
    if (entry.time_logged && entry.time_logged.includes('T')) {
      try {
        const t = new Date(entry.time_logged).getTime();
        if (!isNaN(t)) return t;
      } catch (e) {}
    }
    
    const time = entry.time_logged || '00:00:00';
    try {
      const parts = time.split(':');
      const formattedTime = parts.length === 2 ? `${time}:00` : (parts.length === 3 ? time : '00:00:00');
      const t = new Date(`${entry.date}T${formattedTime}`).getTime();
      if (!isNaN(t)) return t;
    } catch (e) {}
    return new Date(entry.date).getTime();
  };

  // Sort by date descending
  const sorted = [...actualEntries].sort((a, b) => getTimestamp(b) - getTimestamp(a));
  
  // Take the most recent one
  const latest = sorted[0];
  
  // If its flow is anything other than "none" or null -> return HAID
  if (latest.flow_intensity && latest.flow_intensity !== 'none') {
    return 'HAID';
  }

  // If it explicitly marks end of period -> return TAHARA
  // (In this app, intensity 'none' is the end of period)
  if (latest.flow_intensity === 'none') {
    return 'TAHARA';
  }

  return 'TAHARA';
}

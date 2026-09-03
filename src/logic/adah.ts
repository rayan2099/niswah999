/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { User, AdahRecord } from './types.ts';

// Part E — ADAH (HABIT) TRACKING

export function calculateAdah(user: User): { user: User, averageHaidDays: number, averageTuhrDays: number } {
  const newUser = { ...user };
  const ledger = newUser.adahLedger || [];
  
  if (ledger.length === 0) {
    return { user: newUser, averageHaidDays: 0, averageTuhrDays: 0 };
  }

  // Takes last 3-6 cycles from adahLedger
  const relevantCycles = ledger.slice(-6);
  
  const totalHaidHours = relevantCycles.reduce((sum, cycle) => sum + cycle.haidDurationHours, 0);
  const totalTuhrDays = relevantCycles.reduce((sum, cycle) => sum + cycle.tuhrDurationDays, 0);
  
  const averageHaidDays = (totalHaidHours / relevantCycles.length) / 24;
  const averageTuhrDays = totalTuhrDays / relevantCycles.length;
  
  newUser.knownAdahDays = Math.round(averageHaidDays);
  
  // Confidence scoring
  const count = ledger.length;
  if (count >= 6) newUser.adahConfidence = 95;
  else if (count >= 3) newUser.adahConfidence = 70;
  else if (count >= 2) newUser.adahConfidence = 40;
  else if (count >= 1) newUser.adahConfidence = 20;
  else newUser.adahConfidence = 0;
  
  return { user: newUser, averageHaidDays, averageTuhrDays };
}

export function addAdahRecord(user: User, record: AdahRecord): User {
  const newUser = { ...user };
  if (!newUser.adahLedger) newUser.adahLedger = [];
  newUser.adahLedger.push(record);
  return calculateAdah(newUser).user;
}

/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { toHijri } from 'hijri-converter';
import { User } from './types.ts';

// Part G — RAMADAN INTEGRATION

export function isRamadan(date: Date): { isRamadan: boolean, dayNumber: number } {
  const hijri = toHijri(date.getFullYear(), date.getMonth() + 1, date.getDate());
  const isRamadan = hijri.hm === 9;
  return { isRamadan, dayNumber: isRamadan ? hijri.hd : 0 };
}

export function getRamadanFastingStatus(user: User, date: Date): 'LIFTED' | 'OBLIGATORY' {
  if (user.currentState === 'HAID' || user.currentState === 'NIFAS') {
    return 'LIFTED';
  }
  return 'OBLIGATORY';
}

export function trackQadha(user: User): { totalQadhaFastingDays: number, qadhaCompleted: number, qadhaRemaining: number } {
  // This would normally iterate over a history, but for now we just return the user's current qadha stats
  return { 
    totalQadhaFastingDays: user.qadhaFastingDays, 
    qadhaCompleted: user.qadhaCompleted, 
    qadhaRemaining: user.qadhaRemaining 
  };
}

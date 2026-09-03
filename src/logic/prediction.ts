/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { addDays, subDays, startOfDay, differenceInDays } from 'date-fns';
import { User, PredictionResult, OvulationResult, CycleStats } from './types.ts';

// Part H — PREDICTION ENGINE

export function getAverageCycleLength(user: User): number | null {
  const starts = [...new Set((user.adahLedger || [])
    .map(cycle => cycle.haidStart)
    .filter(start => Number.isFinite(start) && start > 0))]
    .sort((a, b) => a - b);
  if (starts.length < 2) return null;

  const intervals = starts.slice(1).map((start, index) =>
    differenceInDays(startOfDay(new Date(start)), startOfDay(new Date(starts[index])))
  ).filter(days => days > 0);
  if (intervals.length === 0) return null;
  return intervals.reduce((sum, days) => sum + days, 0) / intervals.length;
}

export function getAverageHaidDuration(user: User): number | null {
  const durations = (user.adahLedger || [])
    .map(cycle => cycle.haidDurationHours)
    .filter(hours => Number.isFinite(hours) && hours > 0);
  if (durations.length === 0) return null;
  return durations.reduce((sum, hours) => sum + hours, 0) / durations.length / 24;
}

export function predictNextPeriod(user: User): PredictionResult | null {
  const ledger = [...(user.adahLedger || [])].sort((a, b) => a.haidStart - b.haidStart);
  const averageCycleLengthDays = getAverageCycleLength(user);
  const averageHaidDurationDays = getAverageHaidDuration(user);
  if (ledger.length < 2 || averageCycleLengthDays === null) return null;

  const lastHaidStart = ledger[ledger.length - 1].haidStart;
  const predictedStartDate = addDays(new Date(lastHaidStart), averageCycleLengthDays).getTime();
  const predictedEndDate = averageHaidDurationDays === null
    ? predictedStartDate
    : addDays(new Date(predictedStartDate), averageHaidDurationDays).getTime();

  return {
    predictedStartDate,
    predictedEndDate,
    confidenceScore: user.adahConfidence,
    nextPeriodDate: new Date(predictedStartDate).toISOString()
  };
}

export function calculateRegularity(user: User): number | null {
  const starts = [...new Set((user.adahLedger || []).map(cycle => cycle.haidStart))]
    .filter(start => Number.isFinite(start) && start > 0)
    .sort((a, b) => a - b);
  if (starts.length < 3) return null;
  const cycleLengths = starts.slice(1).map((start, index) =>
    differenceInDays(startOfDay(new Date(start)), startOfDay(new Date(starts[index])))
  ).filter(days => days > 0);
  if (cycleLengths.length < 2) return null;
  
  const average = cycleLengths.reduce((a, b) => a + b, 0) / cycleLengths.length;
  const variance = cycleLengths.reduce((a, b) => a + Math.pow(b - average, 2), 0) / cycleLengths.length;
  const stdDev = Math.sqrt(variance);
  
  const regularity = 100 - (stdDev / average * 100);
  return Math.round(Math.min(100, Math.max(0, regularity)));
}

export function calculateCycleStats(entries: any[], user?: User): CycleStats {
  const cycleLength = user ? getAverageCycleLength(user) : null;
  const regularity = user ? calculateRegularity(user) : null;
  const haidStarts = user
    ? [...new Set((user.adahLedger || []).map(cycle => cycle.haidStart))]
        .filter(start => Number.isFinite(start) && start > 0)
        .sort((a, b) => a - b)
    : [];
  const periodLength = user ? getAverageHaidDuration(user) : null;

  if (haidStarts.length < 2 || cycleLength === null) {
    return { 
      currentDay: null,
      daysUntilNext: null,
      isOverdue: false, 
      overdueDays: 0,
      progress: null,
      avgCycleLength: cycleLength,
      avgPeriodLength: periodLength,
      regularity,
      lastPeriodDate: null
    };
  }
  const lastPeriodStart = new Date(haidStarts[haidStarts.length - 1]);

  const today = startOfDay(new Date());
  const diffDays = differenceInDays(today, startOfDay(lastPeriodStart)) + 1;

  const daysUntilNext = Math.round(cycleLength) - diffDays;
  const isOverdue = diffDays > cycleLength;
  const overdueDays = isOverdue ? diffDays - Math.round(cycleLength) : 0;
  const progress = Math.min(100, Math.max(0, (diffDays / cycleLength) * 100));

  return {
    currentDay: diffDays,
    daysUntilNext: Math.max(0, daysUntilNext),
    isOverdue,
    overdueDays,
    progress,
    avgCycleLength: cycleLength,
    avgPeriodLength: periodLength,
    regularity,
    lastPeriodDate: lastPeriodStart.toISOString()
  };
}

export function predictOvulation(user: User): OvulationResult | null {
  const prediction = predictNextPeriod(user);
  if (!prediction) return null;
  const predictedStartDate = new Date(prediction.predictedStartDate);
  
  // Ovulation = predictedStartDate minus 14 days
  const ovulationDate = subDays(predictedStartDate, 14);
  
  return {
    predictedOvulationDate: ovulationDate.getTime(),
    fertileWindowStart: subDays(ovulationDate, 5).getTime(),
    fertileWindowEnd: addDays(ovulationDate, 1).getTime()
  };
}

import { describe, expect, it } from 'vitest';

import { calculateCycleStats, getAverageCycleLength, predictNextPeriod } from '../prediction.ts';
import type { User } from '../types.ts';

const userWithStarts = (starts: string[]): User => ({
  madhhab: 'HANBALI',
  currentState: 'TAHARA',
  stateStartTime: Date.now(),
  knownAdahDays: null,
  avgHaidDuration: null,
  adahConfidence: 0,
  adahLedger: starts.map((start, index) => ({
    cycleNumber: index + 1,
    haidStart: new Date(start).getTime(),
    haidEnd: 0,
    haidDurationHours: 0,
    tuhrDurationDays: 0,
    bloodColorPattern: [],
    bloodThicknessPattern: [],
    istihadahEpisode: false,
    scholarConsulted: false,
  })),
  qadhaFastingDays: 0,
  qadhaCompleted: 0,
  qadhaRemaining: 0,
  pendingBloodStart: null,
});

describe('factual cycle calculations', () => {
  it('returns explicit insufficient data instead of a fallback', () => {
    const user = userWithStarts(['2026-01-01T00:00:00Z']);

    expect(getAverageCycleLength(user)).toBeNull();
    expect(predictNextPeriod(user)).toBeNull();
    expect(calculateCycleStats([], user)).toMatchObject({
      currentDay: null,
      avgCycleLength: null,
      daysUntilNext: null,
      progress: null,
    });
  });

  it('derives the average from each stored Haid-start interval', () => {
    const user = userWithStarts([
      '2026-01-01T00:00:00Z',
      '2026-01-31T00:00:00Z',
      '2026-03-02T00:00:00Z',
    ]);

    expect(getAverageCycleLength(user)).toBe(30);
    expect(predictNextPeriod(user)?.predictedStartDate).toBe(
      new Date('2026-04-01T00:00:00Z').getTime(),
    );
  });
});

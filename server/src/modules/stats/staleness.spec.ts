import { stalenessOf } from './staleness';

const DAY = 24 * 60 * 60 * 1000;
const now = Date.UTC(2026, 6, 28);

describe('stalenessOf', () => {
  it('calls a recent import fresh', () => {
    expect(stalenessOf(now, now)).toBe('fresh');
    expect(stalenessOf(now - 29 * DAY, now)).toBe('fresh');
  });

  it('ages past 30 days and goes stale past 90', () => {
    expect(stalenessOf(now - 30 * DAY, now)).toBe('aging');
    expect(stalenessOf(now - 89 * DAY, now)).toBe('aging');
    expect(stalenessOf(now - 90 * DAY, now)).toBe('stale');
    expect(stalenessOf(now - 400 * DAY, now)).toBe('stale');
  });

  it('treats a missing timestamp as stale, not fresh', () => {
    expect(stalenessOf(0, now)).toBe('stale');
  });
});

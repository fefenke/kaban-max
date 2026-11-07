import { beforeAll, describe, expect, it } from 'vitest';
import { getServiceStatusDisplay } from '../serviceStatusDisplay';

beforeAll(() => {
  (globalThis as unknown as { _: (value: string) => string })._ = (value) =>
    value;
});

describe('service status display', () => {
  it('reports running and stopped when nothing is in flight', () => {
    expect(getServiceStatusDisplay({ running: true, busy: null })).toEqual({
      label: 'The boar keeps the acorns in check',
      tone: 'success',
    });
    expect(getServiceStatusDisplay({ running: false, busy: null })).toEqual({
      label: 'The boar rests',
      tone: 'error',
    });
  });

  it('reports the operation instead of a readiness that is momentarily meaningless', () => {
    expect(getServiceStatusDisplay({ running: false, busy: 'apply' })).toEqual({
      label: 'The boar tidies up its grounds...',
      tone: 'progress',
    });
    expect(getServiceStatusDisplay({ running: true, busy: 'apply' })).toEqual({
      label: 'The boar tidies up its grounds...',
      tone: 'progress',
    });
  });

  it.each([
    ['start' as const, 'The boar comes out of the bushes...'],
    ['stop' as const, 'The boar wraps up the hunt...'],
    ['restart' as const, 'The boar stretches its hooves...'],
    ['apply' as const, 'The boar tidies up its grounds...'],
    ['install' as const, 'The boar updates its homestead...'],
  ])('names the %s operation', (busy, label) => {
    expect(getServiceStatusDisplay({ running: true, busy })).toEqual({
      label,
      tone: 'progress',
    });
  });
});

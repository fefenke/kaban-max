import { describe, expect, it, vi } from 'vitest';
import {
  recentFallbackEvents,
  observationSummary,
  lastFallbackSwitch,
  observationPeriod,
  renderFallbackObservation,
} from '../fallbackObservation';
import type { ClashAPI, KabanMax } from '../../../types';

describe('bounded fallback observation display', () => {
  it('uses a local container for the overview heading to avoid LuCI page-header styles', () => {
    const element = (
      tag: string,
      attrs: Record<string, unknown>,
      children: unknown,
    ) => ({ tag, attrs, children });
    vi.stubGlobal('E', element);
    try {
      const [overview] = renderFallbackObservation({
        outbounds: [],
        stableStatus: {
          state: 'primary',
          active: 'A',
          members: [],
          events: [],
          stats: {
            since: new Date().toISOString(),
            selected_since: new Date().toISOString(),
            switches_total: 0,
            backup_seconds: 0,
            members: [],
          },
        },
      } as unknown as KabanMax.FallbackInfo) as unknown as Array<{
        children: Array<{ tag: string; attrs: Record<string, unknown> }>;
      }>;
      expect(overview.children[0]).toMatchObject({
        tag: 'div',
        attrs: { class: 'kaban-observation__heading' },
      });
    } finally {
      vi.unstubAllGlobals();
    }
  });
  const now = Date.parse('2026-11-07T18:00:00Z');
  it('keeps only the latest 50 events within 24 hours without mutating input', () => {
    const events = Array.from({ length: 60 }, (_, i) => ({
      at: new Date(now - i * 1000).toISOString(),
      from: 'A',
      to: 'B',
      reason: 'test',
    }));
    events.push({
      at: new Date(now - 86400001).toISOString(),
      from: 'A',
      to: 'B',
      reason: 'old',
    });
    const kept = recentFallbackEvents(events, now);
    expect(kept).toHaveLength(50);
    expect(kept[49].at).toBe(new Date(now).toISOString());
    expect(events).toHaveLength(61);
  });
  it('does not mistake a check event for a switch', () => {
    const switched = {
      at: new Date(now).toISOString(),
      from: 'A',
      to: 'B',
      reason: 'switch',
    };
    expect(
      lastFallbackSwitch([
        switched,
        { ...switched, from: 'B', reason: 'suspect' },
      ]),
    ).toEqual(switched);
  });
  it('displays the rolling counters provided by the core without recomputing them from capped events', () => {
    const status: ClashAPI.StableFallbackStatus = {
      state: 'primary',
      active: 'A',
      members: [],
      events: [],
      stats: {
        since: '2026-11-05T18:00:00Z',
        selected_since: '2026-11-07T17:00:00Z',
        switches_total: 5,
        backup_seconds: 61,
        members: [
          {
            name: 'A',
            selected_seconds: 170000,
            connection_errors: 7,
            failed_checks: 3,
            switches_away: 2,
          },
        ],
      },
    };
    expect(observationSummary(status, now)).toMatchObject({
      selectedSeconds: 3600,
      switches: 5,
      backupSeconds: 61,
      connectionErrors: 7,
      failedChecks: 3,
    });
    expect(observationSummary({ ...status, stats: undefined }, now)).toBeNull();
  });
  it('labels a full day as a rolling period and a new session by elapsed time', () => {
    expect(observationPeriod('2026-11-05T18:00:00Z', now)).toEqual({
      fullDay: true,
      seconds: 86400,
    });
    expect(observationPeriod('2026-11-07T15:00:00Z', now)).toEqual({
      fullDay: false,
      seconds: 10800,
    });
    expect(observationPeriod('invalid', now)).toEqual({
      fullDay: false,
      seconds: 0,
    });
    expect(observationPeriod('2026-11-07T19:00:00Z', now)).toEqual({
      fullDay: false,
      seconds: 0,
    });
  });
});

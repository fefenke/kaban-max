import { describe, it, expect, vi } from 'vitest';
const calls = vi.hoisted(() => ({ ubus: vi.fn() }));
vi.mock('../../../../helpers/callUbus', () => ({ callUbus: calls.ubus }));
import {
  autoAction,
  canApply,
  sourceRows,
  targetRows,
  type AutoState,
} from '../autoRouting';

describe('automatic routing lists', () => {
  it('requires explicit backend permission, trusted identity and an unexpired decision for Apply', () => {
    const row = {
      ip: '203.0.113.7',
      domain: 'one.test',
      domain_known: true,
      status: 'proposed',
      apply_allowed: true,
      expires: '2099-01-01T00:00:00Z',
    };
    expect(canApply(row)).toBe(true);
    expect(canApply({ ...row, apply_allowed: false })).toBe(false);
    expect(canApply({ ...row, domain_known: false })).toBe(false);
    expect(canApply({ ...row, domain: '' })).toBe(false);
    expect(canApply({ ...row, expires: '2000-01-01T00:00:00Z' })).toBe(false);
    expect(canApply({ ...row, status: 'inconclusive' })).toBe(false);
  });
  const state: AutoState = {
    sources: [{ id: 's1', outbound: 'Zapret' }],
    candidates: [
      {
        id: 'c1',
        source: 'Zapret',
        ip: '203.0.113.7',
        domain: '',
        status: 'identity_unknown',
        network: 'tcp',
      },
    ],
    unattributed: [
      { ip: '2001:db8::7', domain: '', status: 'unattributed', network: 'tcp' },
    ],
    leases: [
      {
        id: 'a1',
        source: 'Zapret',
        source_id: 's1',
        ip: '203.0.113.7',
        domain: 'one.test',
        target: 'direct-out',
        target_section: 'bypass',
        status: 'applied',
      },
      {
        id: 'a2',
        source: 'Other',
        source_id: 's2',
        ip: '203.0.113.7',
        domain: 'two.test',
        target: 'WARP/profile',
        status: 'applied',
      },
    ],
    decisions: [],
    history: [],
  };
  it('retains no-domain IPs without calling them applied', () => {
    expect(sourceRows(state, 's1').candidates.map((row) => row.ip)).toEqual([
      '203.0.113.7',
      '2001:db8::7',
    ]);
    expect(sourceRows(state, 's1').leases.map((row) => row.domain)).toEqual([
      'one.test',
    ]);
  });
  it('shows separate virtual Direct and concrete WARP target entries', () => {
    expect(targetRows(state, 'bypass', 'Bypass').map((row) => row.id)).toEqual([
      'a1',
    ]);
    expect(targetRows(state, 'warp', 'WARP').map((row) => row.id)).toEqual([
      'a2',
    ]);
    expect(targetRows(state, 'unrelated', 'Other')).toEqual([]);
  });
  it('only sends an operation and backend record ID, never user supplied success/IP', async () => {
    calls.ubus.mockResolvedValue({
      success: true,
      data: { success: true, result: {} },
    });
    await autoAction('delete', 'a1');
    expect(calls.ubus).toHaveBeenLastCalledWith(
      expect.objectContaining({
        object: 'kabanmax',
        method: 'auto_action',
        params: { op: 'delete', id: 'a1' },
        retryUnavailable: false,
      }),
    );
  });
});

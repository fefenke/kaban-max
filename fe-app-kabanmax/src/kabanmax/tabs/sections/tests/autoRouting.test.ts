import { afterEach, describe, it, expect, vi } from 'vitest';
const calls = vi.hoisted(() => ({ ubus: vi.fn(), toast: vi.fn() }));
vi.mock('../../../../helpers/callUbus', () => ({ callUbus: calls.ubus }));
vi.mock('../../../../helpers/showToast', () => ({ showToast: calls.toast }));
import {
  autoAction,
  attachAutoRouting,
  routeText,
  recordStateText,
  canApply,
  sourceRows,
  targetRows,
  type AutoState,
} from '../autoRouting';
import { autoRecords, registryAction, registryNotice } from '../autoRecords';

afterEach(() => vi.unstubAllGlobals());

describe('automatic routing lists', () => {
  it('uses alternative results for pending records and reports only new applied failures', () => {
    vi.stubGlobal('_', (text: string) => text);
    for (const status of ['inconclusive', 'unchanged'])
      expect(recordStateText({ ip: '203.0.113.7', status })).toBe(
        'No working alternative found',
      );
    for (const status of ['detected', 'observing'])
      expect(recordStateText({ ip: '203.0.113.7', status })).toBe(
        'Queued for automatic checking',
      );
    expect(recordStateText({ ip: '203.0.113.7', status: 'checking' })).toBe(
      'Searching for a working alternative…',
    );
    expect(
      recordStateText({
        ip: '203.0.113.7',
        status: 'proposed',
        target: 'direct-out',
      }),
    ).toBe('Working alternative found: Direct');
    expect(recordStateText({ ip: '203.0.113.7', status: 'applied' })).toBe(
      'No new errors',
    );
    expect(
      recordStateText({
        ip: '203.0.113.7',
        status: 'applied',
        new_error: true,
      }),
    ).toBe('New connection error detected');
  });
  it('blocks enabling without an API key, honours unsaved key edits and always permits disabling', () => {
    vi.stubGlobal('_', (text: string) => text);
    vi.stubGlobal('form', {
      Flag: 'flag',
      TextValue: 'text',
      ListValue: 'list',
      DummyValue: 'dummy',
    });
    let savedKey = '';
    let editedKey: string | undefined;
    vi.stubGlobal('uci', { get: () => savedKey });
    const reset = vi.fn();
    const options: Record<string, CBIOption> = {};
    const map = {
      config: 'kabanmax',
      data: { get: () => savedKey },
      lookupOption: () =>
        editedKey === undefined
          ? null
          : [{ formvalue: () => editedKey }, 'settings'],
    };
    const section = {
      tab: vi.fn(),
      taboption: (_tab: string, _type: unknown, key: string) => {
        const option = {
          map,
          depends: vi.fn(),
          value: vi.fn(),
          getUIElement: () => ({ setValue: reset }),
        } as unknown as CBIOption;
        options[key] = option;
        return option;
      },
    };
    attachAutoRouting(section as unknown as CBISection);
    const enabled = options.auto_routing_enabled;
    expect(typeof enabled.validate).toBe('function');
    expect(enabled.validate('meta', '1')).not.toBe(true);
    expect(enabled.validate('meta', '0')).toBe(true);
    enabled.onchange!.call(enabled, {} as Event, 'meta', '1');
    expect(reset).toHaveBeenCalledWith('0');
    expect(calls.toast).toHaveBeenCalledWith(
      expect.stringContaining('Clash API key'),
      'error',
      8000,
    );
    savedKey = 'synthetic-key';
    expect(enabled.validate('meta', '1')).toBe(true);
    editedKey = '';
    expect(enabled.validate('meta', '1')).not.toBe(true);
    editedKey = 'new-synthetic-key';
    expect(enabled.validate('meta', '1')).toBe(true);
  });
  it('explains unavailable automation instead of presenting it as an empty registry', () => {
    vi.stubGlobal('_', (text: string) => text);
    expect(
      registryNotice(
        'Auto-routing API unavailable or rejected request: automatic_routing_unavailable',
      ),
    ).toBe(
      'Automatic routing is not active in the running configuration. Save & Apply the section settings and check the application log if activation fails.',
    );
    expect(registryNotice('Storage write failed')).toBe('Storage write failed');
  });
  it('shows the concrete proposed section and actionable check reasons', () => {
    vi.stubGlobal('_', (text: string) => text);
    expect(
      routeText({
        ip: '203.0.113.7',
        status: 'proposed',
        target: 'direct-out',
        target_name: 'direct-out',
      }),
    ).toBe('Direct');
    expect(
      routeText({
        ip: '203.0.113.7',
        status: 'proposed',
        target: 'direct-out',
      }),
    ).toBe('Direct');
    expect(
      routeText({ ip: '203.0.113.7', status: 'proposed', target: 'WARP' }),
    ).toBe('WARP');
    expect(routeText({ ip: '', status: 'inconclusive', source: 'META' })).toBe(
      'META',
    );
    expect(
      recordStateText({
        ip: '',
        status: 'inconclusive',
        reason: 'actual_destination_ip_unknown',
      }),
    ).toBe('No working alternative found');
    expect(
      recordStateText({
        ip: '203.0.113.7',
        status: 'checking',
        reason: 'checking:direct-out',
      }),
    ).toBe('Checking: Direct');
    expect(
      recordStateText({
        ip: '203.0.113.7',
        status: 'inconclusive',
        reason: 'no_working_alternative',
      }),
    ).toBe('No working alternative found');
  });
  it('splits a confirmed selection into bounded non-retrying batches with partial outcomes', async () => {
    calls.ubus
      .mockResolvedValueOnce({
        success: true,
        data: { success: true, done: 8, skipped: 0, failed: 0, results: [] },
      })
      .mockResolvedValueOnce({
        success: true,
        data: { success: true, done: 0, skipped: 1, failed: 0, results: [] },
      });
    const query = {
      source_section: 's1',
      status: 'pending',
      search: 'one.test',
      sort: 'newest',
      page: 1,
      page_size: 25,
    };
    const result = await registryAction(
      query,
      'apply',
      Array.from({ length: 9 }, (_, i) => `r${i}`),
    );
    expect(result).toMatchObject({ done: 8, skipped: 1, failed: 0 });
    const requests = calls.ubus.mock.calls
      .slice(-2)
      .map(([request]) => request);
    expect(
      requests.every((request) => request.retryUnavailable === false),
    ).toBe(true);
    expect(
      requests.map((request) => JSON.parse(request.params.id).ids.length),
    ).toEqual([8, 1]);
    expect(
      requests.every(
        (request) => JSON.parse(request.params.id).source_section === 's1',
      ),
    ).toBe(true);
  });
  it('freezes manual targets and query across bounded batches', async () => {
    const query = {
      source_section: 'zap',
      status: 'pending',
      search: 'api.example',
      sort: 'newest',
      page: 1,
      page_size: 25,
    };
    const ids = Array.from({ length: 9 }, (_, i) => `manual${i}`);
    const targets = Object.fromEntries(ids.map((id) => [id, 'warp-out']));
    calls.ubus
      .mockImplementationOnce(async () => {
        query.search = 'changed';
        targets.manual8 = 'direct-out';
        return {
          success: true,
          data: { success: true, done: 8, skipped: 0, failed: 0, results: [] },
        };
      })
      .mockResolvedValueOnce({
        success: true,
        data: { success: true, done: 1, skipped: 0, failed: 0, results: [] },
      });
    expect((await registryAction(query, 'apply', ids, targets)).done).toBe(9);
    const requests = calls.ubus.mock.calls
      .slice(-2)
      .map(([request]) => JSON.parse(request.params.id));
    expect(
      requests.map((request) => Object.keys(request.targets).length),
    ).toEqual([8, 1]);
    expect(requests[1]).toMatchObject({
      search: 'api.example',
      targets: { manual8: 'warp-out' },
    });
  });
  it('requests one bounded source page without downloading the full state', async () => {
    calls.ubus.mockResolvedValue({
      success: true,
      data: { rows: [], total: 0, page: 1, counts: {}, version: 1 },
    });
    const query = {
      source_section: 's1',
      status: 'pending',
      search: 'example',
      sort: 'newest',
      page: 2,
      page_size: 25,
    };
    await autoRecords(query);
    expect(calls.ubus).toHaveBeenLastCalledWith(
      expect.objectContaining({ method: 'auto_records', params: query }),
    );
  });

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
        failure: {
          id: 'error-c1',
          source_id: 's1',
          message: 'synthetic timeout',
          at: '2026-11-16T00:00:00Z',
        },
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

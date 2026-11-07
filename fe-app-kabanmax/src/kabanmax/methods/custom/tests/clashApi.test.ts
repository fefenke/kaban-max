import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  config: vi.fn(),
  clashApi: vi.fn(),
}));

vi.mock('../getConfigSections', () => ({ getConfigSections: mocks.config }));
vi.mock('../../shell', () => ({
  KabanMaxShellMethods: { clashApi: mocks.clashApi },
}));
vi.mock('../../../../helpers/getClashApiUrl', () => ({
  canUseDirectClashApi: () => true,
  getClashApiUrl: () => 'http://router.example:9090',
}));

beforeEach(() => {
  vi.resetModules();
  mocks.config.mockResolvedValue([
    { '.type': 'settings', latency_test_url: 'https://example.com/check' },
  ]);
  mocks.clashApi.mockReset();
  mocks.clashApi.mockResolvedValue({
    success: true,
    data: { status: 204, body: '' },
  });
});

afterEach(() => vi.unstubAllGlobals());

it('loads cold dashboard proxies through CLI while the direct controller probe is pending', async () => {
  vi.stubGlobal(
    'fetch',
    vi.fn(() => new Promise(() => {})),
  );
  mocks.clashApi.mockResolvedValue({
    success: true,
    data: { status: 200, body: '{"proxies":{}}' },
  });
  const { getClashApiProxies } = await import('../clashApi');
  const result = getClashApiProxies();

  await vi.waitFor(() =>
    expect(mocks.clashApi).toHaveBeenCalledWith('GET', '/proxies', ''),
  );
  expect(await result).toEqual({ success: true, data: { proxies: {} } });
});

it('uses the direct dashboard path after the background probe responds', async () => {
  const fetchMock = vi.fn().mockResolvedValue({
    status: 200,
    text: async () => '{"proxies":{}}',
  });
  vi.stubGlobal('fetch', fetchMock);
  mocks.clashApi.mockResolvedValue({
    success: true,
    data: { status: 200, body: '{"proxies":{}}' },
  });
  const { getClashApiProxies } = await import('../clashApi');
  await getClashApiProxies();
  await vi.waitFor(() =>
    expect(fetchMock).toHaveBeenCalledWith(
      'http://router.example:9090/version',
      expect.anything(),
    ),
  );
  mocks.clashApi.mockClear();

  await getClashApiProxies();

  expect(fetchMock).toHaveBeenLastCalledWith(
    'http://router.example:9090/proxies',
    expect.anything(),
  );
  expect(mocks.clashApi).not.toHaveBeenCalled();
});

it('chooses the CLI before sending concurrent first mutations to an unreachable controller', async () => {
  const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
  vi.stubGlobal('fetch', fetchMock);
  const { updateClashApiProxyProviders } = await import('../clashApi');

  expect((await updateClashApiProxyProviders(['one', 'two'])).success).toBe(
    true,
  );
  expect(fetchMock).toHaveBeenCalledOnce();
  expect(fetchMock).toHaveBeenCalledWith(
    'http://router.example:9090/version',
    expect.anything(),
  );
  expect(mocks.clashApi).toHaveBeenCalledTimes(2);
});

it('asks for the exit of an outbound by its encoded tag', async () => {
  const report = {
    outbound: 'main/sub1/🇳🇱 Node',
    ipv4: { address: '203.0.113.7', country: 'NL' },
    ipv6: { error: 'connection refused' },
  };
  const fetchMock = vi.fn().mockResolvedValue({
    status: 200,
    text: async () => JSON.stringify(report),
  });
  vi.stubGlobal('fetch', fetchMock);
  const { getClashApiProxyExit } = await import('../clashApi');

  expect(await getClashApiProxyExit('main-out/selector')).toEqual({
    success: true,
    data: report,
  });
  expect(fetchMock).toHaveBeenLastCalledWith(
    'http://router.example:9090/proxies/main-out%2Fselector/exit?timeout=5000',
    expect.anything(),
  );
});

it('loads the configured test URL before the first latency request', async () => {
  const fetchMock = vi
    .fn()
    .mockResolvedValue({ status: 200, text: async () => '{}' });
  vi.stubGlobal('fetch', fetchMock);
  const { getClashApiProxyLatency } = await import('../clashApi');

  await getClashApiProxyLatency('node');
  expect(fetchMock).toHaveBeenLastCalledWith(
    'http://router.example:9090/proxies/node/delay?url=https%3A%2F%2Fexample.com%2Fcheck&timeout=5000',
    expect.anything(),
  );
});

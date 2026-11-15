import { describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ execute: vi.fn() }));
vi.mock('../../../../helpers/executeShellCommand', () => ({
  executeShellCommand: mocks.execute,
}));
import { requestRouteForecast, formatRouteForecast } from '../routeForecast';

describe('read-only route forecast', () => {
  it('passes destination and scope as distinct exec arguments without a shell', async () => {
    mocks.execute.mockResolvedValue({
      code: 0,
      stdout: '{"predicted":{"status":"unknown"}}',
    });
    const result = await requestRouteForecast('example.test', '@system', '443');
    expect(mocks.execute).toHaveBeenLastCalledWith({
      command: '/usr/bin/kabanmax',
      args: ['check_route', 'example.test', '@system', '443'],
      timeout: 15000,
    });
    expect(result).toEqual({ predicted: { status: 'unknown' } });
  });
  it('reports execution and malformed response errors', async () => {
    mocks.execute.mockResolvedValue({ code: 1, stderr: 'failed' });
    await expect(
      requestRouteForecast('example.test', '', '443'),
    ).rejects.toThrow('failed');
    mocks.execute.mockResolvedValue({ code: 0, stdout: 'not json' });
    await expect(
      requestRouteForecast('example.test', '', '443'),
    ).rejects.toThrow();
  });
  it('never presents a predicted route as verified or hides an unknown blocker', () => {
    const text = formatRouteForecast({
      predicted: {
        status: 'unknown',
        reason: 'matcher_requires_core_state',
        rule_index: 2,
      },
    });
    expect(text).toContain('matcher_requires_core_state');
    expect(text).toContain('2');
    expect(text).toContain('verified');
    expect(text).toContain('not_run');
  });
});

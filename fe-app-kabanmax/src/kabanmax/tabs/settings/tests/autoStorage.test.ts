import { describe, expect, it, vi } from 'vitest';
import { addAutoStorageOptions } from '../form/autoStorage';
describe('autorouting storage settings', () => {
  it('offers daily saving and memory budget without an expiry control', () => {
    vi.stubGlobal('_', (s: string) => s);
    vi.stubGlobal('form', { Value: 'value' });
    const options: Record<string, CBIOption> = {};
    const section = {
      option: (_type: unknown, name: string) =>
        (options[name] = {} as CBIOption),
    };
    addAutoStorageOptions(section as unknown as CBISection);
    expect(options.auto_routing_save_interval.default).toBe('1d');
    expect(
      options.auto_routing_save_interval.validate!('settings', '12h'),
    ).toBe(true);
    expect(
      options.auto_routing_save_interval.validate!('settings', '1s'),
    ).not.toBe(true);
    expect(options.auto_routing_cleanup_interval).toBeUndefined();
    expect(options.auto_routing_memory_mib.validate!('settings', '4')).toBe(
      true,
    );
    for (const value of ['0', '33', '1.5'])
      expect(
        options.auto_routing_memory_mib.validate!('settings', value),
      ).not.toBe(true);
    vi.unstubAllGlobals();
  });
});

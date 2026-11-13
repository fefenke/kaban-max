import { describe, expect, it, vi } from 'vitest';
import { addPreRoutingResolveOptions } from '../../tabs/settings/preRoutingResolve';

describe('pre-routing DNS settings', () => {
  it('offers disabled, all and selected, and requires valid selected domains', () => {
    vi.stubGlobal('form', { ListValue: 'list', TextValue: 'text' });
    const options: Record<string, CBIOption & { values: string[] }> = {};
    const section = {
      option: (_type: unknown, name: string) => {
        const item = {
          values: [] as string[],
          value(value: string) {
            this.values.push(value);
          },
          depends: () => {},
        };
        options[name] = item as unknown as CBIOption & { values: string[] };
        return item;
      },
    };
    addPreRoutingResolveOptions(section as unknown as CBISection);
    expect(options.pre_routing_resolve_mode.values).toEqual([
      'disabled',
      'all',
      'selected',
    ]);
    expect(options.pre_routing_resolve_mode.default).toBe('disabled');
    const domains = options.pre_routing_resolve_domains;
    expect(domains.rmempty).not.toBe(false);
    expect(domains.validate('settings', 'example.org\nfull:only.example')).toBe(
      true,
    );
    expect(domains.validate('settings', '')).not.toBe(true);
    vi.unstubAllGlobals();
  });
});

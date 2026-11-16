import { describe, expect, it } from 'vitest';
import { createHarness } from '../lib/luciForm.js';

describe('source-only automatic routing controls', () => {
  it('gates every tab option on Zapret2 and retains hidden stored values', async () => {
    const h = createHarness();
    const map = new h.form.Map('kabanmax');
    const grid = map.section(h.form.GridSection, 'section');
    h.bundle.createSectionContent(grid);
    const options = grid.children.filter((o) => o.tab === 'auto_routing');
    // Harness versions store the tab name differently; identify by option name.
    const controls = options.length
      ? options
      : grid.children.filter(
          (o) =>
            o.option.startsWith('auto_routing_') ||
            o.option === '_automatic_routes',
        );
    expect(controls.length).toBeGreaterThanOrEqual(8);
    for (const control of controls) {
      expect(control.deps.length).toBeGreaterThan(0);
      for (const dependency of control.deps)
        expect(dependency.action).toBe('zapret2');
      if (control.option !== '_automatic_routes')
        expect(control.retain).toBe(true);
    }
    expect(
      grid.children.find((o) => o.option === 'auto_routing_ip_only').readonly,
    ).not.toBe(true);
    expect(
      grid.children.some((o) => o.option === 'auto_routing_direct_section'),
    ).toBe(false);
    expect(
      grid.children.some((o) => o.option === 'auto_routing_probe_zapret'),
    ).toBe(false);
    h.uci.add('kabanmax', 'section', 'zap');
    Object.assign(h.store.get('zap'), {
      action: 'zapret2',
      auto_routing_warp: 'WARP/saved',
    });
    const warp = grid.children.find((o) => o.option === 'auto_routing_warp');
    for (let i = 0; i < 10; i++) {
      expect(await warp.load('zap')).toBe('WARP/saved');
      expect(warp.keylist).toEqual(['', 'WARP/saved']);
    }
  });
});
